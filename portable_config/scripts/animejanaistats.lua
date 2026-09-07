local open = io.open

local showingMessage = false
local MAX_DURATION = 2147483
local UPDATE_INTERVAL = 1.0

local updateTimer = nil
local lastDropCount = nil
local lastSampleTime = nil
local cachedAnimeJaNaiStatus = nil
local lastStatusReadTime = 0

local function read_file(path)
    local file = open(path, "r")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end

local function reset_realtime_sample()
    lastDropCount = mp.get_property_number("vo-drop-frame-count", 0) or 0
    lastSampleTime = mp.get_time()
end

local function get_animejanai_status(now)
    -- AI 状态日志最多每 5 秒读取一次，避免不必要的磁盘 I/O。
    if cachedAnimeJaNaiStatus ~= nil and (now - lastStatusReadTime) < 5 then
        return cachedAnimeJaNaiStatus
    end

    local vf = mp.get_property("vf") or ""
    if vf == "" then
        cachedAnimeJaNaiStatus = "AI 已关闭"
    else
        local data_file_path = mp.command_native({"expand-path", "~~/../animejanai/currentanimejanai.log"})
        local message = read_file(data_file_path)
        if not message or message == "" then
            message = "AnimeJaNai 状态读取失败；按 ~ 键在控制台查看错误信息"
        end
        cachedAnimeJaNaiStatus = message
    end

    lastStatusReadTime = now
    return cachedAnimeJaNaiStatus
end

local function get_realtime_fps(now)
    local paused = mp.get_property_bool("pause", false)
    local targetFps = mp.get_property_number("estimated-vf-fps", nil)
    local speed = mp.get_property_number("speed", 1.0) or 1.0
    local dropCount = mp.get_property_number("vo-drop-frame-count", 0) or 0

    if targetFps then
        targetFps = targetFps * speed
    end

    if not lastDropCount or not lastSampleTime or paused then
        lastDropCount = dropCount
        lastSampleTime = now
        return paused and 0 or targetFps, 0, dropCount, targetFps
    end

    local elapsed = now - lastSampleTime
    local dropped = dropCount - lastDropCount
    if dropped < 0 then dropped = 0 end

    local dropRate = 0
    if elapsed > 0 then
        dropRate = dropped / elapsed
    end

    local effectiveFps = nil
    if targetFps then
        effectiveFps = math.max(0, targetFps - dropRate)
    end

    lastDropCount = dropCount
    lastSampleTime = now

    return effectiveFps, dropRate, dropCount, targetFps
end

local function render_stats()
    if not showingMessage then return end

    local now = mp.get_time()
    local status = get_animejanai_status(now)
    local effectiveFps, dropRate, dropCount, targetFps = get_realtime_fps(now)

    local fpsText
    if effectiveFps then
        fpsText = string.format("实时有效 FPS: %.2f", effectiveFps)
    else
        fpsText = "实时有效 FPS: --"
    end

    local targetText = ""
    if targetFps then
        targetText = string.format("  / 目标 %.2f", targetFps)
    end

    local realtime = string.format(
        "%s%s\n每秒丢帧: %.2f\n累计输出丢帧: %d",
        fpsText,
        targetText,
        dropRate,
        dropCount
    )

    mp.osd_message(status .. "\n\n" .. realtime, MAX_DURATION)
end

function show_animejanai_stats()
    if showingMessage then
        if updateTimer then
            updateTimer:kill()
            updateTimer = nil
        end
        mp.osd_message("")
        showingMessage = false
        return
    end

    showingMessage = true
    cachedAnimeJaNaiStatus = nil
    lastStatusReadTime = 0
    reset_realtime_sample()
    render_stats()

    -- 仅在 Ctrl+J 面板显示期间每秒采样一次；隐藏后定时器彻底停止。
    -- 只读取少量 mpv 属性，不做逐帧回调，不参与视频处理链。
    updateTimer = mp.add_periodic_timer(UPDATE_INTERVAL, render_stats)
end

mp.register_event("file-loaded", function()
    cachedAnimeJaNaiStatus = nil
    lastStatusReadTime = 0
    reset_realtime_sample()
end)

mp.add_key_binding("Ctrl+j", "show_animejanai_stats", show_animejanai_stats)

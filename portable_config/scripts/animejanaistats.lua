local open = io.open

local showingMessage = false
local MAX_DURATION = 2147483
local UPDATE_INTERVAL = 0.25
local FPS_WINDOW = 2.0
local FULL_SPEED_RATIO = 0.98

local updateTimer = nil
local cachedAnimeJaNaiStatus = nil
local lastStatusReadTime = 0

-- 真正的实时帧率：统计 mpv 当前视频时间戳实际推进了多少次。
-- 不再使用 estimated-vf-fps 充当“实际 FPS”；它只用来提供目标值。
local frameTimes = {}
local lastTimePos = nil
local sampleStartTime = nil
local observingTimePos = false

local function read_file(path)
    local file = open(path, "r")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end

local function reset_fps_sample()
    frameTimes = {}
    lastTimePos = nil
    sampleStartTime = mp.get_time()
end

local function prune_frame_times(now)
    local cutoff = now - FPS_WINDOW
    local first = 1
    while first <= #frameTimes and frameTimes[first] < cutoff do
        first = first + 1
    end

    if first > 1 then
        local newTimes = {}
        for i = first, #frameTimes do
            newTimes[#newTimes + 1] = frameTimes[i]
        end
        frameTimes = newTimes
    end
end

local function on_time_pos(_, pos)
    if not showingMessage or pos == nil then return end
    if mp.get_property_bool("pause", false) then
        lastTimePos = pos
        return
    end

    local now = mp.get_time()

    if lastTimePos ~= nil then
        local delta = pos - lastTimePos
        -- 正常前进的一次 time-pos 更新按 1 个实际输出帧计。
        -- 大跳转通常是 seek，不把一次跳转误算成很多帧。
        if delta > 0 and delta < 0.5 then
            frameTimes[#frameTimes + 1] = now
        elseif delta < 0 or delta >= 0.5 then
            -- seek / 大跨度跳转后重新开始采样。
            frameTimes = {}
            sampleStartTime = now
        end
    end

    lastTimePos = pos
    prune_frame_times(now)
end

local function start_frame_observer()
    if observingTimePos then return end
    reset_fps_sample()
    mp.observe_property("time-pos", "number", on_time_pos)
    observingTimePos = true
end

local function stop_frame_observer()
    if not observingTimePos then return end
    mp.unobserve_property(on_time_pos)
    observingTimePos = false
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

local function get_actual_fps(now)
    if mp.get_property_bool("pause", false) then
        return 0
    end

    prune_frame_times(now)

    if not sampleStartTime then
        sampleStartTime = now
    end

    local elapsed = now - sampleStartTime
    if elapsed < 0.75 then
        return nil
    end

    local window = math.min(FPS_WINDOW, elapsed)
    if window <= 0 then return nil end

    return #frameTimes / window
end

local function get_target_fps()
    local fps = mp.get_property_number("estimated-vf-fps", nil)
    local speed = mp.get_property_number("speed", 1.0) or 1.0
    if fps then
        return fps * speed
    end
    return nil
end

local function render_stats()
    if not showingMessage then return end

    local now = mp.get_time()
    local status = get_animejanai_status(now)
    local actualFps = get_actual_fps(now)
    local targetFps = get_target_fps()

    local realtime
    if actualFps == nil then
        if targetFps then
            realtime = string.format("当前实际 FPS: 采样中…  / 目标 %.2f", targetFps)
        else
            realtime = "当前实际 FPS: 采样中…"
        end
    elseif targetFps then
        local full = actualFps >= targetFps * FULL_SPEED_RATIO
        realtime = string.format(
            "当前实际 FPS: %.2f  / 目标 %.2f",
            actualFps,
            targetFps
        )
    else
        realtime = string.format("当前实际 FPS: %.2f", actualFps)
    end

    mp.osd_message(status .. "\n\n" .. realtime, MAX_DURATION)
end

function show_animejanai_stats()
    if showingMessage then
        if updateTimer then
            updateTimer:kill()
            updateTimer = nil
        end
        stop_frame_observer()
        mp.osd_message("")
        showingMessage = false
        return
    end

    showingMessage = true
    cachedAnimeJaNaiStatus = nil
    lastStatusReadTime = 0
    start_frame_observer()
    render_stats()

    -- Ctrl+J 面板显示时每 0.25 秒刷新一次；实际 FPS 使用最近 2 秒真实帧推进统计。
    updateTimer = mp.add_periodic_timer(UPDATE_INTERVAL, render_stats)
end

mp.register_event("file-loaded", function()
    cachedAnimeJaNaiStatus = nil
    lastStatusReadTime = 0
    reset_fps_sample()
end)

mp.register_event("seek", function()
    reset_fps_sample()
end)

mp.observe_property("pause", "bool", function(_, paused)
    if showingMessage then
        reset_fps_sample()
        if paused then
            render_stats()
        end
    end
end)

mp.add_key_binding("Ctrl+j", "show_animejanai_stats", show_animejanai_stats)

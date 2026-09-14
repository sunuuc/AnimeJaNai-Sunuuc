-- FPS is unique video frames submitted through VO, not monitor scanout.
-- Requires this distribution's vo-presented-frame-count native property.
local mp = require 'mp'
local visible = false
local timer
local samples = {}
local status, status_time = nil, -math.huge
local WINDOW, INTERVAL = 2.0, 0.25

local function reset()
    samples = {}
    status, status_time = nil, -math.huge
end

local function actual(now)
    local n = mp.get_property_number('vo-presented-frame-count')
    if not n or n < 0 then samples = {}; return nil end
    if mp.get_property_bool('pause', false) then samples = {}; return 0 end
    local last = samples[#samples]
    if last and (n < last.n or now <= last.t or now - last.t > 4) then samples = {} end
    samples[#samples + 1] = {t=now, n=n}
    -- Retain one sample just before the window boundary; use its real time.
    while #samples > 2 and samples[2].t <= now - WINDOW do table.remove(samples, 1) end
    local first = samples[1]
    if now - first.t < 0.75 then return nil end
    return (n - first.n) / (now - first.t)
end

local function ai_status(now)
    if status and now - status_time < 2 then return status end
    status_time = now
    local active = false
    for _, f in ipairs(mp.get_property_native('vf', {}) or {}) do
        if f.name == 'animejanai' or f.name == 'vapoursynth' then active = true end
    end
    if not active then status = 'AI 已关闭'; return status end
    local path = mp.get_property_native('user-data/animejanai/stats-path')
        or mp.command_native({'expand-path', '~~/../animejanai/currentanimejanai.log'})
    local file = path and io.open(path, 'r')
    status = file and file:read(65536) or nil
    if file then file:close() end
    if not status or status == '' then status = 'AnimeJaNai 状态暂不可用' end
    return status
end

local function render()
    if not visible then return end
    local now = mp.get_time()
    local fps = actual(now)
    local target = mp.get_property_number('estimated-vf-fps')
    local speed = mp.get_property_number('speed', 1) or 1
    local line = '当前实际 FPS: ' .. (fps and string.format('%.2f', fps) or '--')
    line = line .. ' / 目标 ' .. (target and target > 0 and string.format('%.2f', target * speed) or '--')
    mp.osd_message(ai_status(now) .. '\n\n' .. line, 2147483)
end

local function toggle()
    visible = not visible
    reset()
    if visible then
        render()
        timer = mp.add_periodic_timer(INTERVAL, render)
    else
        if timer then timer:kill(); timer = nil end
        mp.osd_message('')
    end
end
for _, event in ipairs({'start-file', 'file-loaded', 'seek', 'playback-restart', 'end-file'}) do
    mp.register_event(event, reset)
end
mp.observe_property('pause', 'bool', function() reset(); if visible then render() end end)
mp.observe_property('speed', 'number', reset)
mp.observe_property('vf', 'native', reset)
mp.add_key_binding('Ctrl+j', 'show_animejanai_stats', toggle)

-- Poll only during active AI playback. Missing/truncated log != build success.
local mp = require 'mp'
local msg = require 'mp.msg'
local options = require 'mp.options'
local o = {auto_pause=true, poll_interval=0.5, stats_path=''}
options.read_options(o, 'animejanai_engine_monitor')
o.poll_interval = math.max(0.25, tonumber(o.poll_interval) or 0.5)
local timer, building, we_paused = nil, false, false
local started_at, build_name, build_res = 0, '?', '?'
local poll_pending
local function reset()
    if we_paused and mp.get_property_bool('pause') then mp.set_property_bool('pause',false) end
    building, we_paused = false, false
    poll_pending=nil
    if timer then timer:kill(); timer=nil end
end
local function poll()
    if we_paused and not mp.get_property_bool('pause') then we_paused=false end
    local path = o.stats_path ~= '' and mp.command_native({'expand-path',o.stats_path})
        or mp.get_property('user-data/animejanai/stats-path')
        or mp.command_native({'expand-path','~~/../animejanai/currentanimejanai.log'})
    local file = io.open(path, 'r')
    local text = file and file:read(65536) or nil
    if file then file:close() end
    -- A missing file or an incomplete rewrite provides no completion evidence.
    if not text or text == '' then
        if building then mp.commandv('vf-command','aji','poll','1') end
        return
    end
    local busy = text:find('Building TensorRT engine',1,true) ~= nil
    if busy and not building then
        building=true;started_at=mp.get_time()
        if o.auto_pause and not mp.get_property_bool('pause') then
            mp.set_property_bool('pause',true);we_paused=true
        end
    elseif building and not busy then
        -- Require a stable snapshot across two reads: native writers truncate
        -- before rewriting, so a single nonempty prefix can still be partial.
        if poll_pending ~= text then poll_pending=text;return end
        building=false;poll_pending=nil
        local failed=text:find('build FAILED',1,true) ~= nil
        if we_paused then mp.set_property_bool('pause',false);we_paused=false end
        msg.info(failed and 'TensorRT 引擎构建失败' or 'TensorRT 引擎构建结束')
        mp.osd_message(failed and 'AnimeJaNai：引擎构建失败，请查看模型旁的 .build.log'
            or 'AnimeJaNai：引擎已就绪',5)
    end
    if busy then poll_pending=nil end
    if building then
        local n,r=text:match('Building TensorRT engine for ([^%s]+) for ([^%s]+)')
        if n then build_name,build_res=n,r end
        mp.osd_message(string.format('AnimeJaNai：正在构建 %s（%s），已用 %d 秒\n%s',
            build_name,build_res,math.floor(mp.get_time()-started_at),
            we_paused and '构建完成后恢复播放；手动继续播放将取消自动暂停。' or '后台构建中。'),o.poll_interval+0.5)
        mp.commandv('vf-command','aji','poll','1')
    end
end
local function start()
    reset()
    for _, f in ipairs(mp.get_property_native('vf', {}) or {}) do
        if f.name=='animejanai' then timer=mp.add_periodic_timer(o.poll_interval,poll);poll();break end
    end
end
mp.register_event('file-loaded',start)
mp.register_event('end-file',reset)
mp.observe_property('vf','native',function()
    if not mp.get_property_bool('idle-active',true) then start() end
end)

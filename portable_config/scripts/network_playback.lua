-- Playback policy and bounded local diagnostics. Never opens a URL or starts a worker.
local mp=require 'mp'
local utils=require 'mp.utils'
local message=require 'mp.msg'
local diagnostic=mp.command_native({'expand-path','~~/playback-diagnostic.json'})
local state={phase='idle',network=false,has_media=false,http_status=nil}
local history={}
local opened_at,loaded_at,opening_sampler=nil,nil,nil
local pending_failure
local function kill_sampler()
    if opening_sampler then opening_sampler:kill();opening_sampler=nil end
end
local function cancel_failure()
    if pending_failure then pending_failure:kill();pending_failure=nil end
end
local function remote(path)
    return type(path)=='string' and path:match('^%a[%w+.-]*://') and not path:match('^[Ff][Ii][Ll][Ee]://')
end
local function persist()
    mp.set_property_native('user-data/player_ui/playback',state)
    local json=utils.format_json({version=2,events=history})
    local f=io.open(diagnostic,'wb');if f then f:write(json);f:close() end
end
local function sample_opening()
    opening_sampler=nil
    if state.phase~='opening' or not state.network or not opened_at then return end
    local samples=state.opening_samples or {}
    samples[#samples+1]={elapsed_ms=math.floor((mp.get_time()-opened_at)*1000+.5),
        cache_speed_bps=mp.get_property_number('cache-speed',0),
        cache_idle=mp.get_property_bool('demuxer-cache-idle',false)}
    while #samples>80 do table.remove(samples,1) end
    state.opening_samples=samples
    for i=#history,1,-1 do
        if history[i].phase=='opening' then history[i].opening_samples=samples;break end
    end
    persist()
    opening_sampler=mp.add_timeout(.5,sample_opening)
end
local function record(phase)
    local now=mp.get_time()
    if phase=='opening' then
        kill_sampler();opened_at=now;loaded_at=nil;state.opening_samples={}
        state.open_to_loaded_ms=nil;state.loaded_to_playing_ms=nil;state.open_to_playing_ms=nil
    elseif phase=='loaded' and opened_at then
        state.open_to_loaded_ms=math.floor((now-opened_at)*1000+.5);loaded_at=now
        kill_sampler()
    elseif phase=='playing' and opened_at then
        state.open_to_playing_ms=math.floor((now-opened_at)*1000+.5)
        if loaded_at then state.loaded_to_playing_ms=math.floor((now-loaded_at)*1000+.5) end
        kill_sampler()
    end
    state.phase=phase
    state.has_media=mp.get_property('path','')~=''
    state.playlist_count=mp.get_property_number('playlist-count',0)
    state.position=mp.get_property_number('playlist-pos',-1)
    state.network_thumbnails=false;state.playlist_prefetch=false
    history[#history+1]={time=os.date('!%Y-%m-%dT%H:%M:%SZ'),phase=phase,network=state.network,
        has_media=state.has_media,playlist_count=state.playlist_count,position=state.position,http_status=state.http_status,
        elapsed_ms=opened_at and math.floor((now-opened_at)*1000+.5) or nil,
        open_to_loaded_ms=state.open_to_loaded_ms,loaded_to_playing_ms=state.loaded_to_playing_ms}
    while #history>24 do table.remove(history,1) end
    persist()
    if phase=='opening' and state.network then opening_sampler=mp.add_timeout(.5,sample_opening) end
end
local function set(name,value)
    local ok,err=mp.set_property(name,value)
    if not ok then message.error('Playback policy option '..name..': '..tostring(err)) end
end
set('prefetch-playlist','no')
mp.register_event('start-file',cancel_failure)
mp.add_hook('on_load',-1000,function()
    cancel_failure()
    state.network=not not remote(mp.get_property('stream-open-filename',mp.get_property('path','')))
    state.http_status=nil
    set('prefetch-playlist','no')
    if state.network then
        for name,value in pairs({['sub-auto']='no',['audio-file-auto']='no',['cover-art-auto']='no',
            ['ytdl']='no',['demuxer-cache-wait']='no',['cache-pause-wait']='1',
            -- Do not hold the first frame for the configured startup cache. Keep
            -- cache-pause enabled so playback can still recover from later stalls.
            ['cache-pause-initial']='no',
            -- Read three minutes ahead and keep the cache in memory, but size it
            -- from the bitrate rather than from a round number: three minutes of
            -- 1080p is 110-260 MiB, and even 4K stays under 550 MiB. 768 MiB is
            -- therefore about 1.5x the worst case, while the 2 GiB this used to
            -- ask for pushed committed memory past 3.9 GB because mpv counts the
            -- packet budget against the process commit even when the packets are
            -- never all resident. The backward half is a further slice of that
            -- same total, so it is kept well under it (768M total, 384M back =
            -- 384M of already-played data plus 384M of readahead).
            ['demuxer-readahead-secs']='180',['cache-secs']='180',
            ['demuxer-max-bytes']='768M',['demuxer-max-back-bytes']='384M',
            -- The video/audio decoder queues default to 512M/1M and are counted
            -- in the same committed pool as the packet cache. 256M is still far
            -- more than the decoder needs to stay ahead of playback at 1080p
            -- (the AnimeJaNai filter chain is the real bottleneck, not the
            -- decoders) and removes half a gigabyte of headroom the player was
            -- reserving and never using.
            ['vd-queue-max-bytes']='256M',['ad-queue-max-bytes']='512K',
            ['network-timeout']='20'}) do
            set('file-local-options/'..name,value)
        end
        mp.commandv('change-list','demuxer-lavf-o','append','http_multiple=0')
    end
    record('opening')
end)
mp.enable_messages('error')
mp.register_event('log-message',function(e)
    local code=e.text and (e.text:match('HTTP error (%d%d%d)') or e.text:match('HTTP/%d[%d.]* (%d%d%d)'))
    if code then state.http_status=tonumber(code) end
end)
mp.register_event('file-loaded',function()cancel_failure();record('loaded')end)
mp.register_event('playback-restart',function()
    if state.phase~='playing' then record('playing') end
end)
mp.register_event('end-file',function(e)
    if e.reason=='error' then
        record('failed')
        local code=state.http_status
        local text=code==401 and '无法打开视频：服务器要求登录（HTTP 401）'
            or code==403 and '无法打开视频：服务器拒绝访问（HTTP 403）'
            or code==404 and '无法打开视频：媒体不存在或链接已失效（HTTP 404）'
            or code and ('无法打开视频：HTTP '..code)
            or '无法打开视频。请检查播放链接或本地诊断记录。'
        -- mpv may advance to another playlist entry after this failure. Show an
        -- error only if no next entry starts; a failed attempt is not a failed
        -- playback session.
        cancel_failure()
        pending_failure=mp.add_timeout(.75,function()
            pending_failure=nil
            if state.phase=='failed' and mp.get_property_bool('idle-active',false) then
                mp.osd_message(text,8)
            end
        end)
    elseif e.reason=='eof' then record('ended')
    elseif e.reason=='stop' then record('stopped') end
end)
mp.register_event('shutdown',function()kill_sampler();cancel_failure()end)
record('idle')

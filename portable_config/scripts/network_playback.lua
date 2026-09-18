-- Playback policy and bounded local diagnostics. Never opens a URL or starts a worker.
local mp=require 'mp'
local utils=require 'mp.utils'
local message=require 'mp.msg'
local diagnostic=mp.command_native({'expand-path','~~/playback-diagnostic.json'})
local state={phase='idle',network=false,has_media=false,http_status=nil}
local history={}
local function remote(path)
    return type(path)=='string' and path:match('^%a[%w+.-]*://') and not path:match('^[Ff][Ii][Ll][Ee]://')
end
local function record(phase)
    state.phase=phase
    state.has_media=mp.get_property('path','')~=''
    state.playlist_count=mp.get_property_number('playlist-count',0)
    state.position=mp.get_property_number('playlist-pos',-1)
    state.network_thumbnails=false;state.playlist_prefetch=false
    history[#history+1]={time=os.date('!%Y-%m-%dT%H:%M:%SZ'),phase=phase,network=state.network,
        has_media=state.has_media,playlist_count=state.playlist_count,position=state.position,http_status=state.http_status}
    while #history>24 do table.remove(history,1) end
    mp.set_property_native('user-data/player_ui/playback',state)
    local json=utils.format_json({version=1,events=history})
    local f=io.open(diagnostic,'wb');if f then f:write(json);f:close() end
end
local function set(name,value)
    local ok,err=mp.set_property(name,value)
    if not ok then message.error('Playback policy option '..name..': '..tostring(err)) end
end
set('prefetch-playlist','no')
mp.add_hook('on_load',-1000,function()
    state.network=not not remote(mp.get_property('stream-open-filename',mp.get_property('path','')))
    state.http_status=nil
    set('prefetch-playlist','no')
    if state.network then
        for name,value in pairs({['sub-auto']='no',['audio-file-auto']='no',['cover-art-auto']='no',
            ['ytdl']='no',['demuxer-cache-wait']='no',['cache-pause-wait']='1',
            ['demuxer-max-bytes']='32MiB',['demuxer-max-back-bytes']='8MiB',
            ['demuxer-readahead-secs']='10',['cache-secs']='10',['network-timeout']='20'}) do
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
mp.register_event('file-loaded',function()record('loaded')end)
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
        mp.osd_message(text,8)
    elseif e.reason=='eof' then record('ended')
    elseif e.reason=='stop' then record('stopped') end
end)
record('idle')

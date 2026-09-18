-- Player UI-style controller, rendered with vector icons and system fonts.
local mp=require 'mp'
local utils=require 'mp.utils'
local options=require 'mp.options'
local core=dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_core.lua'}))
local metrics=dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_metrics.lua'}))
local o={hide_timeout=2.5,network_speed=true,volume_step=5,ui_scale=0.70,font='Microsoft YaHei',accent='B47799'}
options.read_options(o,'player_ui')
o.ui_scale=core.clamp(tonumber(o.ui_scale) or .70,.45,1.5)
o.hide_timeout=core.clamp(o.hide_timeout,1,20);o.volume_step=core.clamp(o.volume_step,1,20)
if not o.accent:match('^%x%x%x%x%x%x$') then o.accent='B47799' end
local ui=mp.create_osd_overlay('ass-events');ui.z=20
local state={visible=true,x=-1,y=-1,hover=nil,menu=nil,scroll=0,drag=nil,pressed=nil,
    thumb=nil,thumb_time=nil,rate=nil,fps=nil,cpu=nil,memory=nil}
local layout,buttons,menu_box,menu_items,menus
local render_timer,hide_timer,pulse,network_timer,thumb_timer
local render,request_render,show,sync_timers,open_menu
local samples=core.fps_sampler()
local WHITE,MUTED,PANEL,ACCENT='FFFFFF','BEBEBE','22201F',o.accent
local labels={previous='上一个文件',next='下一个文件',play='播放 / 暂停',volume='音量 / 静音',
    speed='播放速度',audio='音轨',sub='字幕',danmaku='弹幕',ai='超分 / 补帧预设',
    settings='设置',stats='统计信息',performance='性能统计',playlist='播放列表',fullscreen='全屏',more='更多',
    pin='窗口置顶',minimize='最小化',maximize='最大化 / 还原',close='关闭播放器'}
local presets={}
local function read_presets()
    local p=mp.command_native({'expand-path','~~/../animejanai/animejanai.conf'})
    local f=io.open(p,'rb');if f then presets=core.parse_presets(f:read(1024*1024));f:close() end
end
read_presets()
local function prop(name,default) return mp.get_property_native(name,default) end
local function num(name,default) return mp.get_property_number(name,default) end
local function bool(name,default) return mp.get_property_bool(name,default or false) end
local function cmd(...) return mp.commandv(...) end
local function kill(t) if t then t:kill() end end
local function hide_thumb()
    kill(thumb_timer);thumb_timer=nil
    if state.thumb_time then cmd('script-message-to','thumbfast','clear');state.thumb_time=nil end
end
local function format_num(value,unit,decimals)
    return core.finite(value) and string.format('%.'..(decimals or 1)..'f',value)..(unit or '') or '—'
end
local function actual_sample()
    state.fps=samples:sample(mp.get_time(),num('vo-presented-frame-count'),bool('pause') or bool('seeking'))
    if metrics.read then local m=metrics.read(mp.get_time());state.cpu=m.cpu;state.memory=m.memory end
end
local function volume(delta)
    mp.set_property_number('volume',core.clamp(num('volume',100)+delta,0,num('volume-max',100)))
    mp.osd_message('音量 '..string.format('%.0f',num('volume',100))..'%',1)
end
local function escape()
    local had_menu=menus and menus.back()
    state.drag=nil;state.pressed=nil;state.menu_drag=nil
    if not had_menu then mp.set_property_bool('fullscreen',false) end
    show()
end
local function open_file(kind)
    state.menu=nil;hide_thumb()
    cmd('script-message-to','mpvnet',kind=='audio' and 'load-audio' or 'load-sub')
end
local function current_slot() return num('user-data/animejanai/requested-slot',-1) end
local function ai_select(id)
    cmd('script-message','aji-slot',tostring(id));state.menu=nil;request_render()
end
local function safe_track(t)
    local title=core.title(t.title or '',t['external-filename'] or '')
    if not t.title or t.title=='' then title=t.type=='audio' and '音轨' or '字幕' end
    local bits={tostring(t.id)..'  '..title}
    if t.lang then bits[#bits+1]=t.lang end
    if t.codec then bits[#bits+1]=t.codec end
    if t['audio-channels'] then bits[#bits+1]=t['audio-channels']..' 声道' end
    return table.concat(bits,' · ')
end
local function info_data(kind)
    local rows={};local title=labels[kind] or '设置'
    local function row(text,fn,selected,disabled) rows[#rows+1]={text=text,fn=fn,selected=selected,disabled=disabled or fn==nil} end
    if kind=='performance' then
        local target=num('estimated-vf-fps');if target then target=target*num('speed',1) end
        row('实际 FPS  '..format_num(state.fps,'',2)..'  /  目标 '..format_num(target,'',2))
        row('播放器 CPU  '..format_num(state.cpu,'%')..'    内存 '..format_num(state.memory and state.memory/1048576,' MiB',0))
        row('源帧率  '..format_num(num('container-fps'),' FPS',3)..'    屏幕 '..format_num(num('display-fps'),' Hz',2))
        row('视频输出丢帧  '..format_num(num('frame-drop-count'),'',0)..'    解码丢帧 '..format_num(num('decoder-frame-drop-count'),'',0))
        row('音画偏差  '..format_num(num('avsync') and num('avsync')*1000,' ms',1))
        row('硬件解码  '..mp.get_property('hwdec-current','—'))
        row('视频输出  '..mp.get_property('current-vo','—'))
        local passes=prop('vo-passes',{}) or {};local total=0;local found=false
        for _,p in ipairs(passes.fresh or {}) do if core.finite(p.avg) then total=total+p.avg;found=true end end
        row('GPU 渲染耗时  '..(found and format_num(total/1e6,' ms',2) or '—'))
        row('缓冲  '..format_num(num('demuxer-cache-duration'),' 秒')..'    读取 '..core.rate(state.rate))
    elseif kind=='stats' then
        local v=prop('video-params',{}) or {};local a=prop('audio-params',{}) or {}
        row('视频  '..tostring(v.w or '—')..' × '..tostring(v.h or '—')..' · '..mp.get_property('video-codec','—'))
        row('像素格式  '..tostring(v.pixelformat or '—')..' · '..tostring(v.colormatrix or '—'))
        row('音频  '..mp.get_property('audio-codec-name','—')..' · '..tostring(a.samplerate or '—')..' Hz')
        row('时长  '..core.time(num('duration'))..'    章节 '..tostring(#(prop('chapter-list',{}) or {})))
        row('AnimeJaNai 状态（Ctrl+J）',function()state.visible=false;cmd('script-binding','animejanaistats/show_animejanai_stats')end)
        row('mpv 完整统计',function()state.visible=false;cmd('script-binding','stats/display-stats-toggle')end)
        if #(prop('chapter-list',{}) or {})>0 then row('章节…',function()open_menu('chapters')end) end
    elseif kind=='chapters' then
        title='章节'
        for i,c in ipairs(prop('chapter-list',{}) or {}) do local t=c.time
            row(core.time(c.time)..'  '..(c.title or ('章节 '..i)),function()cmd('seek',t,'absolute+exact')end,num('chapter',-1)==i-1)
        end
    end
    return title,rows
end
-- Anchored menus 1.1.1
menus=dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_menu.lua'}))({
    state=state,core=core,accent=ACCENT,prop=prop,num=num,bool=bool,command=cmd,
    set=mp.set_property,set_number=mp.set_property_number,set_bool=mp.set_property_bool,
    read_presets=read_presets,presets=function()return presets end,current_slot=current_slot,select_slot=ai_select,
    open_file=open_file,info=info_data,after=mp.add_timeout,
    open=function(kind,parent)open_menu(kind,parent)end,
    manager=function()cmd('run',mp.command_native({'expand-path','~~/../AnimeJaNaiManager.exe'}))end
})
open_menu=function(kind,parent)
    if kind=='more' then kind='settings' end
    hide_thumb();samples:reset();state.fps=nil;state.cpu=nil;state.memory=nil
    if metrics.reset then metrics.reset() end
    menus.open(kind,parent)
    if state.menu=='performance' then actual_sample() end
    show();sync_timers()
end
local function activate(id)
    if id=='play' then
        if bool('eof-reached') and bool('seekable') then cmd('seek',0,'absolute+exact') end
        cmd('cycle','pause')
    elseif id=='previous' or id=='next' then
        if num('playlist-count',0)>1 then cmd(id=='previous' and 'playlist-prev' or 'playlist-next','weak')
        elseif bool('seekable') then cmd('seek',id=='previous' and -10 or 10,'relative+exact') end
    elseif id=='volume' then cmd('cycle','mute')
    elseif id=='fullscreen' then cmd('cycle','fullscreen')
    elseif id=='pin' then cmd('cycle','ontop')
    elseif id=='minimize' then mp.set_property_bool('window-minimized',true)
    elseif id=='maximize' then cmd('cycle','window-maximized')
    elseif id=='close' then cmd('quit')
    else open_menu(id) end
end
local icons={
 play='m 9 4 l 27 16 9 28',pause='m 7 5 l 13 5 13 27 7 27 m 20 5 l 26 5 26 27 20 27',
 previous='m 5 6 l 8 6 8 26 5 26 m 26 5 l 10 16 26 27',next='m 24 6 l 27 6 27 26 24 26 m 6 5 l 22 16 6 27',
 volume='m 2 12 l 8 12 17 5 17 27 8 20 2 20 m 21 9 b 27 13 27 19 21 23 l 21 20 b 24 17 24 15 21 12 m 23 3 b 36 10 36 22 23 29 l 23 26 b 32 20 32 12 23 6',
 muted='m 2 12 l 8 12 17 5 17 27 8 20 2 20 m 22 11 l 25 14 28 11 30 13 27 16 30 19 28 21 25 18 22 21 20 19 23 16 20 13',
 audio='m 16 3 l 27 3 27 10 19 10 19 24 b 19 32 6 32 6 25 b 6 20 11 18 16 21',
 sub='m 3 4 l 29 4 b 31 4 32 6 32 8 l 32 24 b 32 28 30 28 28 28 l 4 28 b 0 28 0 26 0 24 l 0 8 b 0 4 1 4 3 4',
 danmaku='m 3 3 l 29 3 29 26 10 26 5 30 5 26 3 26 m 6 7 l 6 22 26 22 26 7 6 7 m 9 10 l 23 10 23 13 9 13 m 9 16 l 18 16 18 19 9 19',
 ai='m 16.00 3.50 l 19.12 0.31 22.12 1.22 22.94 5.61 24.84 7.16 29.30 7.11 30.78 9.88 28.26 13.56 28.50 16.00 31.69 19.12 30.78 22.12 26.39 22.94 24.84 24.84 24.89 29.30 22.12 30.78 18.44 28.26 16.00 28.50 12.88 31.69 9.88 30.78 9.06 26.39 7.16 24.84 2.70 24.89 1.22 22.12 3.74 18.44 3.50 16.00 0.31 12.88 1.22 9.88 5.61 9.06 7.16 7.16 7.11 2.70 9.88 1.22 13.56 3.74 m 16 10 b 12.69 10 10 12.69 10 16 b 10 19.31 12.69 22 16 22 b 19.31 22 22 19.31 22 16 b 22 12.69 19.31 10 16 10',
 stats='m 3 3 l 6 3 6 26 30 26 30 29 3 29 m 10 16 l 14 16 14 23 10 23 m 18 11 l 22 11 22 23 18 23 m 26 5 l 30 5 30 23 26 23',
 performance='m 2 15 l 8 15 12 4 19 25 23 15 30 15 30 18 25 18 19 32 12 13 10 18 2 18',
 playlist='m 3 6 l 27 6 27 9 3 9 m 3 13 l 27 13 27 16 3 16 m 3 20 l 18 20 18 23 3 23 m 23 20 l 32 26 23 32',
 fullscreen='m 2 2 l 12 2 12 5 5 5 5 12 2 12 m 20 2 l 30 2 30 12 27 12 27 5 20 5 m 2 20 l 5 20 5 27 12 27 12 30 2 30 m 27 20 l 30 20 30 30 20 30 20 27 27 27',
 restore='m 10 2 l 13 2 13 13 2 13 2 10 10 10 m 19 2 l 22 2 22 10 30 10 30 13 19 13 m 2 19 l 13 19 13 30 10 30 10 22 2 22 m 19 19 l 30 19 30 22 22 22 22 30 19 30',
 pin='m 12 2 l 23 10 19 14 20 22 13 18 4 30 2 29 10 15 3 12 11 10',
 minimize='m 7 15 l 26 15 26 17 7 17',maximize='m 6 5 l 27 5 27 27 6 27 m 8 7 l 8 25 25 25 25 7',
 close='m 7 5 l 27 25 25 27 5 7 m 25 5 l 27 7 7 27 5 25',
 more='m 2 14 l 7 14 7 19 2 19 m 14 14 l 19 14 19 19 14 19 m 26 14 l 31 14 31 19 26 19'
}
icons.settings=icons.ai
icons.plus='m 15 4 l 18 4 18 14 28 14 28 17 18 17 18 28 15 28 15 17 5 17 5 14 15 14'
icons.info='m 16 1 b 7 1 1 7 1 16 b 1 25 7 31 16 31 b 25 31 31 25 31 16 b 31 7 25 1 16 1 m 14 14 l 14 25 18 25 18 14 m 14 7 l 14 11 18 11 18 7'
local output={}
local clip_region
local function line(s)
    if clip_region then
        s=s:gsub('^(%{[^}]*)(%})',function(tags,ending)return tags..clip_region..ending end,1)
    end
    output[#output+1]=s
end
local function rect(x0,y0,x1,y1,color,alpha)
    if x1<=x0 or y1<=y0 then return end
    line(string.format('{\\rDefault\\an7\\pos(0,0)\\bord0\\shad0\\1c&H%s&\\1a&H%02X&\\p1}m %.2f %.2f l %.2f %.2f %.2f %.2f %.2f %.2f{\\p0}',color or WHITE,alpha or 0,x0,y0,x1,y0,x1,y1,x0,y1))
end
local function circle(x,y,r,color,alpha)
    local k=r*.552285
    line(string.format('{\\rDefault\\an7\\pos(0,0)\\bord0\\shad0\\1c&H%s&\\1a&H%02X&\\p1}m %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f{\\p0}',color,alpha or 0,x-r,y,x-r,y-k,x-k,y-r,x,y-r,x+k,y-r,x+r,y-k,x+r,y,x+r,y+k,x+k,y+r,x,y+r,x-k,y+r,x-r,y+k,x-r,y))
end
local function round(x0,y0,x1,y1,r,color,alpha)
    if x1<=x0 or y1<=y0 then return end
    r=math.min(r,(x1-x0)/2,(y1-y0)/2);local k=r*.552285
    local path=string.format('m %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f',
        x0+r,y0,x1-r,y0,x1-r+k,y0,x1,y0+r-k,x1,y0+r,x1,y1-r,x1,y1-r+k,x1-r+k,y1,x1-r,y1,x0+r,y1,x0+r-k,y1,x0,y1-r+k,x0,y1-r,x0,y0+r,x0,y0+r-k,x0+r-k,y0,x0+r,y0)
    line(string.format('{\\rDefault\\an7\\pos(0,0)\\bord0\\shad0\\1c&H%s&\\1a&H%02X&\\p1}%s{\\p0}',color,alpha or 0,path))
end
local function clip(x0,y0,x1,y1,fn)
    local old=clip_region
    clip_region=string.format('\\clip(%d,%d,%d,%d)',math.floor(x0),math.floor(y0),math.ceil(x1),math.ceil(y1))
    fn();clip_region=old
end
local function text(x,y,size,s,align,color,bold,max)
    if max then s=core.ellipsize(s,max,size) end
    line(string.format('{\\rDefault\\an%d\\pos(%.2f,%.2f)\\fn%s\\fs%d\\b%d\\bord0\\shad1\\1c&H%s&\\1a&H00&}%s',align or 7,x,y,o.font,size,bold and 1 or 0,color or WHITE,core.escape(s)))
end
local function icon(id,x,y,active,disabled,small)
    if state.hover==id then circle(x,y,24,WHITE,226) end
    local color=active and ACCENT or WHITE
    local size=small and 70 or 100
    line(string.format('{\\rDefault\\an7\\pos(%.2f,%.2f)\\bord0\\shad0\\fscx%d\\fscy%d\\1c&H%s&\\1a&H%02X&\\p1}%s{\\p0}',x-16*size/100,y-16*size/100,size,size,color,disabled and 160 or 0,icons[id] or icons.more))
end
local function thumb(t,x)
    if not core.local_media(mp.get_property('path',''),mp.get_property('stream-open-filename',''),bool('demuxer-via-network')) then hide_thumb();return end
    if not state.thumb or state.thumb.disabled or not state.thumb.available then return end
    if state.thumb_time and math.abs(state.thumb_time-t)<.2 then return end
    kill(thumb_timer)
    thumb_timer=mp.add_timeout(.06,function()
        thumb_timer=nil
        if not core.local_media(mp.get_property('path',''),mp.get_property('stream-open-filename',''),bool('demuxer-via-network')) then hide_thumb();return end
        state.thumb_time=t
        local width=state.thumb.width or 160;local height=state.thumb.height or 90
        local px=core.clamp(x*layout.scale-width/2,12,layout.w*layout.scale-width-12)
        local py=(layout.seek.y0-46)*layout.scale-height
        cmd('script-message-to','thumbfast','thumb',tostring(t),tostring(math.floor(px)),tostring(math.floor(py)))
    end)
end
local function seek_value(x)
    return core.clamp((x-layout.seek.x0)/(layout.seek.x1-layout.seek.x0),0,1)*num('duration',0)
end
local function draw_menu()
    menu_items=menus.draw(layout,{rect=rect,round=round,circle=circle,text=text,icon=icon,clip=clip},buttons)
end
local function hit(x,y)
    local found
    for i=#(buttons or {}),1,-1 do local b=buttons[i];if core.inside(b,x,y) then found=b;break end end
    return menus.hit_override(found,x,y)
end
local mouse_bound=false
local function mouse_button(event)
    if event and event.canceled then state.drag=nil;state.menu_drag=nil;state.pressed=nil;hide_thumb();request_render();return end
    local e=event and event.event or 'press'
    local px,py=mp.get_mouse_pos()
    if layout and core.finite(px) and core.finite(py) then
        state.x=px/layout.scale;state.y=py/layout.scale
    end
    if e=='down' or e=='press' then
        show();local b=hit(state.x,state.y);menus.hover(nil)
        if b then
            state.pressed=b.id;state.pressed_key=b.key
            if b.menu and menus.press(b,state.x,state.y) then state.drag='menu'
            elseif b.id=='seek' and num('duration',0)>0 and bool('seekable') then state.drag='seek';hide_thumb()
            elseif b.id=='volume-slider' then state.drag='volume-slider' end
        end
    end
    if state.drag=='volume-slider' and (e=='down' or e=='press') and layout.volume then
        mp.set_property_number('volume',core.clamp((state.x-layout.volume.x0)/(layout.volume.x1-layout.volume.x0),0,1)*100)
    end
    if e=='up' or e=='press' then
        if state.drag=='seek' then cmd('seek',seek_value(state.x),'absolute+exact')
        elseif state.drag=='menu' then menus.drag(state.x,state.y)
        elseif not state.drag then
            local b=hit(state.x,state.y)
            if b and b.id==state.pressed and b.key==state.pressed_key then
                if b.menu then menus.pick(b) else activate(b.id) end
            end
        end
        state.drag=nil;state.menu_drag=nil;state.pressed=nil;sync_timers()
    end
    request_render()
end
local function wheel(delta)
    if menus.wheel(delta,state.x,state.y) then request_render();return end
    if state.hover=='seek' and bool('seekable') then cmd('seek',delta*5,'relative+exact')
    else volume(delta*o.volume_step) end
    request_render()
end
local function bind_mouse(enabled)
    if mouse_bound==enabled then return end
    mouse_bound=enabled
    if enabled then
        mp.add_forced_key_binding('MBTN_LEFT','player_ui-click',mouse_button,{complex=true})
        mp.add_forced_key_binding('MBTN_LEFT_DBL','player_ui-double',function()end)
        mp.add_forced_key_binding('WHEEL_UP','player_ui-wheel-up',function()wheel(1)end,{repeatable=true})
        mp.add_forced_key_binding('WHEEL_DOWN','player_ui-wheel-down',function()wheel(-1)end,{repeatable=true})
    else
        for _,key in ipairs({'player_ui-click','player_ui-double','player_ui-wheel-up','player_ui-wheel-down'}) do mp.remove_key_binding(key) end
    end
end
render=function()
    render_timer=nil
    if bool('window-minimized') then ui:remove();bind_mouse(false);return end
    local pw,ph=mp.get_osd_size();if pw<=0 or ph<=0 then return end
    layout=core.layout(pw,ph,num('playlist-count',0),num('display-hidpi-scale',1),o.ui_scale);buttons={};output={};menu_box=nil
    local net=bool('demuxer-via-network') and o.network_speed and not bool('idle-active',true)
    if state.visible then
        for i=0,47 do local y=layout.h-340+i*340/48
            rect(0,y,layout.w,y+340/48+.2,'000000',math.floor(255-170*(i/47)^1.4))
        end
        local title=core.title(mp.get_property('media-title',''),mp.get_property('path',''))
        if bool('idle-active',true) then title='' end
        text(36,layout.title_y,40,title,7,WHITE,true,layout.w-72)
        local detail={};local count=num('playlist-count',0)
        if count>1 then detail[#detail+1]=string.format('播放列表  %d / %d',num('playlist-pos',0)+1,count) end
        local v=prop('video-params',{}) or {}
        if v.w and v.h then detail[#detail+1]=v.w..' × '..v.h end
        local fps=num('container-fps');if fps then detail[#detail+1]=string.format('%.3g fps',fps) end
        if bool('paused-for-cache') then detail[#detail+1]='正在缓冲…' end
        text(36,layout.detail_y,23,table.concat(detail,'  ·  '),7,MUTED,false,layout.w-72)
        local seek=layout.seek;local dur=num('duration');local pos=num('time-pos',0)
        text(36,seek.y,21,core.time(state.drag=='seek' and seek_value(state.x) or pos),4)
        text(layout.w-36,seek.y,21,core.time(dur),6)
        rect(seek.x0,seek.y-3,seek.x1,seek.y+3,WHITE,178)
        if dur and dur>0 then
            local cache=prop('demuxer-cache-state',{}) or {}
            for _,range in ipairs(cache['seekable-ranges'] or {}) do
                if core.finite(range.start) and core.finite(range['end']) then
                    rect(seek.x0+core.clamp(range.start/dur,0,1)*(seek.x1-seek.x0),seek.y-3,
                        seek.x0+core.clamp(range['end']/dur,0,1)*(seek.x1-seek.x0),seek.y+3,WHITE,100)
                end
            end
            local p=state.drag=='seek' and seek_value(state.x) or pos
            local x=seek.x0+core.clamp(p/dur,0,1)*(seek.x1-seek.x0)
            rect(seek.x0,seek.y-3,x,seek.y+3,ACCENT);circle(x,seek.y,14,'4C4C4C',55);circle(x,seek.y,7,ACCENT)
            buttons[#buttons+1]={id='seek',x0=seek.x0,x1=seek.x1,y0=seek.y0,y1=seek.y1}
            if core.inside(seek,state.x,state.y) and not state.menu then
                local target=seek_value(state.x)
                rect(state.x-44,seek.y0-40,state.x+44,seek.y0-4,PANEL,20);text(state.x,seek.y0-22,19,core.time(target),5)
                if not state.drag then thumb(target,state.x) end
            else hide_thumb() end
        end
        for _,b in ipairs(layout.controls) do
            local id=b.id;local disabled=false
            if id=='previous' then disabled=count>1 and num('playlist-pos',0)==0 or count<=1 and not bool('seekable') end
            if id=='next' then disabled=count>1 and num('playlist-pos',0)>=count-1 or count<=1 and not bool('seekable') end
            if id=='speed' then
                if state.hover==id then rect(b.x0,b.y0,b.x1,b.y1,WHITE,230) end
                text(b.x,b.y,25,(num('speed',1)%1==0 and string.format('%.1fx',num('speed',1)) or string.format('%gx',num('speed',1))),5)
            else
                local drawid=id
                if id=='play' then drawid=(bool('pause') or bool('idle-active',true)) and 'play' or 'pause' end
                if id=='volume' and bool('mute') then drawid='muted' end
                if id=='fullscreen' and bool('fullscreen') then drawid='restore' end
                local d=prop('user-data/player_ui/danmaku',{}) or {}
                icon(drawid,b.x,b.y,state.menu==id or id=='settings' and state.parent=='settings' or id=='danmaku' and d.loaded and d.enabled,disabled)
                if id=='sub' then text(b.x,b.y+1,17,'CC',5,'222222',true) end
            end
            if not disabled then buttons[#buttons+1]=b end
        end
        if layout.volume then
            local b=layout.volume;local v=core.clamp(num('volume',0)/100,0,1)
            rect(b.x0,b.y-3,b.x1,b.y+3,WHITE,145);rect(b.x0,b.y-3,b.x0+v*(b.x1-b.x0),b.y+3,ACCENT)
            circle(b.x0+v*(b.x1-b.x0),b.y,11,'4C4C4C',40);circle(b.x0+v*(b.x1-b.x0),b.y,6,ACCENT)
            buttons[#buttons+1]={id='volume-slider',x0=b.x0,x1=b.x1,y0=b.y0,y1=b.y1}
        end
        for i,id in ipairs({'close','maximize','minimize','pin'}) do
            local x=layout.w-30-(i-1)*60;local b={id=id,x0=x-25,x1=x+25,y0=0,y1=46}
            buttons[#buttons+1]=b;icon(id,x,23,id=='pin' and bool('ontop'),false,true)
        end
        if state.menu then draw_menu() end
        if state.hover and labels[state.hover] and not state.menu then
            local tip=labels[state.hover]
            if count<=1 and (state.hover=='previous' or state.hover=='next') then tip=state.hover=='previous' and '后退 10 秒' or '前进 10 秒' end
            if state.hover=='volume' then tip='音量 '..string.format('%.0f',num('volume',100))..'%' end
            local top=state.y<70;local y=top and 62 or layout.h-106
            text(core.clamp(state.x,120,layout.w-120),y,18,tip,5)
        end
    else hide_thumb() end
    if net and state.menu~='playlist' then text(layout.w-24,61,20,core.rate(state.rate),9,MUTED) end
    local b=hit(state.x,state.y);state.hover=b and b.id or nil
    bind_mouse(state.visible and (b~=nil or state.drag~=nil or state.menu~=nil))
    ui.res_x=math.floor(layout.w+.5);ui.res_y=math.floor(layout.h+.5);ui.data=table.concat(output,'\n')
    if ui.data=='' then
        ui:remove();state.overlay_ok=false;state.overlay_error=nil
    else
        local result,err=ui:update()
        state.overlay_ok=err==nil;state.overlay_error=err
        if err and err~=state.last_overlay_error then require('mp.msg').error('Player UI overlay: '..tostring(err)) end
        state.last_overlay_error=err
    end
    local rows
    if state.menu and menu_items then rows={}
        for _,r in ipairs(menu_items) do rows[#rows+1]={text=r.text,selected=r.selected,disabled=r.disabled,key=r.key,target=r.target,hint=r.hint} end
    end
    local boxes={}
    for _,b in ipairs(menus.boxes) do boxes[#boxes+1]={kind=b.kind,x0=b.x0,x1=b.x1,y0=b.y0,y1=b.y1,total=b.total,view=b.view,offset=b.offset} end
    mp.set_property_native('user-data/player_ui/ui',{visible=state.visible,menu=state.menu or '',width=pw,height=ph,
        controls=buttons,scale=layout.scale,hover=state.hover,mouse_x=state.x,mouse_y=state.y,overlay_ok=state.overlay_ok,overlay_error=state.overlay_error,menu_boxes=boxes,subtitle_slot=state.sub_slot or 1,version='1.1.2',network_rate=state.rate,rows=rows,
        performance=state.menu=='performance' and {fps=state.fps,cpu=state.cpu,memory=state.memory} or nil})
end
request_render=function()if not render_timer then render_timer=mp.add_timeout(.035,render) end end
local menu_escape_bound=false
sync_timers=function()
    local menu_open=state.menu~=nil
    if menu_open~=menu_escape_bound then
        menu_escape_bound=menu_open
        if menu_open then mp.add_forced_key_binding('ESC','player_ui-menu-escape',escape)
        else mp.remove_key_binding('player_ui-menu-escape') end
    end
    local need=not bool('window-minimized') and (state.visible and not bool('pause') and not bool('idle-active',true) or state.menu=='performance')
    if need and not pulse then pulse=mp.add_periodic_timer(.25,function()if state.menu=='performance' then actual_sample() end;request_render()end)
    elseif not need and pulse then pulse:kill();pulse=nil end
    local net=not bool('window-minimized') and o.network_speed and bool('demuxer-via-network') and not bool('idle-active',true)
    if net and not network_timer then network_timer=mp.add_periodic_timer(1,function()
        state.rate=bool('demuxer-cache-idle') and 0 or num('cache-speed');request_render()
    end)
    elseif not net and network_timer then network_timer:kill();network_timer=nil;state.rate=nil end
end
local function hide()
    hide_timer=nil
    if state.menu or state.drag or state.hover or bool('pause') or bool('idle-active',true) then return end
    state.visible=false;state.hover=nil;bind_mouse(false);hide_thumb();sync_timers();request_render()
end
show=function()
    state.visible=true;kill(hide_timer);hide_timer=mp.add_timeout(o.hide_timeout,hide)
    sync_timers();request_render()
end
local function mouse_move()
    local x,y=mp.get_mouse_pos()
    if not layout then local w,h=mp.get_osd_size();layout=core.layout(w,h,num('playlist-count',0),num('display-hidpi-scale',1),o.ui_scale) end
    state.x=x/layout.scale;state.y=y/layout.scale
    if state.drag=='volume-slider' and layout.volume then
        mp.set_property_number('volume',core.clamp((state.x-layout.volume.x0)/(layout.volume.x1-layout.volume.x0),0,1)*100)
    elseif state.drag=='menu' then menus.drag(state.x,state.y) end
    show();local b=hit(state.x,state.y);state.hover=b and b.id or nil;menus.hover(b)
    bind_mouse(b~=nil or state.drag~=nil or state.menu~=nil)
end
mp.add_forced_key_binding('mouse_move','player_ui-move',mouse_move)
mp.add_forced_key_binding('mouse_leave','player_ui-leave',function()
    menus.hover(nil);state.x=-1;state.y=-1;state.hover=nil;state.drag=nil;state.pressed=nil;hide_thumb();hide()
end)
mp.add_key_binding('UP','player_ui-volume-up',function()volume(o.volume_step)end,{repeatable=true})
mp.add_key_binding('DOWN','player_ui-volume-down',function()volume(-o.volume_step)end,{repeatable=true})
mp.add_key_binding('ESC','player_ui-escape',escape)
mp.register_script_message('player_ui-menu',function(kind)
    if menus.allowed[kind] then open_menu(kind) end
end)
mp.register_script_message('player_ui-show',show)
mp.register_script_message('player_ui-hide',function()menus.close();state.hover=nil;hide()end)
mp.register_script_message('thumbfast-info',function(json)local info=utils.parse_json(json);if type(info)=='table' then state.thumb=info end end)
mp.add_key_binding(nil,'visibility',function()if state.visible then state.menu=nil;hide() else show() end end)
for _,p in ipairs({'pause','idle-active','demuxer-via-network','window-minimized','fullscreen','window-maximized','ontop',
    'volume','mute','speed','sid','secondary-sid','sub-visibility','sub-delay','sub-scale','sub-pos','audio-delay','display-hidpi-scale','keepaspect','panscan','video-unscaled','track-list','playlist','playlist-pos','media-title','duration','video-params','osd-dimensions',
    'user-data/player_ui/danmaku','user-data/animejanai/requested-slot'}) do
    mp.observe_property(p,'native',function()
        if p=='pause' then samples:reset();show() else sync_timers();if state.visible then request_render() end end
    end)
end
mp.register_event('start-file',function()
    menus.close();state.drag=nil;state.pressed=nil;state.rate=nil;state.fps=nil;samples:reset();hide_thumb();show()
end)
mp.register_event('file-loaded',function()samples:reset();show()end)
mp.register_event('seek',function()samples:reset()end)
mp.register_event('end-file',function()state.rate=nil;hide_thumb();sync_timers()end)
mp.register_event('shutdown',function()
    menus.shutdown();kill(render_timer);kill(hide_timer);kill(pulse);kill(network_timer);kill(thumb_timer);ui:remove();bind_mouse(false)
end)
show()

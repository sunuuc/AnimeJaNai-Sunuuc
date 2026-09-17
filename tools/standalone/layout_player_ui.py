"""Apply the 1.1.1 controller layout migration; published sources retain the result."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]

def replace_section(s,start,end,replacement):
    a=s.index(start);b=s.index(end,a)
    return s[:a]+replacement+s[b:]

p=ROOT/'portable_config/script-modules/player_ui_core.lua'
s=p.read_text(encoding='utf-8-sig')
if '-- Anchored Player UI layout 1.1.1' not in s:
    s=replace_section(s,'function M.layout(', 'function M.inside(',r'''-- Anchored Player UI layout 1.1.1: physical DPI, not a percentage of the video height.
function M.layout(pw,ph,count,dpi)
    pw,ph=math.max(1,pw),math.max(1,ph)
    local scale=math.min(M.clamp(tonumber(dpi) or 1,.5,3),pw/920,ph/620)
    local w,h=pw/scale,ph/scale;local compact=w<1100
    local step=compact and 58 or 84;local y=h-66;local controls={}
    local function button(id,x,bw)
        bw=bw or 48
        controls[#controls+1]={id=id,x=x,y=y,x0=x-bw/2,x1=x+bw/2,y0=y-25,y1=y+25}
    end
    button('previous',64);button('play',64+step);button('next',64+2*step);button('volume',64+3*step)
    local right={'fullscreen'}
    if count>1 then right[#right+1]='playlist' end
    for _,id in ipairs({'settings','danmaku','sub','audio'}) do right[#right+1]=id end
    local x=w-64
    for _,id in ipairs(right) do button(id,x);x=x-step end
    button('speed',x,72)
    local vx=64+3*step+38;local ex=math.min(vx+146,x-62)
    local volume=ex-vx>=60 and {x0=vx,x1=ex,y0=y-18,y1=y+18,y=y} or nil
    return {w=w,h=h,scale=scale,controls=controls,volume=volume,
        seek={x0=122,x1=w-122,y0=h-158,y1=h-122,y=h-140},
        title_y=h-254,detail_y=h-204,margin=36,compact=compact,small=false}
end
function M.wrap(value,width,size,maxlines)
    local chars=M.chars(value);local out,line,used={},'',0
    maxlines=maxlines or 2
    for i,c in ipairs(chars) do
        local cw=(#c>1 and 1 or (c:match('[ilI.,! :;|]') and .3 or .6))*size
        if used+cw>width and line~='' then
            if #out==maxlines-1 then out[#out+1]=M.ellipsize(line..table.concat(chars,'',i),width,size);return out end
            out[#out+1]=line;line='';used=0
        end
        line=line..c;used=used+cw
    end
    if line~='' or #out==0 then out[#out+1]=line end
    return out
end
''')
    p.write_text(s,encoding='utf-8')
p=ROOT/'portable_config/scripts/player_ui.lua'
s=p.read_text(encoding='utf-8-sig')
if '-- Anchored menus 1.1.1' not in s:
    s=s.replace("local layout,buttons,menu_box,menu_items","local layout,buttons,menu_box,menu_items,menus")
    s=s.replace("stats='统计信息',performance='性能统计',playlist='播放列表'", "settings='设置',stats='统计信息',performance='性能统计',playlist='播放列表'")
    s=replace_section(s,'local function escape()', 'local function open_file(',r'''local function escape()
    local had_menu=menus and menus.back()
    state.drag=nil;state.pressed=nil;state.menu_drag=nil
    if not had_menu then mp.set_property_bool('fullscreen',false) end
    show()
end
''')
    start=s.index('local function menu_data(kind)')
    a=s.index("    elseif kind=='performance' then",start)
    b=s.index("    elseif kind=='more' then",a)
    info="local function info_data(kind)\n    local rows={};local title=labels[kind] or '设置'\n    local function row(text,fn,selected,disabled) rows[#rows+1]={text=text,fn=fn,selected=selected,disabled=disabled or fn==nil} end\n"
    info+=s[a:b].replace("    elseif kind=='performance' then", "    if kind=='performance' then",1)+"    end\n    return title,rows\nend\n"
    stop=s.index('local function activate(id)',b)
    factory=r'''-- Anchored menus 1.1.1
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
'''
    s=s[:start]+info+factory+s[stop:]
    s=s.replace('local output={}\n',"icons.settings=icons.ai\nicons.plus='m 15 4 l 18 4 18 14 28 14 28 17 18 17 18 28 15 28 15 17 5 17 5 14 15 14'\nicons.info='m 16 1 b 7 1 1 7 1 16 b 1 25 7 31 16 31 b 25 31 31 25 31 16 b 31 7 25 1 16 1 m 14 14 l 14 25 18 25 18 14 m 14 7 l 14 11 18 11 18 7'\nlocal output={}\nlocal clip_region\n")
    s=s.replace('local function line(s) output[#output+1]=s end',r'''local function line(s)
    if clip_region then s=s:gsub('{\\rDefault',function()return '{\\rDefault'..clip_region end) end
    output[#output+1]=s
end''')
    idx=s.index('local function text(')
    s=s[:idx]+r'''local function round(x0,y0,x1,y1,r,color,alpha)
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
'''+s[idx:]
    s=replace_section(s,'local function draw_menu()', 'local mouse_bound=false',r'''local function draw_menu()
    menu_items=menus.draw(layout,{rect=rect,round=round,circle=circle,text=text,icon=icon,clip=clip},buttons)
end
local function hit(x,y)
    local found
    for i=#(buttons or {}),1,-1 do local b=buttons[i];if core.inside(b,x,y) then found=b;break end end
    return menus.hit_override(found,x,y)
end
''')
    s=replace_section(s,'local function mouse_button(event)', 'local function bind_mouse(enabled)',r'''local function mouse_button(event)
    if event and event.canceled then state.drag=nil;state.menu_drag=nil;state.pressed=nil;hide_thumb();request_render();return end
    local e=event and event.event or 'press'
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
''')
    s=s.replace("core.layout(pw,ph,num('playlist-count',0))","core.layout(pw,ph,num('playlist-count',0),num('display-hidpi-scale',1))")
    s=s.replace("core.layout(w,h,num('playlist-count',0))","core.layout(w,h,num('playlist-count',0),num('display-hidpi-scale',1))")
    s=s.replace("state.menu==id or id=='ai' and current_slot()>0", "state.menu==id or id=='settings' and state.parent=='settings'")
    s=s.replace("if net then text(layout.w-24,61,20,core.rate(state.rate),9,MUTED) end", "if net and state.menu~='playlist' then text(layout.w-24,61,20,core.rate(state.rate),9,MUTED) end")
    s=s.replace("version='1.1.0'","version='1.1.1'")
    head=s.index("render=function()")
    userdata=s.index("    mp.set_property_native('user-data/player_ui/ui',",head)
    begin=s.find("    local rows",head,userdata)
    if begin<0:begin=userdata
    rows="    local rows\n    if state.menu and menu_items then rows={}\n        for _,r in ipairs(menu_items) do rows[#rows+1]={text=r.text,selected=r.selected,disabled=r.disabled,key=r.key,target=r.target,hint=r.hint} end\n    end\n"
    boxes="    local boxes={}\n    for _,b in ipairs(menus.boxes) do boxes[#boxes+1]={kind=b.kind,x0=b.x0,x1=b.x1,y0=b.y0,y1=b.y1,total=b.total,view=b.view,offset=b.offset} end\n"
    s=s[:begin]+rows+boxes+s[userdata:]
    s=s.replace("controls=buttons,scale=layout.scale,", "controls=buttons,scale=layout.scale,menu_boxes=boxes,subtitle_slot=state.sub_slot or 1,")
    if 'network_rate=state.rate,rows=rows' not in s:s=s.replace('network_rate=state.rate,','network_rate=state.rate,rows=rows,')
    s=replace_section(s,'local function mouse_move()', "mp.add_forced_key_binding('mouse_move'",r'''local function mouse_move()
    local x,y=mp.get_mouse_pos()
    if not layout then local w,h=mp.get_osd_size();layout=core.layout(w,h,num('playlist-count',0),num('display-hidpi-scale',1)) end
    state.x=x/layout.scale;state.y=y/layout.scale
    if state.drag=='volume-slider' and layout.volume then
        mp.set_property_number('volume',core.clamp((state.x-layout.volume.x0)/(layout.volume.x1-layout.volume.x0),0,1)*100)
    elseif state.drag=='menu' then menus.drag(state.x,state.y) end
    show();local b=hit(state.x,state.y);state.hover=b and b.id or nil;menus.hover(b)
    bind_mouse(b~=nil or state.drag~=nil or state.menu~=nil)
end
''')
    if "'player_ui-menu-escape'" not in s:
        s=s.replace('sync_timers=function()','sync_timers=function()\n    if state.menu then mp.add_forced_key_binding(\'ESC\',\'player_ui-menu-escape\',escape) else mp.remove_key_binding(\'player_ui-menu-escape\') end')
    s=re.sub(r"    if \(\{audio=true.*?\}\)\[kind\] then open_menu\(kind\) end", "    if menus.allowed[kind] then open_menu(kind) end",s)
    s=s.replace("    if labels[kind] or kind=='chapters' then open_menu(kind) end", "    if menus.allowed[kind] then open_menu(kind) end")
    s=s.replace("'volume','mute','speed','track-list'", "'volume','mute','speed','sid','secondary-sid','sub-visibility','sub-delay','sub-scale','sub-pos','audio-delay','display-hidpi-scale','keepaspect','panscan','video-unscaled','track-list'")
    s=s.replace("    state.menu=nil;state.drag=nil;state.pressed=nil;state.rate=nil;", "    menus.close();state.drag=nil;state.pressed=nil;state.rate=nil;")
    s=s.replace("    kill(render_timer);kill(hide_timer);kill(pulse);kill(network_timer);kill(thumb_timer)", "    menus.shutdown();kill(render_timer);kill(hide_timer);kill(pulse);kill(network_timer);kill(thumb_timer)")
    p.write_text(s,encoding='utf-8')
assert "version='1.1.1'" in s and 'menu_items=menus.draw' in s
print('Player UI anchored layout ready')

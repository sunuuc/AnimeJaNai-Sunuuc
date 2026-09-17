-- Local XML danmaku on its own overlay: never replaces the selected subtitle/audio track.
local mp=require 'mp'
local utils=require 'mp.utils'
local core=dofile(mp.command_native({'expand-path','~~/script-modules/player_ui_core.lua'}))
local options=require 'mp.options'
local o={enabled=true,opacity=85,area=50,font_size=26}
options.read_options(o,'player_ui_danmaku')
o.opacity=core.clamp(tonumber(o.opacity) or 85,10,100)
o.area=core.clamp(tonumber(o.area) or 50,25,70)
o.font_size=core.clamp(tonumber(o.font_size) or 26,16,40)
local overlay=mp.create_osd_overlay('ass-events');overlay.z=5
local events,active,lanes,index,last,loaded={}, {}, {},1,nil,''
local timer,wake,picker,generation=nil,nil,nil,0
local function publish()
    mp.set_property_native('user-data/player_ui/danmaku',{loaded=loaded~='',file=loaded,count=#events,enabled=o.enabled,opacity=o.opacity,area=o.area})
end
local function kill()
    if timer then timer:kill();timer=nil end
    if wake then wake:kill();wake=nil end
end
local function clear() active={};lanes={};last=nil;overlay:remove() end
local function safe_path(path)
    return type(path)=='string' and path~='' and not path:find('%z') and not path:match('^%a[%w+.-]*://') and path:lower():match('%.xml$')
end
local update,schedule
local function load(path)
    if not safe_path(path) then mp.osd_message('请选择本地 XML 弹幕文件',3);return false end
    local file=io.open(path,'rb');if not file then mp.osd_message('无法打开弹幕文件',3);return false end
    local raw=file:read(16*1024*1024+1);file:close()
    local parsed,why=core.parse_danmaku(raw)
    if not parsed then mp.osd_message(why,4);return false end
    kill();clear();events=parsed;loaded=path;o.enabled=true;index=1
    publish();schedule();mp.osd_message('已加载 '..#events..' 条弹幕',3);return true
end
local function color(rgb)
    local r=math.floor(rgb/65536)%256;local g=math.floor(rgb/256)%256;local b=rgb%256
    return string.format('%02X%02X%02X',b,g,r)
end
update=function()
    if #events==0 or not o.enabled then overlay:remove();return end
    local t=mp.get_property_number('time-pos')
    if not t then return end
    local pw,ph=mp.get_osd_size();if pw<=0 or ph<=0 then return end
    local h=720;local w=h*pw/ph;local size=core.clamp(o.font_size,16,40)
    local rows=math.max(1,math.floor((h*core.clamp(o.area,25,70)/100-64)/(size+12)))
    if not last or t<last or t-last>1 then
        active={};lanes={};index=core.lower_bound(events,math.max(0,t-8))
    end
    local kept={};for _,a in ipairs(active) do if t<a.t+8 then kept[#kept+1]=a end end;active=kept
    local processed=0
    while events[index] and events[index].t<=t and processed<400 do
        local e=events[index];index=index+1;processed=processed+1
        local width=math.min(w*1.5,#core.chars(e.text)*size) -- conservative width avoids collisions
        local duration=8;local velocity=(w+width)/duration
        if e.t+duration>t and #active<rows*3 then
            local fixed=math.max(1,math.floor(rows/4))
            local first,finish=1,rows
            if rows>2 then
                if e.mode==5 then finish=fixed
                elseif e.mode==4 then first=rows-fixed+1
                else first=fixed+1;finish=rows-fixed end
            end
            local chosen
            for row=first,finish do
                local key=row;local prev=lanes[key]
                local free=not prev or e.t>=prev.finish
                if not free and prev.mode==e.mode and (e.mode==1 or e.mode==6) then
                    local elapsed=e.t-prev.t
                    free=elapsed>0 and prev.velocity*elapsed>prev.width+30
                        and (velocity<=prev.velocity or (w-prev.velocity*elapsed+prev.width+30)/prev.velocity<= (w+30)/velocity)
                end
                if free then chosen=row;lanes[key]={t=e.t,finish=e.t+duration,width=width,velocity=velocity,mode=e.mode};break end
            end
            if chosen then active[#active+1]={t=e.t,mode=e.mode,text=e.text,color=e.color,row=chosen,width=width,v=velocity} end
        end
    end
    last=t;local lines={}
    for _,a in ipairs(active) do
        local x=w-a.v*(t-a.t);local align=7;local y=64+(a.row-1)*(size+12)
        if a.mode==6 then x=-a.width+a.v*(t-a.t)
        elseif a.mode==5 then x=w/2;align=8
        elseif a.mode==4 then x=w/2;align=8 end
        lines[#lines+1]=string.format('{\\an%d\\pos(%.1f,%.1f)\\fnMicrosoft YaHei\\fs%d\\bord1.2\\shad0\\1c&H%s&\\1a&H%02X&}%s',align,x,y,size,color(a.color),math.floor(255*(1-core.clamp(o.opacity,10,100)/100)),core.escape(a.text))
    end
    overlay.res_x=w;overlay.res_y=h;overlay.data=table.concat(lines,'\n')
    if overlay.data~='' then overlay:update() else overlay:remove() end
    -- Stop animation entirely during empty stretches. Wake at the next real comment.
    if #active==0 and timer then timer:kill();timer=nil;schedule() end
end
schedule=function()
    kill()
    if not o.enabled or #events==0 or mp.get_property_bool('idle-active',true) then return end
    if mp.get_property_bool('pause',false) or mp.get_property_bool('core-idle',false) then update();return end
    local t=mp.get_property_number('time-pos',0)
    if not last then index=core.lower_bound(events,math.max(0,t-8)) end
    if #active==0 and events[index] and events[index].t>t+.1 then
        wake=mp.add_timeout((events[index].t-t)/math.max(.05,mp.get_property_number('speed',1)),function()wake=nil;schedule()end)
    elseif #active>0 or events[index] then timer=mp.add_periodic_timer(1/30,update);update() end
end
local function choose()
    if picker then return end
    local g=generation
    local ps=[[Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Filter='XML danmaku (*.xml)|*.xml'; $d.Title='选择弹幕文件'; if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.UTF8Encoding]::new();[Console]::Write($d.FileName)}; $d.Dispose()]]
    picker=mp.command_native_async({name='subprocess',args={'powershell.exe','-NoProfile','-STA','-Command',ps},playback_only=false,capture_stdout=true,capture_stderr=true},function(ok,result)
        picker=nil
        if g~=generation then return end
        if ok and result and result.status==0 and result.stdout~='' then load(result.stdout:gsub('[\r\n]+$',''))
        elseif not ok or not result or result.status~=0 then mp.osd_message('文件选择器不可用；可通过 player_ui-danmaku-load 传入本地 XML 路径',4) end
    end)
end
mp.register_script_message('player_ui-danmaku-load',load)
mp.register_script_message('player_ui-danmaku-choose',choose)
mp.register_script_message('player_ui-danmaku-toggle',function()o.enabled=not o.enabled;clear();publish();schedule()end)
mp.register_script_message('player_ui-danmaku-clear',function()kill();clear();events={};loaded='';publish()end)
mp.register_script_message('player_ui-danmaku-opacity',function(value)o.opacity=core.clamp(tonumber(value) or 85,10,100);publish();update()end)
mp.register_script_message('player_ui-danmaku-area',function(value)o.area=core.clamp(tonumber(value) or 50,25,70);clear();publish();schedule()end)
mp.register_event('start-file',function()
    generation=generation+1;kill();clear();events={};loaded='';index=1
    if picker then mp.abort_async_command(picker);picker=nil end
    publish()
end)
mp.register_event('file-loaded',function()
    local path=mp.get_property('path','')
    if not path:match('^%a[%w+.-]*://') then
        local xml=path:gsub('%.[^./\\]+$','')..'.xml'
        local stat=utils.file_info(xml)
        if stat and stat.is_file then load(xml) end
    end
end)
mp.register_event('seek',function()clear();schedule()end)
mp.register_event('end-file',function()kill();clear()end)
mp.register_event('shutdown',function()kill();overlay:remove();if picker then mp.abort_async_command(picker) end end)
for _,prop in ipairs({'pause','core-idle','speed','osd-dimensions'}) do mp.observe_property(prop,'native',schedule) end
publish()

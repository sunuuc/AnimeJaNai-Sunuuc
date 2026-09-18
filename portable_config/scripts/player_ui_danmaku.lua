-- Local XML danmaku on its own overlay: never replaces the selected subtitle/audio track.
local mp=require 'mp'
local utils=require 'mp.utils'
local core=(function()
-- inlined module: player_ui_core.lua
-- Pure functions shared by the controller and its regression tests. No mpv side effects.
local M = {}
function M.clamp(x, a, b) return math.max(a, math.min(b, x)) end
function M.finite(x) return type(x)=='number' and x==x and x~=math.huge and x~=-math.huge end
function M.clean(s)
    return tostring(s or ''):gsub('[%z\1-\8\11\12\14-\31\127]', '')
end
function M.escape(s)
    return M.clean(s):gsub('\\', '\\\239\187\191'):gsub('{','\\{'):gsub('}', '\\}'):gsub('\r?\n','\\N')
end
-- UTF-8 codepoints without depending on Lua 5.3's utf8 module (mpv uses LuaJIT).
function M.chars(s)
    local t={}; for c in M.clean(s):gmatch('[%z\1-\127\194-\244][\128-\191]*') do t[#t+1]=c end; return t
end
function M.ellipsize(s, max, size)
    local out,used={},0
    local chars=M.chars(s)
    for i,c in ipairs(chars) do
        local width=(#c>1 and 1 or (c:match('[ilI.,! :;|]') and .3 or .6))*size
        if used+width>max-size then return table.concat(out)..'…' end
        out[#out+1]=c;used=used+width
    end
    return table.concat(out)
end
function M.time(v)
    if not M.finite(v) then return '--:--' end
    v=math.max(0,math.floor(v));local h=math.floor(v/3600)
    return h>0 and string.format('%d:%02d:%02d',h,math.floor(v/60)%60,v%60)
        or string.format('%02d:%02d',math.floor(v/60),v%60)
end
function M.rate(v)
    if not M.finite(v) or v<0 then return '-- KB/s' end
    if v>=1000000 then return string.format('%.2f MB/s',v/1000000) end
    return string.format('%.1f KB/s',v/1000)
end
function M.title(title,path)
    title=M.clean(title):gsub('[\r\n]+',' ')
    if title=='' then
        title=M.clean(path)
        if not title:match('^%a[%w+.-]*://') then title=title:gsub('^.*[/\\]','') end
    end
    if title:match('^%a[%w+.-]*://') then
        local tail=title:match('^%a[%w+.-]*://[^/]+/(.*)$') or ''
        title=tail:gsub('[?#].*$', ''):match('([^/]+)/*$') or ''
        title=title:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end)
    end
    if title=='' then title='视频播放' end
    return title
end
-- Anchored Player UI layout 1.1.1: physical DPI, not a percentage of the video height.
function M.layout(pw,ph,count,dpi,ui_scale)
    pw,ph=math.max(1,pw),math.max(1,ph)
    local base=M.clamp(tonumber(ui_scale) or .70,.45,1.5)*M.clamp(tonumber(dpi) or 1,.5,1.25)
    local scale=math.min(base,pw/920,ph/620)
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
function M.inside(b,x,y) return b and x>=b.x0 and x<=b.x1 and y>=b.y0 and y<=b.y1 end
function M.parse_presets(text)
    local out,section={},''
    for line in tostring(text):gmatch('[^\r\n]+') do
        local s=line:match('^%s*%[([^%]]+)%]'); if s then section=s end
        local id=section:match('^slot_(%d+)$')
        local name=line:match('^%s*profile_name%s*=%s*(.-)%s*$')
        if id and name and tonumber(id)>=1 and tonumber(id)<=9 then out[tonumber(id)]=name end
    end
    return out
end
function M.fps_sampler()
    local self={samples={}}
    function self:reset() self.samples={} end
    function self:sample(now,n,paused)
        if not M.finite(n) or n<0 then self:reset();return nil end
        if paused then self:reset();return 0 end
        local s=self.samples;local last=s[#s]
        if last and (n<last.n or now<=last.t or now-last.t>4) then self:reset();s=self.samples end
        s[#s+1]={t=now,n=n}
        while #s>2 and s[2].t<=now-2 do table.remove(s,1) end
        if now-s[1].t<.75 then return nil end
        return (n-s[1].n)/(now-s[1].t)
    end
    return self
end
local function unescape(s)
    return s:gsub('&lt;','<'):gsub('&gt;','>'):gsub('&quot;','"'):gsub('&apos;',"'")
        :gsub('&#(%d+);',function(n) n=tonumber(n);return n>=32 and n<127 and string.char(n) or '' end)
        :gsub('&amp;','&')
end
-- Bilibili-compatible XML only. No XML entity expansion, network fetching or code modes.
function M.parse_danmaku(xml)
    if type(xml)~='string' or #xml>16*1024*1024 then return nil,'弹幕文件超过 16 MiB' end
    if xml:upper():find('<!DOCTYPE',1,true) or xml:upper():find('<!ENTITY',1,true) then return nil,'不支持 XML 外部实体' end
    local out={}
    for params,text in xml:gmatch('<d%s+p%s*=%s*["\']([^"\']+)["\'][^>]*>(.-)</d>') do
        local fields={};for field in (params..','):gmatch('(.-),') do fields[#fields+1]=field end
        local t,mode,color=tonumber(fields[1]),tonumber(fields[2]),tonumber(fields[4])
        if M.finite(t) and t>=0 and t<604800 and (mode==1 or mode==4 or mode==5 or mode==6) then
            text=M.clean(unescape(text)):gsub('[\r\n]+',' ')
            local chars=M.chars(text);if #chars>120 then text=table.concat(chars,'',1,120) end
            if text~='' then out[#out+1]={t=t,mode=mode,text=text,color=M.finite(color) and M.clamp(math.floor(color),0,16777215) or 16777215} end
        end
        if #out>=50000 then break end
    end
    table.sort(out,function(a,b)return a.t<b.t end)
    if #out==0 then return nil,'没有可显示的普通 XML 弹幕' end
    return out
end
function M.lower_bound(events,t)
    local lo,hi=1,#events+1
    while lo<hi do local mid=math.floor((lo+hi)/2);if events[mid].t<t then lo=mid+1 else hi=mid end end
    return lo
end
function M.local_media(path,opened,network)
    if network or type(path)~='string' or path=='' then return false end
    local function file_path(s)
        if not s or s=='' then return true end
        if s:match('^%a:[/\\]') then return true end
        if s:match('^%a[%w+.-]*:') or s:sub(1,2)=='//' or s:sub(1,2)=='\\\\' then return false end
        return true
    end
    return file_path(path) and file_path(opened)
end
return M
end)()
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

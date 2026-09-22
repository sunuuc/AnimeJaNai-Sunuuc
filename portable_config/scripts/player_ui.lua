-- Player UI-style controller, rendered with vector icons and system fonts.
local mp=require 'mp'
local utils=require 'mp.utils'
local options=require 'mp.options'
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
-- Player UI layout 1.2.0: the ASS PlayRes IS the window, so glyphs are rasterised at
-- native size and never resampled -- resampling was what made the text soft.
-- ui_scale*dpi scales glyph and icon sizes, and shrinks further when the window
-- is too narrow for the control row.
function M.layout(pw,ph,count,dpi,ui_scale)
    pw,ph=math.max(1,pw),math.max(1,ph)
    local want=M.clamp(tonumber(ui_scale) or 1.00,.45,1.5)*M.clamp(tonumber(dpi) or 1,.75,1.5)
    local w,h=pw,ph
    local built
    for _=1,12 do
        local compact=w<1000*want
        local step=(compact and 54 or 76)*want
        local edge=(compact and 38 or 54)*want
        local y=h-46*want
        local controls={}
        local function button(id,x,bw)
            bw=(bw or 44)*want
            controls[#controls+1]={id=id,x=x,y=y,x0=x-bw/2,x1=x+bw/2,y0=y-22*want,y1=y+22*want}
        end
        button('previous',edge);button('play',edge+step);button('next',edge+2*step);button('volume',edge+3*step)
        local right={'fullscreen'}
        for _,id in ipairs({'settings','danmaku','sub','audio'}) do right[#right+1]=id end
        local x=w-edge
        for _,id in ipairs(right) do button(id,x);x=x-step end
        button('speed',x,58)
        local vx=edge+3*step+26*want
        local ex=math.min(vx+130*want,x-(58*want)/2-14*want)
        local volume=ex-vx>=46*want and {x0=vx,x1=ex,y0=y-15*want,y1=y+15*want,y=y} or nil
        local ok=true
        for i,b in ipairs(controls) do
            if b.x0<0 or b.x1>w or b.y0<0 or b.y1>h then ok=false;break end
            for j=i+1,#controls do
                local c=controls[j]
                if not (b.x1<=c.x0 or c.x1<=b.x0) then ok=false;break end
            end
            if not ok then break end
        end
        if ok then
            built={w=w,h=h,scale=1,ui=want,controls=controls,volume=volume,
                seek={x0=22*want,x1=w-22*want,y0=h-118*want,y1=h-92*want,y=h-105*want},
                title_y=h-186*want,detail_y=h-142*want,margin=26*want,compact=compact,small=false}
            break
        end
        want=want*0.86
    end
    return built or {w=w,h=h,scale=1,ui=want,controls={},volume=nil,
        seek={x0=0,x1=w,y0=h-90,y1=h-70,y=h-80},title_y=h-140,detail_y=h-104,
        margin=18,compact=true,small=false}
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
local metrics=(function()
-- inlined module: player_ui_metrics.lua
-- Native, in-process Windows measurements. Called only while the performance panel is open.
-- No PowerShell/WMI/nvidia-smi loop and no background monitoring process.
local M={}
local ok,ffi=pcall(require,'ffi')
if not ok or ffi.os~='Windows' then return M end
local declared=pcall(ffi.cdef,[[
typedef struct { unsigned long lo, hi; } PLAYER_UI_FILETIME;
typedef struct { unsigned long cb, PageFaultCount; size_t PeakWorkingSetSize, WorkingSetSize,
 QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage, QuotaPeakNonPagedPoolUsage,
 QuotaNonPagedPoolUsage, PagefileUsage, PeakPagefileUsage, PrivateUsage; } PLAYER_UI_PMC;
void* __stdcall GetCurrentProcess(void);
int __stdcall GetProcessTimes(void*, PLAYER_UI_FILETIME*, PLAYER_UI_FILETIME*, PLAYER_UI_FILETIME*, PLAYER_UI_FILETIME*);
unsigned long __stdcall GetActiveProcessorCount(unsigned short);
int __stdcall K32GetProcessMemoryInfo(void*, PLAYER_UI_PMC*, unsigned long);
]])
if not declared then return M end
local k=ffi.load('kernel32')
local last_time,last_cpu
function M.reset() last_time,last_cpu=nil,nil end
function M.read(now)
    local result={}
    local success=pcall(function()
        local handle=k.GetCurrentProcess()
        local t=ffi.new('PLAYER_UI_FILETIME[4]')
        if k.GetProcessTimes(handle,t,t+1,t+2,t+3)~=0 then
            local cpu=(tonumber(t[2].hi)*4294967296+tonumber(t[2].lo)+tonumber(t[3].hi)*4294967296+tonumber(t[3].lo))/1e7
            local cores=math.max(1,tonumber(k.GetActiveProcessorCount(65535)))
            if last_time and now>last_time and cpu>=last_cpu then result.cpu=math.min(100,100*(cpu-last_cpu)/((now-last_time)*cores)) end
            last_time,last_cpu=now,cpu
        end
        local m=ffi.new('PLAYER_UI_PMC[1]');m[0].cb=ffi.sizeof(m[0])
        if k.K32GetProcessMemoryInfo(handle,m,ffi.sizeof(m[0]))~=0 then result.memory=tonumber(m[0].WorkingSetSize) end
    end)
    return success and result or {}
end
return M
end)()
local o={hide_timeout=2.5,network_speed=true,show_clock=true,volume_step=5,ui_scale=1.00,text_outline=0,font='Microsoft YaHei',accent='B47799'}
options.read_options(o,'player_ui')
o.ui_scale=core.clamp(tonumber(o.ui_scale) or 1.00,.45,1.5)
o.text_outline=core.clamp(tonumber(o.text_outline) or 0,0,4)
o.hide_timeout=core.clamp(o.hide_timeout,1,20);o.volume_step=core.clamp(o.volume_step,1,20)
if not o.accent:match('^%x%x%x%x%x%x$') then o.accent='B47799' end
local ui=mp.create_osd_overlay('ass-events');ui.z=20
local state={visible=true,x=-1,y=-1,hover=nil,menu=nil,scroll=0,drag=nil,pressed=nil,
    thumb=nil,thumb_time=nil,rate=nil,fps=nil,cpu=nil,memory=nil}
local layout,buttons,menu_box,menu_items,menus
local render_timer,hide_timer,pulse,network_timer,thumb_timer,clock_timer
local render,request_render,show,sync_timers,open_menu
local samples=core.fps_sampler()
local WHITE,MUTED,PANEL,ACCENT='FFFFFF','BEBEBE','22201F',o.accent
local labels={previous='上一个文件',next='下一个文件',play='播放 / 暂停',volume='音量 / 静音',
    speed='播放速度',audio='音轨',sub='字幕',danmaku='弹幕',ai='超分 / 补帧预设',
    settings='设置',stats='统计信息',playlist='播放列表',fullscreen='全屏',more='更多',
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
    if kind=='stats' then
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
menus=(function()
-- inlined module: player_ui_menu.lua
-- Anchored popovers and a full-height playlist drawer.
-- All rows are derived from player state; no network lookups or guessed media metadata.
return function(c)
    local M={boxes={},rows={},hover_timer=nil,hover_target=nil}
    local s,core=c.state,c.core
    local white,muted,panel,accent='FFFFFF','BEBEBE','2C2C2C',c.accent
    local function close_timer()
        if M.hover_timer then M.hover_timer:kill();M.hover_timer=nil end
        M.hover_target=nil
    end
    function M.close()
        close_timer();M.boxes={};M.rows={};s.menu=nil;s.parent=nil;s.scroll=0;s.parent_scroll=0;s.menu_drag=nil
    end
    function M.open(kind,parent)
        if not M.allowed[kind] then return end
        close_timer();M.hover_blocked=nil
        if s.menu==kind and not parent then M.close();return end
        if parent then s.parent=parent else s.parent=nil;s.parent_scroll=0 end
        s.menu=kind;s.scroll=0;s.menu_drag=nil
        if kind=='ai' then c.read_presets() end
        if kind=='playlist' then s.scroll=math.max(0,c.num('playlist-pos',0)*112-112) end
    end
    function M.back()
        if not s.menu then return false end
        if s.parent then M.hover_blocked=s.menu;s.menu=s.parent;s.parent=nil;s.scroll=s.parent_scroll or 0;s.parent_scroll=0;close_timer()
        else M.close() end
        return true
    end
    local function track_name(t)
        local parts={}
        if t.title and t.title~='' then parts[#parts+1]=core.title(t.title,'') end
        if t.lang and t.lang~='' then parts[#parts+1]=t.lang end
        if t.codec then parts[#parts+1]='('..t.codec:upper()..')' end
        if t.type=='audio' and t['audio-channels'] then parts[#parts+1]=t['audio-channels']..' 声道' end
        return #parts>0 and table.concat(parts,' · ') or ((t.type=='sub' and '字幕 ' or '音轨 ')..t.id)
    end
    function M.data(kind)
        local a={};local title=M.allowed[kind]
        local function row(text,fn,selected,extra)
            local r=extra or {};r.text=text;r.fn=fn;r.selected=selected;r.disabled=fn==nil and not r.target and not r.slider
            a[#a+1]=r;return r
        end
        local function link(text,target,icon)row(text,nil,false,{target=target,icon=icon})end
        local function separator()a[#a+1]={separator=true,h=12}end
        if kind=='settings' then
            link('缩放模式','scale')
            link('超分与补帧','ai')
            link('字幕设置','sub-settings','sub')
            link('弹幕设置','danmaku-settings','danmaku')
            link('统计信息','stats','info')
        elseif kind=='speed' then
            title=nil
            for _,v in ipairs({8,5,3,2,1.5,1.25,1,.5}) do local n=v
                local label=v%1==0 and string.format('%.1fx',v) or string.format('%gx',v)
                row(label,function()c.set_number('speed',n)end,math.abs(c.num('speed',1)-v)<.001)
            end
        elseif kind=='sub' or kind=='audio' then
            local typ=kind=='sub' and 'sub' or 'audio'
            local p=kind=='audio' and 'aid' or (s.sub_slot==2 and 'secondary-sid' or 'sid')
            local selected=tostring(c.prop(p,'no'))
            row('关闭',function()c.set(p,'no')end,selected=='no',{stay=true,key=p..':no'})
            for _,t in ipairs(c.prop('track-list',{}) or {}) do
                if t.type==typ then local id=t.id
                    row(track_name(t),function()
                        c.set_number(p,id)
                        if p=='sid' then c.set_bool('sub-visibility',true) end
                    end,selected==tostring(id),{stay=true,key=p..':'..id})
                end
            end
            separator()
            row(kind=='sub' and '添加字幕' or '添加音轨',function()c.open_file(kind)end,false,{icon='plus'})
            if kind=='audio' then link('音频设置','audio-settings') end
        elseif kind=='danmaku' then
            local d=c.prop('user-data/player_ui/danmaku',{}) or {}
            row('关闭',function()if d.enabled then c.command('script-message','player_ui-danmaku-toggle')end end,not d.loaded or not d.enabled,{stay=true})
            if d.loaded then
                row(core.title('',d.file),function()if not d.enabled then c.command('script-message','player_ui-danmaku-toggle')end end,d.enabled,
                    {stay=true,wrap=5,detail='共 '..tostring(d.count or 0)..' 条弹幕'})
            end
            separator()
            if d.loaded then row(d.enabled and '隐藏弹幕' or '显示弹幕',function()c.command('script-message','player_ui-danmaku-toggle')end,false,{stay=true}) end
            row('加载本地弹幕',function()c.command('script-message','player_ui-danmaku-choose')end)
            link('弹幕设置','danmaku-settings')
        elseif kind=='ai' then
            title=nil
            local id=c.current_slot()
            row('关闭',function()c.select_slot(0)end,id==0,{hint='Ctrl+0',key='preset:0'})
            for n=1,9 do local v=n;local name=c.presets()[n]
                if name then row(name,function()c.select_slot(v)end,id==v,{hint='Ctrl+'..v,key='preset:'..v}) end
            end
            for _,t in ipairs({{1001,'质量'},{1002,'均衡'},{1003,'性能'}}) do local v=t[1]
                row(t[2],function()c.select_slot(v)end,id==v,{hint='Shift+'..(v-1000),key='preset:'..v})
            end
            separator()
            row('配置管理器',c.manager,false,{icon='settings'})
        elseif kind=='scale' then
            title=nil
            local keep=c.bool('keepaspect',true);local original=c.prop('video-unscaled','no')
            local pan=c.num('panscan',0)
            for _,r in ipairs({{'适应窗口','fit'},{'填充裁剪','fill'},{'拉伸铺满','stretch'},{'原始尺寸','original'}}) do local mode=r[2]
                local selected=(mode=='stretch' and not keep) or (keep and ((mode=='original' and original=='yes') or (original~='yes' and ((mode=='fill' and pan==1) or (mode=='fit' and pan==0)))))
                row(r[1],function()
                    c.set_bool('keepaspect',mode~='stretch');c.set('video-unscaled',mode=='original' and 'yes' or 'no')
                    c.set_number('panscan',mode=='fill' and 1 or 0);c.set_number('video-zoom',0);c.set('video-aspect-override','no')
                end,selected)
            end
        elseif kind=='sub-settings' then
            row('显示字幕',function()c.command('cycle','sub-visibility')end,c.bool('sub-visibility',true),{stay=true})
            row('字号缩放',nil,false,{slider={value=c.num('sub-scale',1),min=.5,max=2,step=.05,format='%.2fx',set=function(v)c.set_number('sub-scale',v)end}})
            row('字幕位置',nil,false,{slider={value=c.num('sub-pos',100),min=0,max=100,step=1,format='%.0f%%',set=function(v)c.set_number('sub-pos',v)end}})
            row('延迟  '..string.format('%+.1f 秒',c.num('sub-delay',0)),nil,false,{h=44})
            row('提前 0.1 秒',function()c.command('add','sub-delay','-0.1')end,false,{stay=true})
            row('延后 0.1 秒',function()c.command('add','sub-delay','0.1')end,false,{stay=true})
            row('重置延迟',function()c.set_number('sub-delay',0)end,false,{stay=true})
        elseif kind=='audio-settings' then
            row('音频延迟  '..string.format('%+.1f 秒',c.num('audio-delay',0)),nil,false,{h=44})
            row('提前 0.1 秒',function()c.command('add','audio-delay','-0.1')end,false,{stay=true})
            row('延后 0.1 秒',function()c.command('add','audio-delay','0.1')end,false,{stay=true})
            row('重置延迟',function()c.set_number('audio-delay',0)end,false,{stay=true})
        elseif kind=='danmaku-settings' then
            local d=c.prop('user-data/player_ui/danmaku',{}) or {}
            row('不透明度',nil,false,{slider={value=d.opacity or 85,min=10,max=100,step=1,format='%.0f%%',set=function(v)c.command('script-message','player_ui-danmaku-opacity',tostring(v))end}})
            row('显示区域',nil,false,{slider={value=d.area or 50,min=25,max=70,step=1,format='%.0f%%',set=function(v)c.command('script-message','player_ui-danmaku-area',tostring(v))end}})
            if d.loaded then separator();row('清除弹幕',function()c.command('script-message','player_ui-danmaku-clear')end) end
        elseif kind=='playlist' then
            local list=c.prop('playlist',{}) or {};local current=c.num('playlist-pos',-1)
            title='播放列表'
            for i,t in ipairs(list) do local pos=i-1
                local duration=core.finite(t.duration) and t.duration or (pos==current and c.num('duration') or nil)
                row(core.title(t.title or '',t.filename),function()c.set_number('playlist-pos',pos)end,current==pos,
                    {h=112,wrap=2,number=i,key='entry:'..tostring(t.id or t.filename or i),detail=duration and core.time(duration) or nil})
            end
        else
            title,a=c.info(kind)
            for _,r in ipairs(a) do r.h=52;r.wrap=2;r.key=r.key or r.text end
        end
        return title,a
    end
    M.allowed={settings='设置',speed='播放速度',sub='字幕',audio='音轨',danmaku='弹幕',ai='超分与补帧',scale='缩放模式',
        ['sub-settings']='字幕设置',['danmaku-settings']='弹幕设置',['audio-settings']='音频设置',stats='统计信息',playlist='播放列表',chapters='章节'}
    local function width(kind,l)
        local widths={speed=144,settings=244,sub=310,audio=330,danmaku=310,ai=374,scale=204,stats=480,playlist=600,chapters=400}
        return math.min(widths[kind] or 330,l.w-24)
    end
    local function measure(items,w,kind)
        local y=0
        for _,r in ipairs(items) do
            local indent=r.icon and 58 or 24
            local available=w-indent-22-(r.hint and 64 or 0)-(r.target and 24 or 0)-(kind=='playlist' and 44 or 0)
            r.lines=core.wrap(r.text or '',available,20,r.wrap or 2)
            r.h=r.h or (r.separator and 12 or r.slider and 88 or math.max(kind=='ai' and 48 or 60,#r.lines*27+22+(r.detail and 27 or 0)))
            r.top=y;y=y+r.h
        end
        return y
    end
    local function anchor(l,id)
        for _,b in ipairs(l.controls) do if b.id==id then return b.x end end
        return l.w-232
    end
    local function header_height(kind,title) return kind=='playlist' and 60 or title and 58 or 0 end
    local function makebox(l,kind,parent)
        local title,items=M.data(kind);local w=width(kind,l);local hh=header_height(kind,title)
        local total=measure(items,w,kind);local bottom=l.h-(kind=='speed' and 102 or 116)
        if kind=='playlist' then
            return {kind=kind,title=title,items=items,x0=l.w-w,x1=l.w,y0=0,y1=l.h,header=60,total=total,view=l.h-72,content=60,drawer=true}
        end
        local h=math.min(hh+total+12,bottom-12);local y=bottom-h
        local x=core.clamp(anchor(l,kind)-w/2,12,l.w-w-12)
        if parent then
            x=parent.x0-w-4
            if x<12 then x=parent.x1+4 end
            if x+w>l.w-12 then x=core.clamp(parent.x0-w-4,12,l.w-w-12) end
            y=core.clamp(parent.y1-h,12,bottom-h)
        end
        return {kind=kind,title=title,items=items,x0=x,x1=x+w,y0=y,y1=y+h,header=hh,total=total,view=h-hh-12,content=y+hh+6}
    end
    function M.draw(l,d,buttons)
        M.boxes={};M.rows={}
        if not s.menu then return M.rows end
        local function add(b) b.menu=true;buttons[#buttons+1]=b end
        local function drawbox(b,parent)
            local w=b.x1-b.x0;local scroll_key=parent and 'parent_scroll' or 'scroll'
            s[scroll_key]=core.clamp(s[scroll_key] or 0,0,math.max(0,b.total-b.view));b.offset=s[scroll_key];b.scroll_key=scroll_key
            M.boxes[#M.boxes+1]=b
            if b.drawer then
                d.rect(b.x0,0,b.x1,l.h,'000000',65)
                d.icon('close',b.x0+30,28,false,false,true)
                add({id='menu-close',x0=b.x0+8,x1=b.x0+52,y0=5,y1=51})
            else
                d.round(b.x0-1.5,b.y0-1.5,b.x1+1.5,b.y1+1.5,15,'121212',15)
                d.round(b.x0,b.y0,b.x1,b.y1,14,panel,0)
            end
            if b.title then
                if b.drawer then d.text(b.x0+65,29,22,b.title,4,white,true)
                else d.text(b.x0+16,b.y0+29,23,b.title,4,white,true,w-125) end
            end
            if b.kind=='sub' then
                local x=b.x1-112;local y=b.y0+20
                d.round(x,y,x+96,y+32,5,'242424',0)
                for i=1,2 do
                    local xx=x+2+(i-1)*47
                    if (s.sub_slot or 1)==i then d.round(xx,y+2,xx+45,y+30,4,'494949',0) end
                    d.text(xx+22.5,y+16,19,tostring(i),5,white)
                    add({id='subtitle-slot-'..i,tab=i,x0=xx,x1=xx+45,y0=y,y1=y+32})
                end
            end
            local bottom=b.content+b.view
            for _,r in ipairs(b.items) do
                if not r.separator then M.rows[#M.rows+1]=r end
                local index=#M.rows
                local yy=b.content+r.top-b.offset;local y1=yy+r.h
                if y1>b.content and yy<bottom then
                    d.clip(b.x0+4,b.content,b.x1-4,bottom,function()
                        if r.separator then d.rect(b.x0+6,yy+6,b.x1-6,yy+7,'4A4A4A',30);return end
                        local box={id='row-'..index,index=index,x0=b.x0+6,x1=b.x1-6,y0=math.max(yy,b.content),y1=math.min(y1,bottom),key=r.key or r.text}
                        local hovered=core.inside(box,s.x,s.y)
                        local picked=r.selected or (r.target and r.target==s.menu)
                        if not b.drawer and (picked or hovered and not r.disabled) then d.round(box.x0,yy+3,box.x1,y1-3,12,picked and '383838' or '353535',0) end
                        if picked and not b.drawer then d.round(b.x0+8,yy+r.h/2-14,b.x0+12,yy+r.h/2+14,2,accent,0) end
                        if not r.disabled then add(box) end
                        local left=b.x0+24
                        if b.drawer then
                            left=b.x0+70
                            if picked then d.circle(b.x0+35,yy+r.h/2,13,accent,0);d.text(b.x0+35,yy+r.h/2,18,'✓',5,white,true)
                            else d.text(b.x0+35,yy+r.h/2,20,string.format('%02d',r.number),5,muted) end
                        elseif r.icon then d.icon(r.icon,b.x0+30,yy+r.h/2,false,false,true);left=b.x0+56 end
                        local color=b.drawer and picked and accent or white
                        if r.slider then
                            local slider=r.slider;local sx=b.x0+24;local ex=b.x1-26;local sy=yy+62
                            d.text(left,yy+22,20,r.text,4,white)
                            d.text(ex,yy+22,19,string.format(slider.format,slider.value),6,muted)
                            d.rect(sx,sy-2,ex,sy+2,'666666',0)
                            local xx=sx+(ex-sx)*core.clamp((slider.value-slider.min)/(slider.max-slider.min),0,1)
                            d.rect(sx,sy-2,xx,sy+2,accent,0);d.circle(xx,sy,7,accent,0)
                            add({id='slider-'..index,slider=index,x0=sx-8,x1=ex+8,y0=sy-18,y1=sy+18,start=sx,finish=ex})
                        else
                            local th=#r.lines*27+(r.detail and 27 or 0);local ty=yy+(r.h-th)/2
                            for _,line in ipairs(r.lines) do d.text(left,ty,20,line,7,color,b.drawer);ty=ty+27 end
                            if r.detail then d.text(left,ty,18,r.detail,7,b.drawer and color or muted,false,w-(left-b.x0)-24) end
                            if r.target then d.text(b.x1-25,yy+r.h/2,28,'›',5,white)
                            elseif r.hint then d.text(b.x1-19,yy+r.h/2,14,r.hint,6,muted) end
                        end
                    end)
                end
            end
            if b.total>b.view then
                local height=math.max(28,b.view*b.view/b.total)
                local sy=b.content+(b.view-height)*b.offset/(b.total-b.view)
                d.round(b.x1-7,sy,b.x1-4,sy+height,1.5,'AAAAAA',40)
                add({id='menu-scroll-'..b.kind,x0=b.x1-13,x1=b.x1,y0=b.content,y1=b.content+b.view,scroll_key=scroll_key,
                    start=b.content,range=b.view-height,max=b.total-b.view,height=height,sy=sy})
            end
        end
        local parent
        if s.parent and s.parent~=s.menu then parent=makebox(l,s.parent);drawbox(parent,true) end
        local b=makebox(l,s.menu,parent);drawbox(b,false)
        return M.rows
    end
    function M.pick(b)
        if b.id=='menu-close' or b.id=='menu-dismiss' then M.close()
        elseif b.tab then s.sub_slot=b.tab
        elseif b.index then
            local r=M.rows[b.index]
            if r and r.target then
                local parent=s.parent or s.menu
                s.parent_scroll=s.parent and s.parent_scroll or s.scroll
                c.open(r.target,parent)
            elseif r and r.fn and not r.disabled then r.fn();if not r.stay then M.close() end end
        end
    end
    function M.press(b,x,y)
        if b.slider then
            local r=M.rows[b.slider]
            if r and r.slider then s.menu_drag={slider=r.slider,box=b};M.drag(x,y);return true end
        elseif b.scroll_key then
            s.menu_drag={box=b,grab=y>=b.sy and y<=b.sy+b.height and y-b.sy or b.height/2}
            M.drag(x,y);return true
        end
        return false
    end
    function M.drag(x,y)
        local p=s.menu_drag;if not p then return end
        if p.slider then
            local r=p.slider;local v=r.min+core.clamp((x-p.box.start)/(p.box.finish-p.box.start),0,1)*(r.max-r.min)
            v=core.clamp(math.floor(v/r.step+.5)*r.step,r.min,r.max)
            if p.last~=v then p.last=v;r.set(v) end
        else local b=p.box;s[b.scroll_key]=core.clamp((y-b.start-p.grab)/math.max(1,b.range),0,1)*b.max end
    end
    function M.wheel(delta,x,y)
        if not s.menu then return false end
        for i=#M.boxes,1,-1 do local b=M.boxes[i]
            if core.inside(b,x,y) then s[b.scroll_key]=core.clamp((s[b.scroll_key] or 0)-delta*(b.drawer and 72 or 60),0,math.max(0,b.total-b.view));return true end
        end
        return s.menu~=nil
    end
    function M.hover(b)
        if not s.menu then close_timer();return end
        local r=b and b.index and M.rows[b.index]
        local target=r and r.target
        if target~=M.hover_blocked then M.hover_blocked=nil end
        if target and target==M.hover_blocked then close_timer();return end
        if target==s.menu then close_timer();return end
        if target==M.hover_target then return end
        close_timer()
        if target then
            M.hover_target=target
            M.hover_timer=c.after(.18,function()
                M.hover_timer=nil;M.hover_target=nil
                if s.menu then
                    s.parent_scroll=s.parent and s.parent_scroll or s.scroll
                    c.open(target,s.parent or s.menu)
                end
            end)
        end
    end
    function M.hit_override(b,x,y)
        if not s.menu then return b end
        if b and b.menu then return b end
        for _,box in ipairs(M.boxes) do if core.inside(box,x,y) then return {id='menu-surface',menu=true} end end
        if s.menu=='playlist' then return {id='menu-dismiss',menu=true} end
        if b and (b.id=='settings' or b.id=='speed' or b.id=='audio' or b.id=='sub' or b.id=='danmaku' or b.id=='playlist') then return b end
        return {id='menu-dismiss',menu=true}
    end
    function M.shutdown()close_timer()end
    return M
end
end)()({
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
    if state.menu=='stats' then actual_sample() end
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
local function text(x,y,size,s,align,color,bold,max,outline)
    if max then s=core.ellipsize(s,max,size) end
    line(string.format('{\\rDefault\\an%d\\pos(%.2f,%.2f)\\fn%s\\fs%d\\b%d\\bord%s\\shad0\\1c&H%s&\\1a&H00&}%s',align or 7,x,y,o.font,size,bold and 1 or 0,string.format('%.2f',outline or o.text_outline),color or WHITE,core.escape(s)))
end
local icon_u=1
local function icon(id,x,y,active,disabled,small)
    local sc=icon_u
    if state.hover==id then circle(x,y,18*sc,WHITE,226) end
    local color=active and ACCENT or WHITE
    local size=(small and 44 or 60)*sc
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
        local py=(layout.seek.y0-14*(layout.ui or 1))*layout.scale-height
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
-- A black window with no feedback is indistinguishable from a frozen player.
-- Opening and buffering are reported on the overlay itself, independently of the
-- control bar, so the state is visible even after the bar auto-hides.
loading_state=function()
    if bool('idle-active',true) or bool('pause') then return nil end
    if bool('paused-for-cache') then return '正在缓冲…' end
    if num('vo-presented-frame-count',0)>0 then return nil end
    -- Nothing is on screen yet. Before the demuxer has parsed any track the list
    -- is empty, which is exactly the "opening" phase a black window hides.
    local tracks=prop('track-list',{}) or {}
    if #tracks==0 then return '正在加载…' end
    for _,t in ipairs(tracks) do
        if t.type=='video' and not t.albumart and t.selected~=false then return '正在加载…' end
    end
end
render=function()
    render_timer=nil
    state.tick=(state.tick or 0)+1
    if bool('window-minimized') then ui:remove();bind_mouse(false);return end
    local pw,ph=mp.get_osd_size();if pw<=0 or ph<=0 then return end
    layout=core.layout(pw,ph,num('playlist-count',0),num('display-hidpi-scale',1),o.ui_scale);buttons={};output={};menu_box=nil
    local u=layout.ui;icon_u=u
    local net=bool('demuxer-via-network') and o.network_speed and not bool('idle-active',true)
    local loading=loading_state()
    if state.visible then
        local band=190*u
        for i=0,47 do local y=layout.h-band+i*band/48
            rect(0,y,layout.w,y+band/48+.2,'000000',math.floor(255-140*(i/47)^1.4))
        end
        -- Only the title stays on the bar. Episode index, resolution, fps and the
        -- timecodes are not read here; they live in the statistics menu instead.
        local count=num('playlist-count',0)
        local seek=layout.seek;local dur=num('duration');local pos=num('time-pos',0)
        -- Track stays dim, the buffered range is clearly brighter, played is accent.
        rect(seek.x0,seek.y-2.5*u,seek.x1,seek.y+2.5*u,WHITE,200)
        if dur and dur>0 then
            local cache=prop('demuxer-cache-state',{}) or {}
            for _,range in ipairs(cache['seekable-ranges'] or {}) do
                if core.finite(range.start) and core.finite(range['end']) then
                    rect(seek.x0+core.clamp(range.start/dur,0,1)*(seek.x1-seek.x0),seek.y-2.5*u,
                        seek.x0+core.clamp(range['end']/dur,0,1)*(seek.x1-seek.x0),seek.y+2.5*u,WHITE,70)
                end
            end
            local p=state.drag=='seek' and seek_value(state.x) or pos
            local x=seek.x0+core.clamp(p/dur,0,1)*(seek.x1-seek.x0)
            rect(seek.x0,seek.y-2.5*u,x,seek.y+2.5*u,ACCENT);circle(x,seek.y,10*u,'4C4C4C',55);circle(x,seek.y,5*u,ACCENT)
            buttons[#buttons+1]={id='seek',x0=seek.x0,x1=seek.x1,y0=seek.y0,y1=seek.y1}
            if core.inside(seek,state.x,state.y) and not state.menu then
                local target=seek_value(state.x)
                rect(state.x-38*u,seek.y0-32*u,state.x+38*u,seek.y0-4*u,PANEL,20);text(state.x,seek.y0-18*u,14*u,core.time(target),5)
                if not state.drag then thumb(target,state.x) end
            else hide_thumb() end
        end
        for _,b in ipairs(layout.controls) do
            local id=b.id;local disabled=false
            if id=='previous' then disabled=count>1 and num('playlist-pos',0)==0 or count<=1 and not bool('seekable') end
            if id=='next' then disabled=count>1 and num('playlist-pos',0)>=count-1 or count<=1 and not bool('seekable') end
            if id=='speed' then
                if state.hover==id then rect(b.x0,b.y0,b.x1,b.y1,WHITE,230) end
                text(b.x,b.y,17*u,(num('speed',1)%1==0 and string.format('%.1fx',num('speed',1)) or string.format('%gx',num('speed',1))),5)
            else
                local drawid=id
                if id=='play' then drawid=(bool('pause') or bool('idle-active',true)) and 'play' or 'pause' end
                if id=='volume' and bool('mute') then drawid='muted' end
                if id=='fullscreen' and bool('fullscreen') then drawid='restore' end
                local d=prop('user-data/player_ui/danmaku',{}) or {}
                icon(drawid,b.x,b.y,state.menu==id or id=='settings' and state.parent=='settings' or id=='danmaku' and d.loaded and d.enabled,disabled)
                if id=='sub' then text(b.x,b.y+1*u,13*u,'CC',5,'222222',true) end
            end
            if not disabled then buttons[#buttons+1]=b end
        end
        if layout.volume then
            local b=layout.volume;local v=core.clamp(num('volume',0)/100,0,1)
            rect(b.x0,b.y-2.5*u,b.x1,b.y+2.5*u,WHITE,145);rect(b.x0,b.y-2.5*u,b.x0+v*(b.x1-b.x0),b.y+2.5*u,ACCENT)
            circle(b.x0+v*(b.x1-b.x0),b.y,9*u,'4C4C4C',40);circle(b.x0+v*(b.x1-b.x0),b.y,5*u,ACCENT)
            buttons[#buttons+1]={id='volume-slider',x0=b.x0,x1=b.x1,y0=b.y0,y1=b.y1}
        end
        for i,id in ipairs({'close','maximize','minimize','pin'}) do
            local x=layout.w-26*u-(i-1)*50*u;local b={id=id,x0=x-22*u,x1=x+22*u,y0=0,y1=38*u}
            buttons[#buttons+1]=b;icon(id,x,19*u,id=='pin' and bool('ontop'),false,true)
        end
        if state.menu then draw_menu() end
        if state.hover and labels[state.hover] and not state.menu then
            local tip=labels[state.hover]
            if count<=1 and (state.hover=='previous' or state.hover=='next') then tip=state.hover=='previous' and '后退 10 秒' or '前进 10 秒' end
            if state.hover=='volume' then tip='音量 '..string.format('%.0f',num('volume',100))..'%' end
            local top=state.y<52*u;local y=top and 46*u or layout.h-78*u
            text(core.clamp(state.x,90*u,layout.w-90*u),y,14*u,tip,5)
        end
    else hide_thumb() end
    if loading then
        local cy=layout.h/2
        rect(0,cy-50*u,layout.w,cy+48*u,'000000',100)
        text(layout.w/2,cy-30*u,24*u,loading,5,WHITE,true)
        for i=1,3 do
            local on=((state.tick+i)%3==0)
            circle(layout.w/2+(i-2)*22*u,cy+34*u,on and 3.5*u or 2*u,on and ACCENT or WHITE,on and 0 or 140)
        end
    end
    -- The episode name and the read rate belong to the bar. They are drawn in the
    -- bar's own title slot (name on top, rate directly under it) and NOT AT ALL
    -- once it retracts, so nothing stays pinned over the picture. Drawing them
    -- after an auto-hidden bar put a permanent caption across the bottom of the
    -- frame, which is exactly what it looked like: something left hanging there.
    local title=core.title(mp.get_property('media-title',''),mp.get_property('path',''))
    if bool('idle-active',true) then title='' end
    if title~='' and state.visible then
        text(layout.margin,layout.title_y,30*u,title,7,WHITE,false,layout.w-2*layout.margin,0.6)
        if net then text(layout.margin,layout.detail_y,16*u,core.rate(state.rate),7,WHITE,false,nil,0.6) end
    end
    -- The clock sits in the very top-left corner rather than over the frame.
    if o.show_clock and not bool('idle-active',true) then
        text(10*u,8*u,22*u,os.date('%H:%M'),7,MUTED,false,nil,0.6)
    end
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
        performance=state.menu=='stats' and {fps=state.fps,cpu=state.cpu,memory=state.memory} or nil})
end
request_render=function()if not render_timer then render_timer=mp.add_timeout(.035,render) end end
local menu_escape_bound=false
-- A paused player only redraws on demand, so the clock re-arms a one-shot timer that
-- lands on the next minute boundary. It stays live without leaving a repeating timer
-- running while the overlay is hidden.
local function schedule_clock()
    clock_timer=nil
    if not o.show_clock or bool('idle-active',true) or bool('window-minimized') then return end
    clock_timer=mp.add_timeout(60-(os.time()%60),function()
        clock_timer=nil
        request_render()
        schedule_clock()
    end)
end
sync_timers=function()
    local menu_open=state.menu~=nil
    if menu_open~=menu_escape_bound then
        menu_escape_bound=menu_open
        if menu_open then mp.add_forced_key_binding('ESC','player_ui-menu-escape',escape)
        else mp.remove_key_binding('player_ui-menu-escape') end
    end
    local need=not bool('window-minimized') and (state.visible and not bool('pause') and not bool('idle-active',true) or state.menu=='stats' or loading_state()~=nil)
    if need and not pulse then pulse=mp.add_periodic_timer(.25,function()if state.menu=='stats' then actual_sample() end;request_render()end)
    elseif not need and pulse then pulse:kill();pulse=nil end
    local net=not bool('window-minimized') and o.network_speed and bool('demuxer-via-network') and not bool('idle-active',true)
    if net and not network_timer then network_timer=mp.add_periodic_timer(1,function()
        state.rate=bool('demuxer-cache-idle') and 0 or num('cache-speed');request_render()
    end)
    elseif not net and network_timer then network_timer:kill();network_timer=nil;state.rate=nil end
    local want_clock=o.show_clock and not bool('window-minimized') and not bool('idle-active',true)
    if want_clock and not clock_timer then schedule_clock() end
    if not want_clock then kill(clock_timer);clock_timer=nil end
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
        -- The title and clock stay on screen while the bar is hidden, so every observed
        -- change still needs a redraw.
        if p=='pause' then samples:reset();show() else sync_timers();request_render() end
    end)
end
mp.register_event('start-file',function()
    menus.close();state.drag=nil;state.pressed=nil;state.rate=nil;state.fps=nil;samples:reset();hide_thumb();show()
end)
mp.register_event('file-loaded',function()samples:reset();show()end)
mp.register_event('seek',function()samples:reset()end)
mp.register_event('end-file',function()state.rate=nil;hide_thumb();sync_timers()end)
mp.register_event('shutdown',function()
    menus.shutdown();kill(render_timer);kill(hide_timer);kill(pulse);kill(network_timer);kill(thumb_timer);kill(clock_timer);ui:remove();bind_mouse(false)
end)
show()

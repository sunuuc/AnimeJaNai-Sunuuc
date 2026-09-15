-- One owner for native AI startup, slot requests and temporary build pause.
-- No vf observer writes, no file-loaded reconfigure, no periodic playback seek.
local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'
local o = {auto_pause=true, poll_interval=0.25, stats_path=''}
options.read_options(o, 'animejanai_engine_monitor')
local interval = math.max(0.15, math.min(1, tonumber(o.poll_interval) or 0.25))
local path = mp.command_native({'expand-path', '~~/../animejanai/currentanimejanai.' .. utils.getpid() .. '.log'})
local conf = mp.command_native({'expand-path', '~~/../animejanai/animejanai.conf'})
local desired, sent, signature, template, label
local loaded, generation, dispatch_timer, watch_timer = false, 0, nil, nil
local owned_pause, user_takeover, refresh_paused = false, false, false
local pending, tries, watch_deadline, build_deadline, stable = false, 0, 0, nil, nil
local profile_names = {[1001]='Quality',[1002]='Balanced',[1003]='Performance'}

local function slot_number(s)
    s = tostring(s or '')
    if not s:match('^%d+$') then return nil end
    local n = tonumber(s)
    if n and ((n >= 0 and n <= 9) or (n >= 1001 and n <= 1003)) then return n end
end
local function copy(v)
    if type(v) ~= 'table' then return v end
    local r = {}; for k,x in pairs(v) do r[k] = copy(x) end; return r
end
local function key(f)
    if not f then return '' end
    local parts = {f.name or '', f.label or '', tostring(f.enabled ~= false)}
    for k,v in pairs(f.params or {}) do parts[#parts+1] = k .. '=' .. tostring(v) end
    table.sort(parts); return table.concat(parts, '\0')
end
local function native(filters)
    local candidate, idx
    for i,f in ipairs(filters) do
        if f.name == 'animejanai' then
            if f.label == 'aji' then return f,i end
            if candidate then return nil,nil,'存在多个未标识的 AI 滤镜，未自动修改。' end
            candidate,idx = f,i
        end
    end
    return candidate,idx
end
local function read_default()
    local file = io.open(conf, 'r')
    if not file then return nil end
    local section, result
    for line in file:lines() do
        line = line:gsub('^\239\187\191',''):match('^%s*(.-)%s*$')
        if not line:match('^[#;]') then
            local sec = line:match('^%[([^%]]+)%]')
            if sec then section=sec:lower()
            else
                local name,value=line:match('^([%w_]+)%s*=%s*(.-)%s*$')
                if name=='default_slot' and section=='global' then
                    result=slot_number(value:match('^(%d+)'))
                elseif name=='profile_name' then
                    local id=section and section:match('^slot_(%d+)$')
                    if id then profile_names[tonumber(id)]=value end
                end
            end
        end
    end
    file:close(); return result
end
local function kill(which)
    if which then which:kill() end
end
local function release_pause()
    local resume=owned_pause and mp.get_property_bool('pause',false)
    owned_pause=false
    if resume then mp.set_property_bool('pause',false) end
end
local function hold_pause()
    if o.auto_pause and not user_takeover and not mp.get_property_bool('pause',false) then
        owned_pause=true; mp.set_property_bool('pause',true)
    end
end
local function stop_watch(resume)
    kill(watch_timer); watch_timer=nil; stable=nil; build_deadline=nil
    if resume then release_pause() end
end
local function fail(text)
    pending=false; kill(dispatch_timer);dispatch_timer=nil;stop_watch(true)
    msg.error(text);mp.osd_message('AnimeJaNai：' .. text,5)
end
local function has_video()
    for _,t in ipairs(mp.get_property_native('track-list',{}) or {}) do
        if t.type=='video' and t.selected and not t.albumart then return true end
    end
    return false
end
local function read_status()
    local f=io.open(path,'r');if not f then return nil end
    local text=f:read(65537);f:close()
    if not text or #text==0 or #text>65536 or text:sub(-1)~='\n' then return nil end
    text=text:gsub('\r\n','\n')
    local profile=text:match('^Upscale Profile: ([^\n]+)\n')
    if not profile or not text:find('Original Video Resolution:',1,true) then return nil end
    local matches = desired and (desired==0 and profile=='Off' or desired>0 and (desired<10
        and profile:match('^(%d+)%. ') == tostring(desired)
        or desired>=1001 and profile==profile_names[desired]))
    if not matches then return nil end -- previous slot/other process is not completion
    if not text:find('Active Upscale Chain:',1,true) and not text:find('No Chains Activated',1,true) then return nil end
    return text
end
local function finish_status(text)
    local was_building=build_deadline~=nil
    stop_watch(false)
    local failed=desired~=0 and (text:find('FAILED',1,true) or text:find('No Chains Activated',1,true))
    if refresh_paused and not owned_pause and mp.get_property_bool('pause',false)
            and mp.get_property_bool('seekable',false) then
        refresh_paused=false
        mp.commandv('seek','0','relative+exact') -- once, only an explicit paused switch
    end
    refresh_paused=false; release_pause()
    if failed then
        msg.warn('当前配置未完整启用，请查看 Ctrl+J 中的模型/处理链信息。')
        mp.osd_message('AnimeJaNai：当前配置未完整启用，按 Ctrl+J 查看原因。',5)
    elseif was_building then mp.osd_message('AnimeJaNai：引擎已就绪',3) end
end
local function poll()
    if not loaded or not desired or (desired==0 and not refresh_paused) or not has_video() then stop_watch(true);return end
    local f=native(mp.get_property_native('vf',{}) or {})
    if not f or f.enabled==false then stop_watch(true);return end
    local text=read_status()
    local now=mp.get_time()
    if text and text:find('Building TensorRT engine',1,true) then
        stable=nil; build_deadline=build_deadline or now+1200
        hold_pause()
        mp.commandv('vf-command',label or 'aji','poll','1')
        mp.osd_message('AnimeJaNai：正在构建引擎，完成后恢复播放。',interval+0.2)
    elseif text then
        if stable==text then finish_status(text);return end
        stable=text
    else stable=nil end
    if now>(build_deadline or watch_deadline) then
        stop_watch(true);refresh_paused=false
        msg.warn('等待 AI 初始化状态超时；已解除本脚本的暂停，未跳转或重建滤镜。')
        mp.osd_message('AnimeJaNai：暂未确认 AI 初始化完成，按 Ctrl+J 查看状态。',5)
    end
end
local function start_watch(startup)
    stop_watch(false)
    if not loaded or not desired or (desired==0 and not refresh_paused) or not has_video() then release_pause();return end
    watch_deadline=mp.get_time()+8
    if startup and desired>0 then hold_pause() end -- start the clock AFTER the first configured frame
    watch_timer=mp.add_periodic_timer(interval,poll);poll()
end
local function stamp(filters,f,index,n)
    local replacement=copy(f)
    replacement.params=replacement.params or {}
    replacement.params.slot=tostring(n);replacement.params.stats=path
    replacement.label=replacement.label or 'aji';replacement.enabled=true
    local k=key(replacement)
    label=replacement.label
    if k~=key(f) then
        filters[index]=replacement
        local ok,err=mp.set_property_native('vf',filters)
        if not ok then return nil,err end
    end
    template=copy(replacement);signature=k;sent=n
    return true
end
local function new_filter()
    if template then return copy(template) end
    return {name='animejanai',label='aji',params={
        lib='~~/../animejanai/inference/aji.dll',conf=conf,
        ['model-dir']='~~/../animejanai/onnx',['rife-model-dir']='~~/../animejanai/rife',
        trtexec='~~/../animejanai/inference/trtexec.exe',stats=path,slot=tostring(desired)}}
end
local dispatch
local function schedule(delay)
    kill(dispatch_timer)
    local g=generation
    dispatch_timer=mp.add_timeout(delay or 0,function()
        dispatch_timer=nil
        if g==generation then dispatch() end
    end)
end
dispatch=function()
    if not pending or not loaded then return end
    local filters=mp.get_property_native('vf',{}) or {}
    local f,index,err=native(filters)
    local creating=false
    if err then fail(err);return end
    if not f then
        if desired==0 then sent=0;pending=false;stop_watch(true);return end
        for _,other in ipairs(filters) do
            if other.name=='vapoursynth' then
                for _,v in pairs(other.params or {}) do
                    if tostring(v):lower():find('animejanai',1,true) then
                        fail('检测到旧版 VapourSynth AI 处理链，未叠加第二套 AI 滤镜。');return
                    end
                end
            end
        end
        creating=true;f=new_filter();index=#filters+1;filters[index]=f
        -- A missing graph is inserted once with the final slot; never followed
        -- by a racing command aimed at the old/absent graph.
        f.params=f.params or {};f.params.slot='-1'
    end
    if key(f)~=signature then sent=nil end
    label=f.label or 'aji'
    local ok=true
    if creating or (f.params or {}).stats~=path or not signature or f.enabled==false then
        ok,err=stamp(filters,f,index,desired)
    elseif sent~=desired then
        ok,err=mp.commandv('vf-command',label,'slot',tostring(desired))
        if ok then sent=desired end
    end
    if not ok then
        tries=tries+1
        if tries<=5 then schedule(math.min(0.05*2^(tries-1),0.5))
        else fail('配置切换未被播放器接受：' .. tostring(err)) end
        return
    end
    pending=false;tries=0
    mp.set_property_native('user-data/animejanai/requested-slot',desired)
    start_watch(false)
end
local function request(raw)
    local n=slot_number(raw)
    if not n then msg.error('拒绝无效配置槽位：'..tostring(raw));return end
    local filters=mp.get_property_native('vf',{}) or {}
    local f=native(filters)
    if n==desired and sent==n and key(f)==signature and not pending then return end
    desired=n;generation=generation+1;pending=true;tries=0;user_takeover=false
    refresh_paused=loaded and mp.get_property_bool('pause',false) and not owned_pause
    stop_watch(false)
    schedule(0) -- one event-loop turn coalesces queued requests; latest wins
end

-- Remove only the exact unsafe legacy pair, outside quoted text. No disk edits.
local function normalize(cmd)
    local parts,start,quote,escape={},1,nil,false
    for i=1,#cmd do
        local c=cmd:sub(i,i)
        if escape then escape=false
        elseif c=='\\' and quote then escape=true
        elseif quote then if c==quote then quote=nil end
        elseif c=='"' or c=="'" then quote=c
        elseif c==';' then parts[#parts+1]=cmd:sub(start,i-1);start=i+1 end
    end
    if quote then return cmd end
    parts[#parts+1]=cmd:sub(start)
    local changed=false
    for i=1,#parts-1 do
        local a=parts[i]:match('^%s*(.-)%s*$')
        local n=parts[i+1]:match('^%s*script%-message%s+aji%-slot%s+(%d+)%s*$')
        if a:match('^apply%-profile%s+upscale%-on$') and slot_number(n) then parts[i]='';changed=true end
    end
    if not changed then return cmd end
    local out={};for _,p in ipairs(parts) do if p~='' then out[#out+1]=p end end
    return table.concat(out,';')
end
local function repair_bindings()
    local effective={}
    for _,b in ipairs(mp.get_property_native('input-bindings',{}) or {}) do
        if b.section=='default' and not b.is_weak and (b.priority or -1)>=0
                and (not effective[b.key] or b.priority>effective[b.key].priority) then effective[b.key]=b end
    end
    local lines={}
    for k,b in pairs(effective) do
        local updated=normalize(b.cmd or '')
        if updated~=b.cmd and not k:find('[\r\n]') then lines[#lines+1]=k..' '..updated end
    end
    if #lines>0 then
        local ok,err=mp.commandv('load-input-conf','memory://'..table.concat(lines,'\n'))
        if not ok then msg.error('旧快捷键兼容失败：'..tostring(err)) end
    end
end

mp.set_property_native('user-data/animejanai/stats-path',path)
mp.register_script_message('aji-slot',request)
mp.observe_property('pause','bool',function(_,value)
    if owned_pause and value==false then owned_pause=false;user_takeover=true end
end)
mp.add_hook('on_load',-50,function()
    generation=generation+1;kill(dispatch_timer);dispatch_timer=nil
    loaded=false;stop_watch(true);sent=nil;signature=nil;user_takeover=false;refresh_paused=false
    local d=read_default()
    local filters=mp.get_property_native('vf',{}) or {}
    local f,index,err=native(filters)
    desired=desired or d or (f and slot_number((f.params or {}).slot)) or 1002
    os.remove(path)
    if err then msg.error(err)
    elseif f and f.enabled~=false then
        local ok,why=stamp(filters,f,index,desired)
        if not ok then pending=true;tries=0;msg.error('AI 起播配置失败：'..tostring(why)) end
        mp.set_property_native('user-data/animejanai/requested-slot',desired)
    end
    repair_bindings()
end)
mp.register_event('file-loaded',function()
    loaded=true
    if pending then
        if desired>0 and has_video() then hold_pause() end
        schedule(0)
    elseif sent then start_watch(true) end
end)
mp.register_event('end-file',function()
    generation=generation+1;loaded=false;pending=false;sent=nil
    kill(dispatch_timer);dispatch_timer=nil;stop_watch(true);refresh_paused=false
end)
mp.register_event('shutdown',function()
    kill(dispatch_timer);kill(watch_timer);os.remove(path)
end)
repair_bindings()

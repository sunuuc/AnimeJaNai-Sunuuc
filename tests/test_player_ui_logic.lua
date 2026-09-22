local ok,real=pcall(require,'mp')
local root=ok and real.get_property('script-opts'):match('playeruiroot=([^,]+)') or arg[1]
local core=dofile(assert(root)..'/portable_config/script-modules/player_ui_core.lua')
local checks=0
local function check(v,label) checks=checks+1;assert(v,label) end
local function suite()
 check(core.time(3661)=='1:01:01' and core.rate(1250000)=='1.25 MB/s','units')
 check(core.title('', 'https://server.invalid/a/movie.mkv?token=secret')=='movie.mkv','private URL query hidden')
 check(core.escape('{\\pos(1,2)}'):find('\\{',1,true),'escape ASS text')
 for _,size in ipairs({{1280,720},{960,540},{640,360},{2560,1600},{3840,2160},{300,160}}) do
  for _,count in ipairs({0,1,2,100}) do for _,dpi in ipairs({1,1.25,1.5,2}) do
   local l=core.layout(size[1],size[2],count,dpi);local controls={};local ids={}
   for _,b in ipairs(l.controls)do controls[#controls+1]=b;ids[b.id]=b end
   if l.volume then controls[#controls+1]=l.volume end
   check(ids.settings and ids.audio and ids.sub and ids.danmaku and not ids.ai and not ids.stats and not ids.performance,'clean Player UI bottom row')
   check(ids.playlist==nil,'playlist control removed from the bottom row')
   for i,b in ipairs(controls)do
    check(b.x0>=0 and b.x1<=l.w and b.y0>=0 and b.y1<=l.h,'screen bounds')
    for j=i+1,#controls do local c=controls[j];check(b.x1<=c.x0 or c.x1<=b.x0,'non-overlapping hit areas')end
   end
   check(l.title_y>=0 and l.seek.x1>l.seek.x0,'title and seek bounds')
  end end
 end
 local a,b=core.layout(1280,720,2,1),core.layout(2560,1440,2,1)
 check(a.scale==b.scale,'fullscreen does not enlarge controls proportionally')
 local f=core.fps_sampler()
 for i=0,8 do local v=f:sample(i*.25,i*12,false);if i==8 then check(v==48,'native full FPS')end end
 for i=9,16 do local v=f:sample(i*.25,96,false);if i==16 then check(v==0,'stalled FPS')end end
 check(f:sample(5,96,true)==0 and f:sample(5.25,nil,false)==nil,'paused/unavailable counter')
 local xml=assert(core.parse_danmaku('<i><d p="2,1,25,16777215">你好</d><d p="1,5,25,1">a&amp;b</d><d p="3,7,25,1">code</d></i>'))
 check(#xml==2 and xml[1].text=='a&b','XML modes and ordering')
 check(core.parse_danmaku('<!DOCTYPE x [<!ENTITY a SYSTEM "file:///a">]>')==nil,'entity rejection')
 check(core.parse_danmaku(string.rep('a',16*1024*1024+1))==nil,'bounded XML input')
 check(#core.wrap(string.rep('很长的字幕标题',30),260,20,2)==2,'long labels bounded to two lines')
 local now,timers,bindings,messages,observers=0,{},{},{},{}
 local pos={x=0,y=0};local commands={}
 local props={pause=false,['idle-active']=false,['window-minimized']=false,['playlist-count']=1,['playlist-pos']=0,
  ['time-pos']=10,duration=120,seekable=true,volume=50,['volume-max']=100,speed=1,sid=2,aid=1,['secondary-sid']='no',
  ['track-list']={{id=1,type='audio',title='A',selected=true},{id=2,type='sub',title='S',selected=true},{id=3,type='sub',title='Secondary'}},
  ['playlist']={{filename='movie.mkv'}},['media-title']='Title',['video-params']={w=1920,h=1080},['container-fps']=24}
 local function timer(delay,fn,repeated)
  local t={at=now+delay,fn=fn,delay=delay,repeated=repeated,alive=true};function t:kill()self.alive=false end
  timers[#timers+1]=t;return t
 end
 local function advance(dt)
  local limit=now+dt;local n=0
  while true do
   local first
   for _,t in ipairs(timers)do if t.alive and t.at<=limit and(not first or t.at<first.at)then first=t end end
   if not first then break end
   now=first.at;if first.repeated then first.at=now+first.delay else first.alive=false end
   first.fn();n=n+1;assert(n<10000,'timer loop')
  end;now=limit
 end
 local fake={get_time=function()return now end,
  get_property_native=function(n,d)if props[n]~=nil then return props[n]end;return d end,
  get_property_number=function(n,d)if type(props[n])=='number'then return props[n]end;return d end,
  get_property_bool=function(n,d)if type(props[n])=='boolean'then return props[n]end;return d end,
  get_property=function(n,d)if props[n]~=nil then return tostring(props[n])end;return d end,
  set_property_native=function(n,v)props[n]=v;return true end,set_property_number=function(n,v)props[n]=v;return true end,
  set_property_bool=function(n,v)props[n]=v;return true end,set_property=function(n,v)props[n]=v;return true end,
  create_osd_overlay=function()return {update=function()end,remove=function()end}end,
  get_osd_size=function()return 1280,720 end,get_mouse_pos=function()return pos.x,pos.y end,
  command_native=function(a)if a[1]=='expand-path'then return a[2]:gsub('^~~/%.%./',root..'/'):gsub('^~~/',root..'/portable_config/')end end,
  commandv=function(...)local a={...};commands[#commands+1]=a;if a[1]=='cycle'then props[a[2]]=not props[a[2]]end;return true end,
  osd_message=function()end,add_timeout=function(d,f)return timer(d,f,false)end,add_periodic_timer=function(d,f)return timer(d,f,true)end,
  add_key_binding=function(_,n,f)bindings[n]=f end,add_forced_key_binding=function(_,n,f)bindings[n]=f end,
  remove_key_binding=function(n)bindings[n]=nil end,register_script_message=function(n,f)messages[n]=f end,
  observe_property=function(n,_,f)observers[n]=f end,register_event=function()end}
 local saved={mp=package.loaded.mp,opts=package.loaded['mp.options'],utils=package.loaded['mp.utils']}
 package.loaded.mp=fake;package.loaded['mp.options']={read_options=function()end};package.loaded['mp.utils']={parse_json=function()return {}end}
 dofile(root..'/portable_config/scripts/player_ui.lua');advance(.1)
 local function ui()return props['user-data/player_ui/ui']end
 local function button(id)for _,b in ipairs(ui().controls)do if b.id==id then return b end end end
 local function click(id)
  local b=assert(button(id),'missing button '..id);pos.x=(b.x0+b.x1)*.5*ui().scale;pos.y=(b.y0+b.y1)*.5*ui().scale
  bindings['player_ui-move']();advance(.04);bindings['player_ui-click']({event='down'});bindings['player_ui-click']({event='up'});advance(.05)
 end
 local function row(key)
  for i,r in ipairs(ui().rows or {})do if r.key==key or r.target==key or r.text==key then return 'row-'..i end end
  error('missing menu row '..key)
 end
 check(ui().version=='1.1.2','production layout revision')
 bindings['player_ui-volume-up']();bindings['player_ui-volume-down']();check(props.volume==50 and props['time-pos']==10,'volume keys do not seek')
 click('speed');check(ui().menu_boxes[1].x1-ui().menu_boxes[1].x0==144,'speed popover width')
 check(ui().rows[1].text=='8.0x' and ui().rows[8].text=='0.5x','Player UI speed order')
 click(row('1.5x'));check(props.speed==1.5,'speed selection applies')
 click('sub');click('subtitle-slot-2');click(row('secondary-sid:3'))
 check(props.sid==2 and props['secondary-sid']==3,'second subtitle does not overwrite first')
 click('subtitle-slot-1');click(row('sid:no'));check(props.sid=='no' and props['secondary-sid']==3,'independent subtitle off')
 click('settings');check(ui().menu=='settings' and not button('ai'),'settings owns AI and statistics')
 click(row('ai'));check(ui().menu=='ai' and #ui().menu_boxes==2,'AI cascades beside settings')
 local x,y=ui().menu_boxes[1],ui().menu_boxes[2];check(y.x1<=x.x0,'child opens to the left without overlap')
 click(row('preset:0'));check(commands[#commands][2]=='aji-slot' and commands[#commands][3]=='0','reuse AI controller')
 click('settings');click(row('scale'));click(row('填充裁剪'));check(props.panscan==1 and props.keepaspect,'fill crop mode')
 click('settings');click(row('stats'));props.fullscreen=true;bindings['player_ui-menu-escape']();advance(.1)
 check(props.fullscreen and ui().menu=='settings','Esc returns from submenu without leaving fullscreen')
 bindings['player_ui-menu-escape']();advance(.1);check(props.fullscreen and ui().menu=='','Esc closes root menu')
 local n=#commands;local b=button('seek');pos.x=(b.x0+b.x1)*ui().scale/2;pos.y=(b.y0+b.y1)*ui().scale/2
 bindings['player_ui-move']();advance(.1);bindings['player_ui-click']({event='down'});bindings['player_ui-click']({event='up',canceled=true});advance(.1)
 check(#commands==n,'canceled drag does not seek')
 props['playlist-count']=12;props.playlist={}
 for i=1,12 do props.playlist[i]={filename='part'..i..'.mkv'}end
 observers.playlist();advance(.1)
 check(button('playlist')==nil,'playlist drawer is gone with its control')
 bindings['player_ui-leave']();advance(4)
 local active=0;for _,t in ipairs(timers)do if t.alive and t.repeated then active=active+1 end end
 check(active==0,'hidden local video has no repeating UI timer')
 package.loaded.mp=saved.mp;package.loaded['mp.options']=saved.opts;package.loaded['mp.utils']=saved.utils
end
local success,err=xpcall(suite,debug.traceback)
if success then print('PASS Player UI logic: '..checks..' assertions')else print(err)end
if ok then real.commandv('quit',success and 0 or 1)elseif not success then os.exit(1)end

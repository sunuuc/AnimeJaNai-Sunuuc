local ok,real=pcall(require,'mp')
local root=ok and real.get_property('script-opts'):match('playeruiroot=([^,]+)') or arg[1]
assert(root,'test root missing')
local core=dofile(root..'/portable_config/script-modules/player_ui_core.lua')
local checks=0
local function check(c,m) checks=checks+1;assert(c,m) end
local function suite()
 check(core.time(3661)=='1:01:01','duration formatting')
 check(core.rate(1250000)=='1.25 MB/s','actual bytes per second')
 check(core.title('', 'https://server.invalid/a/movie.mkv?token=secret')=='movie.mkv','URL query not displayed')
 check(core.title('已传入的标题 S1:E18','ignored')=='已传入的标题 S1:E18','preserve supplied title')
 check(core.escape('{\\pos(1,2)}'):find('\\{',1,true)~=nil,'ASS text escaping')
 for _,d in ipairs({{1280,720},{960,540},{640,360},{2560,1600},{3840,2160},{300,160}}) do
  for _,n in ipairs({0,1,2,100}) do
   local l=core.layout(d[1],d[2],n)
   local all={};for _,b in ipairs(l.controls) do all[#all+1]=b end
   if l.volume then all[#all+1]=l.volume end
   for i,b in ipairs(all) do
    check(b.x0>=0 and b.x1<=l.w and b.y0>=0 and b.y1<=l.h,'control bounds')
    for j=i+1,#all do local c=all[j];check(b.x1<=c.x0 or c.x1<=b.x0,'control overlap') end
   end
   check(l.title_y>=0 and l.seek.x0<l.seek.x1,'title/seek bounds')
  end
 end
 local samples=core.fps_sampler()
 for i=0,8 do local f=samples:sample(i*.25,i*12,false);if i==8 then check(f==48,'full rate') end end
 for i=9,16 do local f=samples:sample(i*.25,96,false);if i==16 then check(f==0,'stalled counter') end end
 check(samples:sample(5,96,true)==0,'paused FPS')
 check(samples:sample(5.25,nil,false)==nil,'missing counter not fabricated')
 local parsed=assert(core.parse_danmaku('<i><d p="2,1,25,16777215">你好</d><d p="1,5,25,1">a&amp;b</d><d p="3,7,25,1">code</d></i>'))
 check(#parsed==2 and parsed[1].text=='a&b','XML modes and ordering')
 check(core.parse_danmaku('<!DOCTYPE x [<!ENTITY a SYSTEM "file:///a">]>')==nil,'reject XML entities')
 check(core.parse_danmaku(string.rep('a',16*1024*1024+1))==nil,'bounded XML input')
 local now,timers,bindings,messages,observers=0,{},{},{},{}
 local pos={x=0,y=0};local commands={}
 local props={pause=false,['idle-active']=false,['window-minimized']=false,['playlist-count']=1,['playlist-pos']=0,
  ['time-pos']=10,duration=120,seekable=true,volume=50,['volume-max']=100,speed=1,
  ['track-list']={{id=1,type='audio',title='A',selected=true},{id=2,type='sub',title='S',selected=true}},
  ['playlist']={{filename='movie.mkv'}},['media-title']='Title',['video-params']={w=1920,h=1080},['container-fps']=24}
 local function timer(delay,fn,repeated)
  local t={at=now+delay,fn=fn,delay=delay,repeated=repeated,alive=true}
  function t:kill()self.alive=false end
  timers[#timers+1]=t;return t
 end
 local function advance(dt)
  local until_=now+dt;local iterations=0
  while true do
   local next_
   for _,t in ipairs(timers)do if t.alive and t.at<=until_ and(not next_ or t.at<next_.at)then next_=t end end
   if not next_ then break end
   now=next_.at;if next_.repeated then next_.at=now+next_.delay else next_.alive=false end
   next_.fn();iterations=iterations+1;assert(iterations<10000,'timer loop')
  end
  now=until_
 end
 local fake={
  get_time=function()return now end,
  get_property_native=function(n,d)if props[n]~=nil then return props[n] end;return d end,
  get_property_number=function(n,d)if type(props[n])=='number'then return props[n]end;return d end,
  get_property_bool=function(n,d)if type(props[n])=='boolean'then return props[n]end;return d end,
  get_property=function(n,d)if props[n]~=nil then return tostring(props[n])end;return d end,
  set_property_native=function(n,v)props[n]=v;return true end,
  set_property_number=function(n,v)props[n]=v;return true end,
  set_property_bool=function(n,v)props[n]=v;return true end,
  set_property=function(n,v)props[n]=v;return true end,
  create_osd_overlay=function()return {update=function()end,remove=function()end}end,
  get_osd_size=function()return 1280,720 end,get_mouse_pos=function()return pos.x,pos.y end,
  command_native=function(a)if a[1]=='expand-path'then return a[2]:gsub('^~~/%.%./',root..'/'):gsub('^~~/',root..'/portable_config/')end end,
  commandv=function(...)local a={...};commands[#commands+1]=a;if a[1]=='cycle'then props[a[2]]=not props[a[2]]end;return true end,
  osd_message=function()end,
  add_timeout=function(d,f)return timer(d,f,false)end,
  add_periodic_timer=function(d,f)return timer(d,f,true)end,
  add_key_binding=function(_,n,f)bindings[n]=f end,add_forced_key_binding=function(_,n,f)bindings[n]=f end,
  remove_key_binding=function(n)bindings[n]=nil end,
  register_script_message=function(n,f)messages[n]=f end,
  observe_property=function(n,_,f)observers[n]=f end,
  register_event=function()end,
 }
 local saved={mp=package.loaded.mp,opts=package.loaded['mp.options'],utils=package.loaded['mp.utils']}
 package.loaded.mp=fake;package.loaded['mp.options']={read_options=function()end};package.loaded['mp.utils']={parse_json=function()return {}end}
 dofile(root..'/portable_config/scripts/player_ui.lua');advance(.1)
 check(props['user-data/player_ui/ui'].version=='1.1.0','production UI loaded')
 bindings['player_ui-volume-up']();check(props.volume==55,'Up changes volume')
 bindings['player_ui-volume-down']();check(props.volume==50 and props['time-pos']==10,'Down does not seek')
 local function button(id)for _,b in ipairs(props['user-data/player_ui/ui'].controls)do if b.id==id then return b end end end
 local function click(id)
  local b=assert(button(id),'missing button '..id);local scale=props['user-data/player_ui/ui'].scale
  pos.x=(b.x0+b.x1)*.5*scale;pos.y=(b.y0+b.y1)*.5*scale
  bindings['player_ui-move']();advance(.04)
  bindings['player_ui-click']({event='down'});bindings['player_ui-click']({event='up'});advance(.04)
 end
 check(button('playlist')==nil,'single URL has no guessed episodes')
 click('sub');check(props['user-data/player_ui/ui'].menu=='sub','subtitle button hit')
 click('row-2');check(props.sid==2,'actual subtitle id selected')
 click('speed');click('row-5');check(props.speed==1.5,'speed selection')
 click('ai');click('row-1');check(commands[#commands][2]=='aji-slot' and commands[#commands][3]=='0','existing AI controller used')
 messages['player_ui-menu']('audio');advance(.1);props.fullscreen=true;bindings['player_ui-menu-escape']();advance(.1)
 check(props.fullscreen and props['user-data/player_ui/ui'].menu=='','Esc closes menu first')
 local n=#commands;local b=button('seek');pos.x=(b.x0+b.x1)/2;pos.y=(b.y0+b.y1)/2
 bindings['player_ui-move']();advance(.1);bindings['player_ui-click']({event='down'});bindings['player_ui-click']({event='up',canceled=true});advance(.1)
 check(#commands==n,'canceled drag does not seek')
 props['playlist-count']=2;props.playlist={{filename='a.mkv'},{filename='b.mkv'}};observers.playlist();advance(.1)
 click('playlist');click('row-2');check(props['playlist-pos']==1,'real playlist entry selected')
 bindings['player_ui-leave']();advance(4)
 local active=0;for _,t in ipairs(timers)do if t.alive and t.repeated then active=active+1 end end
 check(active==0,'hidden local-video UI has no repeating timer')
 package.loaded.mp=saved.mp;package.loaded['mp.options']=saved.opts;package.loaded['mp.utils']=saved.utils
end
local success,err=xpcall(suite,debug.traceback)
if success then print('PASS Player UI logic: '..checks..' assertions')else print(err)end
if ok then real.commandv('quit',success and 0 or 1)elseif not success then os.exit(1)end

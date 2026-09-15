-- Deterministic state-machine tests for r4 slot/startup control. No GPU/network.
local real=require'mp'
local msg=require'mp.msg'
local root=real.get_property('script-opts'):match('r2root=([^,]+)')
local saved={mp=package.loaded.mp,options=package.loaded['mp.options'],utils=package.loaded['mp.utils'],open=io.open,remove=os.remove}
local function test()
  local now=10
  local filters={{name='animejanai',label='aji',enabled=true,params={conf='conf.ini',stats='shared.log',slot='8'}},{name='other',params={keep='yes'}}}
  local props={pause=false,seekable=true}
  local events,hooks,observers,messages={}, {}, {}, {}
  local timeouts,periodics,slots={}, {}, {}
  local writes,seeks,repaired,fail_once=0,0,nil,false
  local statustext=nil
  local bindings={{section='default',is_weak=false,priority=0,key='Ctrl+8',cmd='apply-profile upscale-on; script-message aji-slot 8'}}
  local function notify(n,v) if observers[n] then observers[n](n,v) end end
  local fake={
    get_time=function() return now end,
    get_property=function(n,d) local v=props[n];if v==nil then return d end;return v end,
    get_property_bool=function(n,d) local v=props[n];if v==nil then return d end;return v end,
    get_property_native=function(n,d)
      if n=='vf' then return filters elseif n=='track-list' then return {{type='video',selected=true,albumart=false}}
      elseif n=='input-bindings' then return bindings end
      local v=props[n];if v==nil then return d end;return v
    end,
    set_property_bool=function(n,v) props[n]=v;notify(n,v);return true end,
    set_property_native=function(n,v) if n=='vf' then filters=v;writes=writes+1 else props[n]=v end;return true end,
    command_native=function(a) if a[1]=='expand-path' then if a[2]:find('currentanimejanai',1,true) then return 'stats.log' elseif a[2]:find('animejanai.conf',1,true) then return 'conf.ini' end;return 'virtual/'..a[2] end end,
    commandv=function(...)
      local a={...}
      if a[1]=='vf-command' and a[3]=='slot' then if fail_once then fail_once=false;return false,'busy' end;slots[#slots+1]=tonumber(a[4]);return true end
      if a[1]=='load-input-conf' then repaired=a[2];return true end
      if a[1]=='seek' then seeks=seeks+1;return true end
      return true
    end,
    add_hook=function(n,_,f) hooks[n]=f end,register_event=function(n,f) events[n]=f end,
    observe_property=function(n,_,f) observers[n]=f end,register_script_message=function(n,f) messages[n]=f end,
    set_property=function(n,v) props[n]=v;return true end,osd_message=function() end,add_key_binding=function() end,
    add_timeout=function(_,f) local t={alive=true,fn=f};function t:kill() self.alive=false end;timeouts[#timeouts+1]=t;return t end,
    add_periodic_timer=function(_,f) local t={alive=true,fn=f};function t:kill() self.alive=false end;periodics[#periodics+1]=t;return t end,
  }
  package.loaded.mp=fake;package.loaded['mp.options']={read_options=function()end};package.loaded['mp.utils']={getpid=function()return 4242 end}
  os.remove=function() return true end
  io.open=function(path)
    if path=='conf.ini' then local lines={'[global]','default_slot=7','[slot_7]','profile_name=2×补帧 + 2K｜高质量'};return {lines=function()local i=0;return function()i=i+1;return lines[i]end end,close=function()end} end
    if path=='stats.log' and statustext then return {read=function()return statustext end,close=function()end} end
    return nil
  end
  local function timeout()
    for i=#timeouts,1,-1 do local t=timeouts[i];if t.alive then t.alive=false;t.fn();return end end
    error('no timeout')
  end
  local function status(n)
    statustext='Upscale Profile: '..n..'. Test\nOriginal Video Resolution: 1920x1080\nActive Upscale Chain: 1\n'
    local t=periodics[#periodics];assert(t and t.alive);t.fn();t.fn()
  end
  dofile(root..'/portable_config/scripts/animejanai_slot.lua')
  assert(props['user-data/animejanai/stats-path']=='stats.log')
  assert(repaired and not repaired:find('apply%-profile upscale%-on'),'unsafe legacy key was not neutralized')
  hooks.on_load();assert(writes==1 and filters[1].params.slot=='7' and filters[1].params.stats=='stats.log')
  events['file-loaded']();assert(props.pause==true,'startup was not held until configured status')
  status(7);assert(props.pause==false,'startup pause was not released')
  messages['aji-slot']('8');timeout();assert(slots[#slots]==8 and writes==1,'single key did not switch exactly once')
  status(8)
  local before=#slots;messages['aji-slot']('9');messages['aji-slot']('6');timeout();assert(#slots==before+1 and slots[#slots]==6,'rapid keys were not coalesced to latest')
  status(6)
  fail_once=true;messages['aji-slot']('5');timeout();timeout();assert(slots[#slots]==5,'temporary command failure was not retried')
  status(5)
  props.pause=true;messages['aji-slot']('4');timeout();status(4);assert(seeks==1,'paused switch must refresh exactly once')
  events['end-file']();assert(not periodics[#periodics].alive,'watcher leaked after end-file')
  local before_t=#periodics;dofile(root..'/portable_config/scripts/animejanai_session.lua');dofile(root..'/portable_config/scripts/animejanai_engine_monitor.lua');assert(#periodics==before_t,'retired scripts started background polling')
  msg.info('PASS controls r4: startup/single/rapid/retry/pause/legacy/leak')
end
local ok,err=xpcall(test,debug.traceback)
package.loaded.mp=saved.mp;package.loaded['mp.options']=saved.options;package.loaded['mp.utils']=saved.utils;io.open=saved.open;os.remove=saved.remove
if not ok then msg.error(err) end
real.commandv('quit',ok and 0 or 1)

local root=assert(arg[1])
local clock,events,hooks,timers,messages=0,{},{},{},{}
local props={['stream-open-filename']='https://example.invalid/first',path='https://example.invalid/first',
    ['playlist-count']=2,['playlist-pos']=0,['idle-active']=false}
local fake={}
function fake.get_time()return clock end
function fake.command_native()return root..'/_probe/playback-diagnostic-logic.json' end
function fake.get_property(name,default)return props[name] or default end
function fake.get_property_number(name,default)return props[name] or default end
function fake.get_property_bool(name,default)
    if props[name]==nil then return default end
    return props[name]
end
function fake.set_property()return true end
function fake.set_property_native()return true end
function fake.commandv()return true end
function fake.enable_messages()end
function fake.add_hook(name,_,callback)hooks[name]=callback end
function fake.register_event(name,callback)events[name]=callback end
function fake.add_timeout(delay,callback)
    local timer={due=clock+delay,callback=callback,alive=true}
    function timer:kill()self.alive=false end
    timers[#timers+1]=timer
    return timer
end
function fake.osd_message(value)messages[#messages+1]=value end
package.loaded.mp=fake
package.loaded['mp.utils']={format_json=function()return '{}' end}
package.loaded['mp.msg']={error=function()end}
dofile(root..'/portable_config/scripts/network_playback.lua')
local function advance(seconds)
    clock=clock+seconds
    for _,timer in ipairs(timers) do
        if timer.alive and timer.due<=clock then timer.alive=false;timer.callback() end
    end
end
hooks.on_load()
events['end-file']({reason='error'})
events['start-file']()
props['stream-open-filename']='https://example.invalid/second'
props.path=props['stream-open-filename']
props['playlist-pos']=1
hooks.on_load()
events['file-loaded']()
events['playback-restart']()
advance(1)
assert(#messages==0,'a failed playlist entry must not show a final playback error')
events['end-file']({reason='error'})
props['idle-active']=true
advance(1)
assert(#messages==1 and messages[1]:find('无法打开视频',1,true),'final failure must remain visible')
os.remove(root..'/_probe/playback-diagnostic-logic.json')
print('PASS network playback error lifecycle')

-- Exercise the packaged control scripts without launching browsers or AI jobs.
local real = require 'mp'
local msg = require 'mp.msg'
local root = real.get_property('script-opts'):match('r2root=([^,]+)')
local saved = {mp=package.loaded.mp, options=package.loaded['mp.options'],
    utils=package.loaded['mp.utils'], open=io.open, remove=os.remove}
local function tests()
    assert(root)
    local events, observers, timers, hooks, messages = {}, {}, {}, {}, {}
    local filters={{name='animejanai',params={stats='shared.log',slot='8'}},
        {name='other',params={keep='yes'}}}
    local properties={pause=false,['idle-active']=false}
    local removed, text, writes, subprocesses = {}, nil, 0, 0
    local fake = {
        get_time=function() return 12 end,
        get_property=function(n) return properties[n] end,
        get_property_bool=function(n,d) local v=properties[n];if v==nil then return d end;return v end,
        get_property_native=function(n,d) if n=='vf' then return filters end;local v=properties[n];if v==nil then return d end;return v end,
        set_property=function(n,v) properties[n]=v end,
        set_property_bool=function(n,v) properties[n]=v end,
        set_property_native=function(n,v)
            if n=='vf' then filters=v;writes=writes+1 else properties[n]=v end
            return true
        end,
        command_native=function(a) assert(a[1]=='expand-path');return 'virtual/'..a[2] end,
        commandv=function(...) end,
        command_native_async=function(a,cb)
            subprocesses=subprocesses+1
            assert(a.name=='subprocess' and a.args[3]=='https://github.com/sunuuc/AnimeJaNai-zh-CN/releases')
            cb(false,nil) -- failed browser launch must not quit the player
        end,
        add_hook=function(n,_,f) hooks[n]=f end,
        observe_property=function(n,_,f) observers[n]=f end,
        register_event=function(n,f) events[n]=f end,
        register_script_message=function(n,f) messages[n]=f end,
        add_key_binding=function() end,
        osd_message=function() end,
        add_periodic_timer=function(_,f)
            local t={alive=true,fn=f};function t:kill() self.alive=false end
            timers[#timers+1]=t;return t
        end,
    }
    package.loaded.mp=fake
    package.loaded['mp.options']={read_options=function() end}
    package.loaded['mp.utils']={getpid=function() return 4242 end}
    os.remove=function(p) removed[#removed+1]=p;return true end
    dofile(root..'/portable_config/scripts/animejanai_session.lua')
    hooks.on_load();observers.vf();observers.vf()
    assert(writes==1 and filters[1].params.slot=='8' and filters[2].params.keep=='yes')
    local path=properties['user-data/animejanai/stats-path']
    assert(path:find('currentanimejanai.4242.log',1,true) and filters[1].params.stats==path)
    events.shutdown();assert(#removed==2 and removed[1]==path and removed[2]==path)
    io.open=function(p)
        assert(p==path)
        if text==nil then return nil end
        return {read=function() return text end,close=function() end}
    end
    dofile(root..'/portable_config/scripts/animejanai_engine_monitor.lua')
    assert(#timers==0,'idle monitor must not poll')
    events['file-loaded']();assert(#timers==1)
    local poll=timers[1].fn
    text='Building TensorRT engine for model for 1080p\n';poll();assert(properties.pause)
    text=nil;poll();assert(properties.pause,'missing log resumed playback')
    text='';poll();assert(properties.pause,'empty log resumed playback')
    text='Engine ready\n';poll();assert(properties.pause);poll();assert(not properties.pause)
    text='Building TensorRT engine for model for 1080p\n';poll();assert(properties.pause)
    properties.pause=false;poll() -- user takes over
    properties.pause=true
    text='Engine ready\n';poll();poll();assert(properties.pause,'overrode manual pause')
    events['end-file']();assert(not timers[1].alive)
    dofile(root..'/portable_config/scripts/animejanai_update.lua')
    assert(subprocesses==0,'startup must not run updater or browser')
    messages['animejanai-update']();assert(subprocesses==1)
    msg.info('PASS controls: per-process log/preserved filters/idempotence/idle/missing/empty/manual pause/update failure')
end
local ok,err=xpcall(tests,debug.traceback)
package.loaded.mp=saved.mp;package.loaded['mp.options']=saved.options;package.loaded['mp.utils']=saved.utils
io.open=saved.open;os.remove=saved.remove
if not ok then msg.error(err) end
real.commandv('quit',ok and 0 or 1)

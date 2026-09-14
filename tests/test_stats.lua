-- Executed by the packaged mpv Lua runtime; no external Lua installation.
local real = require 'mp'
local msg = require 'mp.msg'
local root = real.get_property('script-opts'):match('r2root=([^,]+)')
assert(root, 'missing test root')
local now, count, paused, callbacks, events, props, timers, output = 0, 0, false, {}, {}, {}, {}, ''
local fake = {
    get_time=function() return now end,
    get_property_number=function(name, default)
        if name=='vo-presented-frame-count' then return count end
        if name=='estimated-vf-fps' then return 48 end
        if name=='speed' then return 1 end
        return default
    end,
    get_property_bool=function() return paused end,
    get_property_native=function(name, default) return default end,
    get_property=function() return nil end,
    osd_message=function(s) output=s end,
    add_periodic_timer=function(_, f)
        local t={alive=true,fn=f}; function t:kill() self.alive=false end
        timers[#timers+1]=t; return t
    end,
    register_event=function(n,f) events[n]=f end,
    observe_property=function(n,_,f) props[n]=f end,
    add_key_binding=function(_,n,f) callbacks[n]=f end,
}
local saved = package.loaded.mp
package.loaded.mp = fake
local ok, err = pcall(dofile, root .. '/portable_config/scripts/animejanaistats.lua')
package.loaded.mp = saved
assert(ok, err)
callbacks.show_animejanai_stats()
assert(output:find('FPS: --',1,true), output)
local function tick(n, dt) now=now+dt; count=n; timers[#timers].fn() end
for i=1,8 do tick(i*12,.25) end
assert(output:find('FPS: 48.00 / 目标 48.00',1,true), output)
for i=1,8 do tick(96+i*6,.25) end
assert(output:find('FPS: 24.00 / 目标 48.00',1,true), output)
for i=1,8 do tick(144,.25) end
assert(output:find('FPS: 0.00',1,true), output)
paused=true; props.pause(); assert(output:find('FPS: 0.00',1,true),output)
paused=false; props.pause(); assert(output:find('FPS: --',1,true),output)
for i=1,4 do tick(144+i*12,.25) end
assert(output:find('FPS: 48.00',1,true),output)
tick(0,.25); assert(output:find('FPS: --',1,true),output)
count=nil; now=now+.25; timers[#timers].fn();assert(output:find('FPS: --',1,true),output)
callbacks.show_animejanai_stats();assert(not timers[#timers].alive and output=='')
msg.info('PASS native FPS Lua: full/half/stall/pause/resume/reset/unavailable/hidden')
real.commandv('quit', 0)

-- Run alongside all four packaged scripts on a real video in the real runtime.
local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local function check()
    local ok, err = xpcall(function()
        local path = mp.get_property_native('user-data/animejanai/stats-path')
        assert(type(path)=='string', 'session path was not created')
        assert(path:find('currentanimejanai.' .. utils.getpid() .. '.log',1,true),path)
        assert(path:sub(1,1)~='"', 'JSON quoted path cannot be used for file access')
        -- Native counter must remain readable when every controller is loaded.
        assert(mp.get_property_number('vo-presented-frame-count',0)>0)
        mp.commandv('script-binding','animejanaistats/show_animejanai_stats')
        msg.info('PASS packaged scripts: native path/native frame counter/OSD binding')
    end,debug.traceback)
    if not ok then msg.error(err) end
    mp.commandv('quit', ok and 0 or 1)
end
mp.register_event('file-loaded',function() mp.add_timeout(0.75,check) end)

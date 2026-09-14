-- Each external-player process owns its status file. Never read/delete another
-- process's build status, and never rewrite the user's saved configuration.
local mp = require 'mp'
local utils = require 'mp.utils'
local path = mp.command_native({'expand-path',
    '~~/../animejanai/currentanimejanai.' .. tostring(utils.getpid()) .. '.log'})
local changing = false
local function configure()
    if changing then return end
    local filters = mp.get_property_native('vf', {}) or {}
    local changed = false
    for _, f in ipairs(filters) do
        if f.name == 'animejanai' then
            f.params = f.params or {}
            if f.params.stats ~= path then f.params.stats = path; changed = true end
        end
    end
    if changed then
        changing = true
        local ok, applied, err = pcall(mp.set_property_native, 'vf', filters)
        changing = false
        if not ok or not applied then
            require('mp.msg').error('无法隔离当前进程的状态日志: ' .. tostring(ok and err or applied))
        end
    end
end
mp.set_property_native('user-data/animejanai/stats-path', path)
mp.add_hook('on_load', -50, function() os.remove(path); configure() end)
mp.observe_property('vf', 'native', configure)
mp.register_event('shutdown', function() os.remove(path) end)

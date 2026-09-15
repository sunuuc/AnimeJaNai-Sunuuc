-- Real packaged mpv runtime smoke check. Slot state machine is isolated in test_controls.lua.
local mp=require'mp'
local msg=require'mp.msg'
local function check()
  local ok,err=xpcall(function()
    assert(mp.get_property_number('vo-presented-frame-count',0)>0)
    mp.commandv('script-binding','animejanaistats/show_animejanai_stats')
    msg.info('PASS packaged scripts: native frame counter/OSD binding')
  end,debug.traceback)
  if not ok then msg.error(err) end
  mp.commandv('quit',ok and 0 or 1)
end
mp.register_event('file-loaded',function()mp.add_timeout(.75,check)end)

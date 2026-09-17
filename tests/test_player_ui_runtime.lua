local mp=require 'mp'
local msg=require 'mp.msg'
local opts=mp.get_property('script-opts','')
local out=assert(opts:match('playeruiout=([^,]+)'))
local checks,done=0,false
local function finish(ok,err)
 if done then return end;done=true
 if ok then msg.info('PASS Player UI Windows UI: '..checks..' checks')else msg.error(tostring(err))end
 mp.commandv('quit',ok and 0 or 1)
end
local function guard(fn)
 if done then return end
 local ok,e=xpcall(fn,debug.traceback);if not ok then finish(false,e)end
end
local function after(delay,fn)mp.add_timeout(delay,function()guard(fn)end)end
local function check(ok,m)checks=checks+1;assert(ok,m);msg.info('PASS '..m)end
local function ui()return mp.get_property_native('user-data/player_ui/ui',{})end
local function button(id)for _,b in ipairs(ui().controls or {})do if b.id==id then return b end end end
local function click(id,then_)
 local u=ui();local b=assert(button(id),'missing UI control: '..id)
 mp.commandv('mouse',math.floor((b.x0+b.x1)*u.scale/2),math.floor((b.y0+b.y1)*u.scale/2))
 after(.15,function()mp.commandv('keypress','MBTN_LEFT');after(.2,then_)end)
end
local function menu(kind,then_)mp.commandv('script-message','player_ui-menu',kind);after(.15,then_)end
local function shot(name)
 local ok,err=mp.commandv('screenshot-to-file',out..'/'..name..'.png','window')
 check(ok,'rendered screenshot '..name..' '..tostring(err or ''))
end
local steps={}
steps[#steps+1]=function(next_)
 check(ui().version=='1.1.0','Player UI controller loaded in native runtime')
 check(mp.get_property_number('vo-presented-frame-count',0)>0,'native video frame presented')
 check(button('playlist')==nil,'single video has no invented episode list')
 check(button('audio') and button('sub') and button('ai') and button('danmaku'),'requested controls present')
 local items=ui().controls
 for i,b in ipairs(items)do
  check(b.x0>=0 and b.y0>=0 and b.x1*ui().scale<=ui().width+1,'control bounds '..b.id)
  for j=i+1,#items do local c=items[j]
   check(b.x1<=c.x0 or c.x1<=b.x0 or b.y1<=c.y0 or c.y1<=b.y0,'nonoverlap '..b.id..'/'..c.id)
  end
 end
 shot('player_ui-player');next_()
end
steps[#steps+1]=function(next_)
 local t=mp.get_property_number('time-pos',0)
 mp.set_property_number('volume',50);mp.commandv('keypress','UP')
 after(.15,function()
  check(mp.get_property_number('volume')==55,'Up raises volume once');mp.commandv('keypress','DOWN')
  after(.15,function()
   check(mp.get_property_number('volume')==50,'Down lowers volume once')
   check(math.abs(mp.get_property_number('time-pos',0)-t)<.05,'volume keys do not seek');next_()
  end)
 end)
end
steps[#steps+1]=function(next_)
 click('sub',function()
  check(ui().menu=='sub','mouse opens subtitle menu');shot('player_ui-subtitles')
  click('row-2',function()check(mp.get_property('sid')~='no','real subtitle selected');next_()end)
 end)
end
steps[#steps+1]=function(next_)
 click('audio',function()
  check(ui().menu=='audio','mouse opens audio menu');check(#(ui().rows or {})>=4,'actual audio tracks shown')
  click('row-1',function()
   check(mp.get_property('aid')=='no','audio can be disabled')
   menu('audio',function()click('row-2',function()check(mp.get_property('aid')~='no','audio can be restored');next_()end)end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 click('speed',function()click('row-5',function()
  check(mp.get_property_number('speed')==1.5,'speed button applies 1.5x');mp.set_property_number('speed',1);next_()
 end)end)
end
steps[#steps+1]=function(next_)
 click('ai',function()
  check(ui().menu=='ai','mouse opens AI presets');check(#(ui().rows or {})>=13,'configured preset names listed');shot('player_ui-ai-presets')
  click('row-1',function()
   check(mp.get_property_native('vf')==nil or #(mp.get_property_native('vf',{})or{})==0,'AI off does not create a GPU graph');next_()
  end)
 end)
end
steps[#steps+1]=function(next_)
 local sid=mp.get_property('sid');local aid=mp.get_property('aid')
 mp.commandv('script-message','player_ui-danmaku-load',out..'/comments.xml')
 after(.25,function()
  local d=mp.get_property_native('user-data/player_ui/danmaku',{})
  check(d.loaded and d.count==3,'local XML parsed in production danmaku script')
  check(mp.get_property('sid')==sid and mp.get_property('aid')==aid,'danmaku keeps subtitle and audio tracks')
  menu('danmaku',function()shot('player_ui-danmaku');mp.commandv('keypress','ESC');after(.15,next_)end)
 end)
end
steps[#steps+1]=function(next_)
 menu('performance',function()
  after(.9,function()
   local p=ui().performance or {};check(p.fps==0,'performance panel shows zero while paused');shot('player_ui-performance')
   mp.set_property_bool('pause',false)
   after(2,function()
    local f=(ui().performance or {}).fps;check(type(f)=='number' and f>0,'actual native frame counter sampled while playing')
    mp.set_property_bool('pause',true);mp.commandv('keypress','ESC');after(.15,next_)
   end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 mp.commandv('loadfile',out..'/second.y4m','append')
 after(.25,function()
  check(button('playlist')~=nil,'playlist button appears for multiple inputs')
  menu('playlist',function()
   check(#(ui().rows or {})==2,'playlist uses exactly the supplied files');shot('player_ui-playlist')
   click('row-2',function()
    after(.6,function()
     check(mp.get_property_number('playlist-pos')==1,'mouse selects the second real file')
     check(not mp.get_property_native('user-data/player_ui/danmaku',{}).loaded,'next file clears previous danmaku');next_()
    end)
   end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 mp.set_property_number('window-scale',2);mp.commandv('script-message','player_ui-show')
 after(.5,function()check(ui().width>0 and ui().height>0,'resized window layout available');shot('player_ui-compact');next_()end)
end
local index=0
local function next_step()
 index=index+1;if index>#steps then finish(true);return end
 guard(function()steps[index](next_step)end)
end
local started=false
mp.register_event('file-loaded',function()
 if started then return end;started=true;local attempts=0
 local function wait()
  attempts=attempts+1
  if ui().version and mp.get_property_number('vo-presented-frame-count',0)>0 then next_step()
  elseif attempts<30 then after(.2,wait)else error('UI or video output did not initialize')end
 end
 after(.5,wait)
end)
mp.add_timeout(45,function()finish(false,'Player UI UI test deadline exceeded')end)

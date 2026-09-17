local mp=require 'mp'
local msg=require 'mp.msg'
local out=assert(mp.get_property('script-opts',''):match('playeruiout=([^,]+)'))
local checks,done=0,false
local function finish(ok,err)
 if done then return end;done=true
 if ok then msg.info('PASS Player UI Windows UI: '..checks..' checks')else msg.error(tostring(err))end
 mp.commandv('quit',ok and 0 or 1)
end
local function guard(fn)if not done then local ok,e=xpcall(fn,debug.traceback);if not ok then finish(false,e)end end end
local function after(delay,fn)mp.add_timeout(delay,function()guard(fn)end)end
local function check(ok,m)checks=checks+1;assert(ok,m);msg.info('PASS '..m)end
local function ui()return mp.get_property_native('user-data/player_ui/ui',{})end
local function button(id)for _,b in ipairs(ui().controls or {})do if b.id==id then return b end end end
local function click(id,then_)
 local u=ui();local b=assert(button(id),'missing UI control: '..id)
 mp.commandv('mouse',math.floor((b.x0+b.x1)*u.scale/2),math.floor((b.y0+b.y1)*u.scale/2))
 after(.06,function()mp.commandv('keypress','MBTN_LEFT');after(.15,then_)end)
end
local function row(key)
 for i,r in ipairs(ui().rows or {})do if r.key==key or r.target==key or r.text==key then return 'row-'..i end end
 error('missing row '..key)
end
local function menu(kind,then_)mp.commandv('script-message','player_ui-menu',kind);after(.15,then_)end
local function close(then_)mp.commandv('script-message','player_ui-hide');after(.1,function()mp.commandv('script-message','player_ui-show');after(.1,then_)end)end
local function shot(name)
 local ok,err=mp.commandv('screenshot-to-file',out..'/'..name..'.png','window');check(ok,'screenshot '..name..' '..tostring(err or ''))
end
local steps={}
steps[#steps+1]=function(next_)
 check(ui().version=='1.1.1','Player UI controller version')
 check(mp.get_property_number('vo-presented-frame-count',0)>0,'native video output')
 check(not button('playlist'),'single input has no invented episode list')
 check(button('settings') and button('audio') and button('sub') and button('danmaku'),'Player UI bottom row')
 check(not button('ai') and not button('stats') and not button('performance'),'secondary features are inside settings')
 for i,b in ipairs(ui().controls)do
  check(b.x0>=0 and b.y0>=0 and b.x1*ui().scale<=ui().width+1,'bounds '..b.id)
  for j=i+1,#ui().controls do local c=ui().controls[j]
   check(b.x1<=c.x0 or c.x1<=b.x0 or b.y1<=c.y0 or c.y1<=b.y0,'nonoverlap '..b.id..'/'..c.id)
  end
 end
 shot('player_ui-player');next_()
end
steps[#steps+1]=function(next_)
 local t=mp.get_property_number('time-pos',0);mp.set_property_number('volume',50);mp.commandv('keypress','UP')
 after(.1,function()
  check(mp.get_property_number('volume')==55,'Up raises volume once');mp.commandv('keypress','DOWN')
  after(.1,function()check(mp.get_property_number('volume')==50 and math.abs(mp.get_property_number('time-pos',0)-t)<.05,'Down changes volume without seeking');next_()end)
 end)
end
steps[#steps+1]=function(next_)
 click('speed',function()
  check(ui().menu=='speed','speed popover opens')
  local b=ui().menu_boxes[1];check(b.x1-b.x0==144,'narrow speed popover')
  check(ui().rows[1].text=='8.0x' and ui().rows[8].text=='0.5x','descending speed order');shot('player_ui-speed')
  click(row('1.5x'),function()check(mp.get_property_number('speed')==1.5,'speed applies');mp.set_property_number('speed',1);next_()end)
 end)
end
steps[#steps+1]=function(next_)
 local f=assert(io.open(out..'/second-subtitle.srt','wb'));f:write('1\n00:00:00,000 --> 00:00:12,000\nSecondary subtitles\n');f:close()
 mp.commandv('sub-add',out..'/second-subtitle.srt','auto')
 after(.15,function()
  click('sub',function()
   check(ui().menu=='sub' and button('subtitle-slot-1') and button('subtitle-slot-2'),'subtitle slot selector')
   shot('player_ui-subtitles');local primary=mp.get_property('sid')
   click('subtitle-slot-2',function()
    click(row('secondary-sid:2'),function()
     check(mp.get_property('sid')==primary and mp.get_property_number('secondary-sid')==2,'secondary subtitle does not overwrite primary')
     click(row('secondary-sid:no'),function()check(mp.get_property('sid')==primary and mp.get_property('secondary-sid')=='no','independent subtitle off');close(next_)end)
    end)
   end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 click('audio',function()
  check(ui().menu=='audio','audio menu')
  click(row('aid:no'),function()
   check(mp.get_property('aid')=='no','audio disabled')
   click(row('aid:1'),function()check(mp.get_property_number('aid')==1,'audio restored');close(next_)end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 click('settings',function()
  check(ui().menu=='settings','settings root');shot('player_ui-settings')
  click(row('ai'),function()
   check(ui().menu=='ai' and #ui().menu_boxes==2,'AI submenu beside settings')
   local a,b=ui().menu_boxes[1],ui().menu_boxes[2];check(b.x1<a.x0 and b.y0>=0,'left submenu placement')
   check(#ui().rows>=19,'all configured presets retained');shot('player_ui-ai-presets')
   click(row('preset:0'),function()check(#(mp.get_property_native('vf',{})or{})==0,'AI off does not create a graph');next_()end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 click('settings',function()click(row('scale'),function()
  shot('player_ui-scale')
  click(row('填充裁剪'),function()
   check(mp.get_property_number('panscan')==1 and mp.get_property_bool('keepaspect'),'real fill/crop mode')
   mp.set_property_number('panscan',0);next_()
  end)
 end)end)
end
steps[#steps+1]=function(next_)
 local sid,aid=mp.get_property('sid'),mp.get_property('aid')
 mp.commandv('script-message','player_ui-danmaku-load',out..'/comments.xml')
 after(.2,function()
  local d=mp.get_property_native('user-data/player_ui/danmaku',{})
  check(d.loaded and d.count==3,'XML danmaku loaded')
  check(mp.get_property('sid')==sid and mp.get_property('aid')==aid,'independent danmaku layer')
  click('danmaku',function()
   shot('player_ui-danmaku');check(ui().rows[2].selected,'loaded danmaku entry selected')
   click(row('danmaku-settings'),function()
    shot('player_ui-danmaku-settings')
    local slider
    for _,b in ipairs(ui().controls)do if b.slider then slider=b;break end end
    check(slider~=nil,'danmaku settings slider present')
    local u=ui();mp.commandv('mouse',math.floor(slider.finish*u.scale),math.floor((slider.y0+slider.y1)/2*u.scale))
    after(.08,function()mp.commandv('keypress','MBTN_LEFT');after(.15,function()
     check(mp.get_property_native('user-data/player_ui/danmaku',{}).opacity==100,'opacity slider changes live renderer');close(next_)end)
    end)
   end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 click('settings',function()click(row('performance'),function()
  after(.9,function()
   check((ui().performance or {}).fps==0,'paused actual FPS');shot('player_ui-performance')
   mp.set_property_bool('pause',false)
   after(2,function()
    local fps=(ui().performance or {}).fps;check(type(fps)=='number' and fps>0,'playing actual FPS')
    mp.set_property_bool('pause',true);mp.commandv('keypress','ESC')
    after(.1,function()check(ui().menu=='settings','Esc returns to settings');close(next_)end)
   end)
  end)
 end)end)
end
steps[#steps+1]=function(next_)
 for i=1,8 do mp.commandv('loadfile',out..'/second.y4m','append')end
 after(.2,function()
  check(button('playlist')~=nil,'playlist button appears for actual entries')
  click('playlist',function()
   check(#ui().rows==9,'drawer lists exactly nine supplied entries')
   local b=ui().menu_boxes[1];check(b.y0==0 and b.y1*ui().scale==ui().height and b.x1*ui().scale==ui().width,'right drawer fills window height')
   check(button('menu-scroll-playlist')~=nil,'playlist scrollbar');shot('player_ui-playlist')
   click('row-2',function()after(.3,function()
    check(mp.get_property_number('playlist-pos')==1,'second actual entry selected')
    check(not mp.get_property_native('user-data/player_ui/danmaku',{}).loaded,'new video clears old danmaku');next_()
   end)end)
  end)
 end)
end
steps[#steps+1]=function(next_)
 mp.set_property_number('window-scale',2);mp.commandv('script-message','player_ui-show')
 after(.3,function()
  check(ui().width>0 and ui().height>0,'compact window resized')
  click('settings',function()click(row('ai'),function()
   for _,b in ipairs(ui().menu_boxes)do check(b.x0>=0 and b.y0>=0 and b.x1*ui().scale<=ui().width+1 and b.y1*ui().scale<=ui().height+1,'compact menu fits screen')end
   shot('player_ui-compact');next_()
  end)end)
 end)
end
local index=0
local function next_step()index=index+1;if index>#steps then finish(true)else guard(function()steps[index](next_step)end)end end
local started=false
mp.register_event('file-loaded',function()
 if started then return end;started=true;local attempts=0
 local function wait()
  attempts=attempts+1
  if ui().version and mp.get_property_number('vo-presented-frame-count',0)>0 then next_step()
  elseif attempts<30 then after(.2,wait)else error('UI initialization timeout')end
 end
 after(.5,wait)
end)
mp.add_timeout(50,function()finish(false,'Player UI UI test deadline exceeded')end)

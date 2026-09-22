-- Anchored popovers and a full-height playlist drawer.
-- All rows are derived from player state; no network lookups or guessed media metadata.
return function(c)
    local M={boxes={},rows={},hover_timer=nil,hover_target=nil}
    local s,core=c.state,c.core
    local white,muted,panel,accent='FFFFFF','BEBEBE','2C2C2C',c.accent
    local function close_timer()
        if M.hover_timer then M.hover_timer:kill();M.hover_timer=nil end
        M.hover_target=nil
    end
    function M.close()
        close_timer();M.boxes={};M.rows={};s.menu=nil;s.parent=nil;s.scroll=0;s.parent_scroll=0;s.menu_drag=nil
    end
    function M.open(kind,parent)
        if not M.allowed[kind] then return end
        close_timer();M.hover_blocked=nil
        if s.menu==kind and not parent then M.close();return end
        if parent then s.parent=parent else s.parent=nil;s.parent_scroll=0 end
        s.menu=kind;s.scroll=0;s.menu_drag=nil
        if kind=='ai' then c.read_presets() end
        if kind=='playlist' then s.scroll=math.max(0,c.num('playlist-pos',0)*112-112) end
    end
    function M.back()
        if not s.menu then return false end
        if s.parent then M.hover_blocked=s.menu;s.menu=s.parent;s.parent=nil;s.scroll=s.parent_scroll or 0;s.parent_scroll=0;close_timer()
        else M.close() end
        return true
    end
    local function track_name(t)
        local parts={}
        if t.title and t.title~='' then parts[#parts+1]=core.title(t.title,'') end
        if t.lang and t.lang~='' then parts[#parts+1]=t.lang end
        if t.codec then parts[#parts+1]='('..t.codec:upper()..')' end
        if t.type=='audio' and t['audio-channels'] then parts[#parts+1]=t['audio-channels']..' 声道' end
        return #parts>0 and table.concat(parts,' · ') or ((t.type=='sub' and '字幕 ' or '音轨 ')..t.id)
    end
    function M.data(kind)
        local a={};local title=M.allowed[kind]
        local function row(text,fn,selected,extra)
            local r=extra or {};r.text=text;r.fn=fn;r.selected=selected;r.disabled=fn==nil and not r.target and not r.slider
            a[#a+1]=r;return r
        end
        local function link(text,target,icon)row(text,nil,false,{target=target,icon=icon})end
        local function separator()a[#a+1]={separator=true,h=12}end
        if kind=='settings' then
            link('缩放模式','scale')
            link('超分与补帧','ai')
            link('字幕设置','sub-settings','sub')
            link('弹幕设置','danmaku-settings','danmaku')
            link('统计信息','stats','info')
        elseif kind=='speed' then
            title=nil
            for _,v in ipairs({8,5,3,2,1.5,1.25,1,.5}) do local n=v
                local label=v%1==0 and string.format('%.1fx',v) or string.format('%gx',v)
                row(label,function()c.set_number('speed',n)end,math.abs(c.num('speed',1)-v)<.001)
            end
        elseif kind=='sub' or kind=='audio' then
            local typ=kind=='sub' and 'sub' or 'audio'
            local p=kind=='audio' and 'aid' or (s.sub_slot==2 and 'secondary-sid' or 'sid')
            local selected=tostring(c.prop(p,'no'))
            row('关闭',function()c.set(p,'no')end,selected=='no',{stay=true,key=p..':no'})
            for _,t in ipairs(c.prop('track-list',{}) or {}) do
                if t.type==typ then local id=t.id
                    row(track_name(t),function()
                        c.set_number(p,id)
                        if p=='sid' then c.set_bool('sub-visibility',true) end
                    end,selected==tostring(id),{stay=true,key=p..':'..id})
                end
            end
            separator()
            row(kind=='sub' and '添加字幕' or '添加音轨',function()c.open_file(kind)end,false,{icon='plus'})
            if kind=='audio' then link('音频设置','audio-settings') end
        elseif kind=='danmaku' then
            local d=c.prop('user-data/player_ui/danmaku',{}) or {}
            row('关闭',function()if d.enabled then c.command('script-message','player_ui-danmaku-toggle')end end,not d.loaded or not d.enabled,{stay=true})
            if d.loaded then
                row(core.title('',d.file),function()if not d.enabled then c.command('script-message','player_ui-danmaku-toggle')end end,d.enabled,
                    {stay=true,wrap=5,detail='共 '..tostring(d.count or 0)..' 条弹幕'})
            end
            separator()
            if d.loaded then row(d.enabled and '隐藏弹幕' or '显示弹幕',function()c.command('script-message','player_ui-danmaku-toggle')end,false,{stay=true}) end
            row('加载本地弹幕',function()c.command('script-message','player_ui-danmaku-choose')end)
            link('弹幕设置','danmaku-settings')
        elseif kind=='ai' then
            title=nil
            local id=c.current_slot()
            row('关闭',function()c.select_slot(0)end,id==0,{hint='Ctrl+0',key='preset:0'})
            for n=1,9 do local v=n;local name=c.presets()[n]
                if name then row(name,function()c.select_slot(v)end,id==v,{hint='Ctrl+'..v,key='preset:'..v}) end
            end
            for _,t in ipairs({{1001,'质量'},{1002,'均衡'},{1003,'性能'}}) do local v=t[1]
                row(t[2],function()c.select_slot(v)end,id==v,{hint='Shift+'..(v-1000),key='preset:'..v})
            end
            separator()
            row('配置管理器',c.manager,false,{icon='settings'})
        elseif kind=='scale' then
            title=nil
            local keep=c.bool('keepaspect',true);local original=c.prop('video-unscaled','no')
            local pan=c.num('panscan',0)
            for _,r in ipairs({{'适应窗口','fit'},{'填充裁剪','fill'},{'拉伸铺满','stretch'},{'原始尺寸','original'}}) do local mode=r[2]
                local selected=(mode=='stretch' and not keep) or (keep and ((mode=='original' and original=='yes') or (original~='yes' and ((mode=='fill' and pan==1) or (mode=='fit' and pan==0)))))
                row(r[1],function()
                    c.set_bool('keepaspect',mode~='stretch');c.set('video-unscaled',mode=='original' and 'yes' or 'no')
                    c.set_number('panscan',mode=='fill' and 1 or 0);c.set_number('video-zoom',0);c.set('video-aspect-override','no')
                end,selected)
            end
        elseif kind=='sub-settings' then
            row('显示字幕',function()c.command('cycle','sub-visibility')end,c.bool('sub-visibility',true),{stay=true})
            row('字号缩放',nil,false,{slider={value=c.num('sub-scale',1),min=.5,max=2,step=.05,format='%.2fx',set=function(v)c.set_number('sub-scale',v)end}})
            row('字幕位置',nil,false,{slider={value=c.num('sub-pos',100),min=0,max=100,step=1,format='%.0f%%',set=function(v)c.set_number('sub-pos',v)end}})
            row('延迟  '..string.format('%+.1f 秒',c.num('sub-delay',0)),nil,false,{h=44})
            row('提前 0.1 秒',function()c.command('add','sub-delay','-0.1')end,false,{stay=true})
            row('延后 0.1 秒',function()c.command('add','sub-delay','0.1')end,false,{stay=true})
            row('重置延迟',function()c.set_number('sub-delay',0)end,false,{stay=true})
        elseif kind=='audio-settings' then
            row('音频延迟  '..string.format('%+.1f 秒',c.num('audio-delay',0)),nil,false,{h=44})
            row('提前 0.1 秒',function()c.command('add','audio-delay','-0.1')end,false,{stay=true})
            row('延后 0.1 秒',function()c.command('add','audio-delay','0.1')end,false,{stay=true})
            row('重置延迟',function()c.set_number('audio-delay',0)end,false,{stay=true})
        elseif kind=='danmaku-settings' then
            local d=c.prop('user-data/player_ui/danmaku',{}) or {}
            row('不透明度',nil,false,{slider={value=d.opacity or 85,min=10,max=100,step=1,format='%.0f%%',set=function(v)c.command('script-message','player_ui-danmaku-opacity',tostring(v))end}})
            row('显示区域',nil,false,{slider={value=d.area or 50,min=25,max=70,step=1,format='%.0f%%',set=function(v)c.command('script-message','player_ui-danmaku-area',tostring(v))end}})
            if d.loaded then separator();row('清除弹幕',function()c.command('script-message','player_ui-danmaku-clear')end) end
        elseif kind=='playlist' then
            local list=c.prop('playlist',{}) or {};local current=c.num('playlist-pos',-1)
            title='播放列表'
            for i,t in ipairs(list) do local pos=i-1
                local duration=core.finite(t.duration) and t.duration or (pos==current and c.num('duration') or nil)
                row(core.title(t.title or '',t.filename),function()c.set_number('playlist-pos',pos)end,current==pos,
                    {h=112,wrap=2,number=i,key='entry:'..tostring(t.id or t.filename or i),detail=duration and core.time(duration) or nil})
            end
        else
            title,a=c.info(kind)
            for _,r in ipairs(a) do r.h=52;r.wrap=2;r.key=r.key or r.text end
        end
        return title,a
    end
    M.allowed={settings='设置',speed='播放速度',sub='字幕',audio='音轨',danmaku='弹幕',ai='超分与补帧',scale='缩放模式',
        ['sub-settings']='字幕设置',['danmaku-settings']='弹幕设置',['audio-settings']='音频设置',stats='统计信息',playlist='播放列表',chapters='章节'}
    local function width(kind,l)
        local widths={speed=144,settings=244,sub=310,audio=330,danmaku=310,ai=374,scale=204,stats=480,playlist=600,chapters=400}
        return math.min(widths[kind] or 330,l.w-24)
    end
    local function measure(items,w,kind)
        local y=0
        for _,r in ipairs(items) do
            local indent=r.icon and 58 or 24
            local available=w-indent-22-(r.hint and 64 or 0)-(r.target and 24 or 0)-(kind=='playlist' and 44 or 0)
            r.lines=core.wrap(r.text or '',available,20,r.wrap or 2)
            r.h=r.h or (r.separator and 12 or r.slider and 88 or math.max(kind=='ai' and 48 or 60,#r.lines*27+22+(r.detail and 27 or 0)))
            r.top=y;y=y+r.h
        end
        return y
    end
    local function anchor(l,id)
        for _,b in ipairs(l.controls) do if b.id==id then return b.x end end
        return l.w-232
    end
    local function header_height(kind,title) return kind=='playlist' and 60 or title and 58 or 0 end
    local function makebox(l,kind,parent)
        local title,items=M.data(kind);local w=width(kind,l);local hh=header_height(kind,title)
                local total=measure(items,w,kind);local bottom=l.h-(kind=='speed' and 102 or 116)
        if kind=='playlist' then
            return {kind=kind,title=title,items=items,x0=l.w-w,x1=l.w,y0=0,y1=l.h,header=60,total=total,view=l.h-72,content=60,drawer=true}
        end
        local h=math.min(hh+total+12,bottom-12);local y=bottom-h
        local x=core.clamp(anchor(l,kind)-w/2,12,l.w-w-12)
        if parent then
            x=parent.x0-w-4
            if x<12 then x=parent.x1+4 end
            if x+w>l.w-12 then x=core.clamp(parent.x0-w-4,12,l.w-w-12) end
            y=core.clamp(parent.y1-h,12,bottom-h)
        end
        return {kind=kind,title=title,items=items,x0=x,x1=x+w,y0=y,y1=y+h,header=hh,total=total,view=h-hh-12,content=y+hh+6}
    end
    function M.draw(l,d,buttons)
        M.boxes={};M.rows={}
        if not s.menu then return M.rows end
        local function add(b) b.menu=true;buttons[#buttons+1]=b end
        local function drawbox(b,parent)
            local w=b.x1-b.x0;local scroll_key=parent and 'parent_scroll' or 'scroll'
            s[scroll_key]=core.clamp(s[scroll_key] or 0,0,math.max(0,b.total-b.view));b.offset=s[scroll_key];b.scroll_key=scroll_key
            M.boxes[#M.boxes+1]=b
            if b.drawer then
                d.rect(b.x0,0,b.x1,l.h,'000000',65)
                d.icon('close',b.x0+30,28,false,false,true)
                add({id='menu-close',x0=b.x0+8,x1=b.x0+52,y0=5,y1=51})
            else
                d.round(b.x0-1.5,b.y0-1.5,b.x1+1.5,b.y1+1.5,15,'121212',15)
                d.round(b.x0,b.y0,b.x1,b.y1,14,panel,0)
            end
            if b.title then
                if b.drawer then d.text(b.x0+65,29,22,b.title,4,white,true)
                else d.text(b.x0+16,b.y0+29,23,b.title,4,white,true,w-125) end
            end
            if b.kind=='sub' then
                local x=b.x1-112;local y=b.y0+20
                d.round(x,y,x+96,y+32,5,'242424',0)
                for i=1,2 do
                    local xx=x+2+(i-1)*47
                    if (s.sub_slot or 1)==i then d.round(xx,y+2,xx+45,y+30,4,'494949',0) end
                    d.text(xx+22.5,y+16,19,tostring(i),5,white)
                    add({id='subtitle-slot-'..i,tab=i,x0=xx,x1=xx+45,y0=y,y1=y+32})
                end
            end
            local bottom=b.content+b.view
            for _,r in ipairs(b.items) do
                if not r.separator then M.rows[#M.rows+1]=r end
                local index=#M.rows
                local yy=b.content+r.top-b.offset;local y1=yy+r.h
                if y1>b.content and yy<bottom then
                    d.clip(b.x0+4,b.content,b.x1-4,bottom,function()
                        if r.separator then d.rect(b.x0+6,yy+6,b.x1-6,yy+7,'4A4A4A',30);return end
                        local box={id='row-'..index,index=index,x0=b.x0+6,x1=b.x1-6,y0=math.max(yy,b.content),y1=math.min(y1,bottom),key=r.key or r.text}
                        local hovered=core.inside(box,s.x,s.y)
                        local picked=r.selected or (r.target and r.target==s.menu)
                        if not b.drawer and (picked or hovered and not r.disabled) then d.round(box.x0,yy+3,box.x1,y1-3,12,picked and '383838' or '353535',0) end
                        if picked and not b.drawer then d.round(b.x0+8,yy+r.h/2-14,b.x0+12,yy+r.h/2+14,2,accent,0) end
                        if not r.disabled then add(box) end
                        local left=b.x0+24
                        if b.drawer then
                            left=b.x0+70
                            if picked then d.circle(b.x0+35,yy+r.h/2,13,accent,0);d.text(b.x0+35,yy+r.h/2,18,'✓',5,white,true)
                            else d.text(b.x0+35,yy+r.h/2,20,string.format('%02d',r.number),5,muted) end
                        elseif r.icon then d.icon(r.icon,b.x0+30,yy+r.h/2,false,false,true);left=b.x0+56 end
                        local color=b.drawer and picked and accent or white
                        if r.slider then
                            local slider=r.slider;local sx=b.x0+24;local ex=b.x1-26;local sy=yy+62
                            d.text(left,yy+22,20,r.text,4,white)
                            d.text(ex,yy+22,19,string.format(slider.format,slider.value),6,muted)
                            d.rect(sx,sy-2,ex,sy+2,'666666',0)
                            local xx=sx+(ex-sx)*core.clamp((slider.value-slider.min)/(slider.max-slider.min),0,1)
                            d.rect(sx,sy-2,xx,sy+2,accent,0);d.circle(xx,sy,7,accent,0)
                            add({id='slider-'..index,slider=index,x0=sx-8,x1=ex+8,y0=sy-18,y1=sy+18,start=sx,finish=ex})
                        else
                            local th=#r.lines*27+(r.detail and 27 or 0);local ty=yy+(r.h-th)/2
                            for _,line in ipairs(r.lines) do d.text(left,ty,20,line,7,color,b.drawer);ty=ty+27 end
                            if r.detail then d.text(left,ty,18,r.detail,7,b.drawer and color or muted,false,w-(left-b.x0)-24) end
                            if r.target then d.text(b.x1-25,yy+r.h/2,28,'›',5,white)
                            elseif r.hint then d.text(b.x1-19,yy+r.h/2,14,r.hint,6,muted) end
                        end
                    end)
                end
            end
            if b.total>b.view then
                local height=math.max(28,b.view*b.view/b.total)
                local sy=b.content+(b.view-height)*b.offset/(b.total-b.view)
                d.round(b.x1-7,sy,b.x1-4,sy+height,1.5,'AAAAAA',40)
                add({id='menu-scroll-'..b.kind,x0=b.x1-13,x1=b.x1,y0=b.content,y1=b.content+b.view,scroll_key=scroll_key,
                    start=b.content,range=b.view-height,max=b.total-b.view,height=height,sy=sy})
            end
        end
        local parent
        if s.parent and s.parent~=s.menu then parent=makebox(l,s.parent);drawbox(parent,true) end
        local b=makebox(l,s.menu,parent);drawbox(b,false)
        return M.rows
    end
    function M.pick(b)
        if b.id=='menu-close' or b.id=='menu-dismiss' then M.close()
        elseif b.tab then s.sub_slot=b.tab
        elseif b.index then
            local r=M.rows[b.index]
            if r and r.target then
                local parent=s.parent or s.menu
                s.parent_scroll=s.parent and s.parent_scroll or s.scroll
                c.open(r.target,parent)
            elseif r and r.fn and not r.disabled then r.fn();if not r.stay then M.close() end end
        end
    end
    function M.press(b,x,y)
        if b.slider then
            local r=M.rows[b.slider]
            if r and r.slider then s.menu_drag={slider=r.slider,box=b};M.drag(x,y);return true end
        elseif b.scroll_key then
            s.menu_drag={box=b,grab=y>=b.sy and y<=b.sy+b.height and y-b.sy or b.height/2}
            M.drag(x,y);return true
        end
        return false
    end
    function M.drag(x,y)
        local p=s.menu_drag;if not p then return end
        if p.slider then
            local r=p.slider;local v=r.min+core.clamp((x-p.box.start)/(p.box.finish-p.box.start),0,1)*(r.max-r.min)
            v=core.clamp(math.floor(v/r.step+.5)*r.step,r.min,r.max)
            if p.last~=v then p.last=v;r.set(v) end
        else local b=p.box;s[b.scroll_key]=core.clamp((y-b.start-p.grab)/math.max(1,b.range),0,1)*b.max end
    end
    function M.wheel(delta,x,y)
        if not s.menu then return false end
        for i=#M.boxes,1,-1 do local b=M.boxes[i]
            if core.inside(b,x,y) then s[b.scroll_key]=core.clamp((s[b.scroll_key] or 0)-delta*(b.drawer and 72 or 60),0,math.max(0,b.total-b.view));return true end
        end
        return s.menu~=nil
    end
    function M.hover(b)
        if not s.menu then close_timer();return end
        local r=b and b.index and M.rows[b.index]
        local target=r and r.target
        if target~=M.hover_blocked then M.hover_blocked=nil end
        if target and target==M.hover_blocked then close_timer();return end
        if target==s.menu then close_timer();return end
        if target==M.hover_target then return end
        close_timer()
        if target then
            M.hover_target=target
            M.hover_timer=c.after(.18,function()
                M.hover_timer=nil;M.hover_target=nil
                if s.menu then
                    s.parent_scroll=s.parent and s.parent_scroll or s.scroll
                    c.open(target,s.parent or s.menu)
                end
            end)
        end
    end
    function M.hit_override(b,x,y)
        if not s.menu then return b end
        if b and b.menu then return b end
        for _,box in ipairs(M.boxes) do if core.inside(box,x,y) then return {id='menu-surface',menu=true} end end
        if s.menu=='playlist' then return {id='menu-dismiss',menu=true} end
        if b and (b.id=='settings' or b.id=='speed' or b.id=='audio' or b.id=='sub' or b.id=='danmaku' or b.id=='playlist') then return b end
        return {id='menu-dismiss',menu=true}
    end
    function M.shutdown()close_timer()end
    return M
end

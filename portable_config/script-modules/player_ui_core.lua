-- Pure functions shared by the controller and its regression tests. No mpv side effects.
local M = {}
function M.clamp(x, a, b) return math.max(a, math.min(b, x)) end
function M.finite(x) return type(x)=='number' and x==x and x~=math.huge and x~=-math.huge end
function M.clean(s)
    return tostring(s or ''):gsub('[%z\1-\8\11\12\14-\31\127]', '')
end
function M.escape(s)
    return M.clean(s):gsub('\\', '\\\239\187\191'):gsub('{','\\{'):gsub('}', '\\}'):gsub('\r?\n','\\N')
end
-- UTF-8 codepoints without depending on Lua 5.3's utf8 module (mpv uses LuaJIT).
function M.chars(s)
    local t={}; for c in M.clean(s):gmatch('[%z\1-\127\194-\244][\128-\191]*') do t[#t+1]=c end; return t
end
function M.ellipsize(s, max, size)
    local out,used={},0
    local chars=M.chars(s)
    for i,c in ipairs(chars) do
        local width=(#c>1 and 1 or (c:match('[ilI.,! :;|]') and .3 or .6))*size
        if used+width>max-size then return table.concat(out)..'…' end
        out[#out+1]=c;used=used+width
    end
    return table.concat(out)
end
function M.time(v)
    if not M.finite(v) then return '--:--' end
    v=math.max(0,math.floor(v));local h=math.floor(v/3600)
    return h>0 and string.format('%d:%02d:%02d',h,math.floor(v/60)%60,v%60)
        or string.format('%02d:%02d',math.floor(v/60),v%60)
end
function M.rate(v)
    if not M.finite(v) or v<0 then return '-- KB/s' end
    if v>=1000000 then return string.format('%.2f MB/s',v/1000000) end
    return string.format('%.1f KB/s',v/1000)
end
function M.title(title,path)
    title=M.clean(title):gsub('[\r\n]+',' ')
    if title=='' then
        title=M.clean(path)
        if not title:match('^%a[%w+.-]*://') then title=title:gsub('^.*[/\\]','') end
    end
    if title:match('^%a[%w+.-]*://') then
        local tail=title:match('^%a[%w+.-]*://[^/]+/(.*)$') or ''
        title=tail:gsub('[?#].*$', ''):match('([^/]+)/*$') or ''
        title=title:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end)
    end
    if title=='' then title='视频播放' end
    return title
end
-- Anchored Player UI layout 1.1.1: physical DPI, not a percentage of the video height.
function M.layout(pw,ph,count,dpi)
    pw,ph=math.max(1,pw),math.max(1,ph)
    local scale=math.min(M.clamp(tonumber(dpi) or 1,.5,3),pw/920,ph/620)
    local w,h=pw/scale,ph/scale;local compact=w<1100
    local step=compact and 58 or 84;local y=h-66;local controls={}
    local function button(id,x,bw)
        bw=bw or 48
        controls[#controls+1]={id=id,x=x,y=y,x0=x-bw/2,x1=x+bw/2,y0=y-25,y1=y+25}
    end
    button('previous',64);button('play',64+step);button('next',64+2*step);button('volume',64+3*step)
    local right={'fullscreen'}
    if count>1 then right[#right+1]='playlist' end
    for _,id in ipairs({'settings','danmaku','sub','audio'}) do right[#right+1]=id end
    local x=w-64
    for _,id in ipairs(right) do button(id,x);x=x-step end
    button('speed',x,72)
    local vx=64+3*step+38;local ex=math.min(vx+146,x-62)
    local volume=ex-vx>=60 and {x0=vx,x1=ex,y0=y-18,y1=y+18,y=y} or nil
    return {w=w,h=h,scale=scale,controls=controls,volume=volume,
        seek={x0=122,x1=w-122,y0=h-158,y1=h-122,y=h-140},
        title_y=h-254,detail_y=h-204,margin=36,compact=compact,small=false}
end
function M.wrap(value,width,size,maxlines)
    local chars=M.chars(value);local out,line,used={},'',0
    maxlines=maxlines or 2
    for i,c in ipairs(chars) do
        local cw=(#c>1 and 1 or (c:match('[ilI.,! :;|]') and .3 or .6))*size
        if used+cw>width and line~='' then
            if #out==maxlines-1 then out[#out+1]=M.ellipsize(line..table.concat(chars,'',i),width,size);return out end
            out[#out+1]=line;line='';used=0
        end
        line=line..c;used=used+cw
    end
    if line~='' or #out==0 then out[#out+1]=line end
    return out
end
function M.inside(b,x,y) return b and x>=b.x0 and x<=b.x1 and y>=b.y0 and y<=b.y1 end
function M.parse_presets(text)
    local out,section={},''
    for line in tostring(text):gmatch('[^\r\n]+') do
        local s=line:match('^%s*%[([^%]]+)%]'); if s then section=s end
        local id=section:match('^slot_(%d+)$')
        local name=line:match('^%s*profile_name%s*=%s*(.-)%s*$')
        if id and name and tonumber(id)>=1 and tonumber(id)<=9 then out[tonumber(id)]=name end
    end
    return out
end
function M.fps_sampler()
    local self={samples={}}
    function self:reset() self.samples={} end
    function self:sample(now,n,paused)
        if not M.finite(n) or n<0 then self:reset();return nil end
        if paused then self:reset();return 0 end
        local s=self.samples;local last=s[#s]
        if last and (n<last.n or now<=last.t or now-last.t>4) then self:reset();s=self.samples end
        s[#s+1]={t=now,n=n}
        while #s>2 and s[2].t<=now-2 do table.remove(s,1) end
        if now-s[1].t<.75 then return nil end
        return (n-s[1].n)/(now-s[1].t)
    end
    return self
end
local function unescape(s)
    return s:gsub('&lt;','<'):gsub('&gt;','>'):gsub('&quot;','"'):gsub('&apos;',"'")
        :gsub('&#(%d+);',function(n) n=tonumber(n);return n>=32 and n<127 and string.char(n) or '' end)
        :gsub('&amp;','&')
end
-- Bilibili-compatible XML only. No XML entity expansion, network fetching or code modes.
function M.parse_danmaku(xml)
    if type(xml)~='string' or #xml>16*1024*1024 then return nil,'弹幕文件超过 16 MiB' end
    if xml:upper():find('<!DOCTYPE',1,true) or xml:upper():find('<!ENTITY',1,true) then return nil,'不支持 XML 外部实体' end
    local out={}
    for params,text in xml:gmatch('<d%s+p%s*=%s*["\']([^"\']+)["\'][^>]*>(.-)</d>') do
        local fields={};for field in (params..','):gmatch('(.-),') do fields[#fields+1]=field end
        local t,mode,color=tonumber(fields[1]),tonumber(fields[2]),tonumber(fields[4])
        if M.finite(t) and t>=0 and t<604800 and (mode==1 or mode==4 or mode==5 or mode==6) then
            text=M.clean(unescape(text)):gsub('[\r\n]+',' ')
            local chars=M.chars(text);if #chars>120 then text=table.concat(chars,'',1,120) end
            if text~='' then out[#out+1]={t=t,mode=mode,text=text,color=M.finite(color) and M.clamp(math.floor(color),0,16777215) or 16777215} end
        end
        if #out>=50000 then break end
    end
    table.sort(out,function(a,b)return a.t<b.t end)
    if #out==0 then return nil,'没有可显示的普通 XML 弹幕' end
    return out
end
function M.lower_bound(events,t)
    local lo,hi=1,#events+1
    while lo<hi do local mid=math.floor((lo+hi)/2);if events[mid].t<t then lo=mid+1 else hi=mid end end
    return lo
end
return M

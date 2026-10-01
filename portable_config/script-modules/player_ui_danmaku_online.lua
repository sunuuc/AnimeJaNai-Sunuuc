-- Pure online danmaku helpers. The caller owns mpv state and asynchronous jobs.
local M = {}

local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local UTF8_CODEPOINT='[%z\1-\127\194-\244][\128-\191]*'

function M.limit_text(value,limit,clean)
    value=tostring(value or '')
    limit=math.max(0,math.floor(tonumber(limit) or 0))
    if limit==0 then return '' end
    local out,count={},0
    for character in value:gmatch(UTF8_CODEPOINT) do
        if count==limit then out[limit]='…';break end
        count=count+1;out[count]=character
    end
    value=table.concat(out)
    return clean and clean(value) or value
end

function M.episode_id(value)
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
    local id=tostring(value)
    if #id<1 or #id>20 or not id:match('^%d+$') then return nil end
    return id
end

function M.base64(value)
    local out = {}
    for i = 1, #value, 3 do
        local a, b, c = value:byte(i, i + 2)
        b, c = b or 0, c or 0
        local n = a * 65536 + b * 256 + c
        out[#out + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        out[#out + 1] = alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        out[#out + 1] = i + 1 <= #value and alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or '='
        out[#out + 1] = i + 2 <= #value and alphabet:sub(n % 64 + 1, n % 64 + 1) or '='
    end
    return table.concat(out)
end

local function ps_b64(value)
    return "[Convert]::FromBase64String('" .. M.base64(value) .. "')"
end

local function safe_url(url)
    return type(url) == 'string' and not url:find('[%z\r\n]')
        and url:lower():match('^https?://[^/%?#]+') ~= nil
end

-- Build a PowerShell command containing only ASCII and base64 data. This avoids
-- Windows -Command quoting and UTF-8 byte/codepoint confusion for CJK titles.
function M.request_command(url, body, options)
    options = options or {}
    assert(safe_url(url), 'invalid HTTP URL')
    assert(body == nil or type(body) == 'string', 'request body must be a string')

    local timeout = math.floor(math.max(1, math.min(120, tonumber(options.timeout) or 30)))
    local response_limit = math.floor(math.max(65536, math.min(16 * 1024 * 1024,
        tonumber(options.response_limit) or 8 * 1024 * 1024)))
    local parts = {
        "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';try{",
        '[Console]::OutputEncoding=[Text.Encoding]::UTF8;',
        '$utf8=[System.Text.UTF8Encoding]::new($false);',
        '$url=$utf8.GetString(' .. ps_b64(url) .. ');',
        '$request=[System.Net.HttpWebRequest]::Create($url);',
        "$request.UserAgent='AnimeJaNai/1.0';",
        "$request.Timeout=" .. tostring(timeout * 1000) .. ';',
        "$request.ReadWriteTimeout=" .. tostring(timeout * 1000) .. ';',
        '[System.Net.ServicePointManager]::SecurityProtocol=[System.Net.SecurityProtocolType]::Tls12;',
    }

    if body ~= nil then
        parts[#parts + 1] = "$request.Method='POST';$request.ContentType='application/json; charset=utf-8';"
        parts[#parts + 1] = '$body=$utf8.GetString(' .. ps_b64(body) .. ');$bytes=$utf8.GetBytes($body);'
        parts[#parts + 1] = '$request.ContentLength=$bytes.Length;'
    else
        parts[#parts + 1] = "$request.Method='GET';"
    end

    local app_id = tostring(options.app_id or '')
    local app_secret = tostring(options.app_secret or '')
    if app_id ~= '' and app_secret ~= '' then
        local path = url:match('^https?://[^/]+(/[^?#]*)') or '/'
        parts[#parts + 1] = '$appId=$utf8.GetString(' .. ps_b64(app_id) .. ');'
        parts[#parts + 1] = '$secret=$utf8.GetString(' .. ps_b64(app_secret) .. ');'
        parts[#parts + 1] = '$path=$utf8.GetString(' .. ps_b64(path) .. ');'
        parts[#parts + 1] = '$timestamp=[string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();'
        parts[#parts + 1] = '$signing=$appId+$timestamp+$path+$secret;'
        parts[#parts + 1] = '$sha=[Security.Cryptography.SHA256]::Create();'
        parts[#parts + 1] = '$signature=[Convert]::ToBase64String($sha.ComputeHash($utf8.GetBytes($signing)));'
        parts[#parts + 1] = "$request.Headers.Add('X-AppId',$appId);"
        parts[#parts + 1] = "$request.Headers.Add('X-Timestamp',$timestamp);"
        parts[#parts + 1] = "$request.Headers.Add('X-Signature',$signature);"
    end

    if body ~= nil then
        parts[#parts + 1] = '$requestStream=$request.GetRequestStream();'
        parts[#parts + 1] = '$requestStream.Write($bytes,0,$bytes.Length);$requestStream.Dispose();'
    end

    parts[#parts + 1] = '$response=$request.GetResponse();try{$stream=$response.GetResponseStream();'
    parts[#parts + 1] = '$decoder=$utf8.GetDecoder();$buffer=New-Object byte[] 8192;$characters=New-Object char[] 8192;$total=0;'
    parts[#parts + 1] = 'while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){'
    parts[#parts + 1] = '$total+=$read;if($total -gt ' .. tostring(response_limit) .. "){throw 'Response exceeds configured limit'};"
    parts[#parts + 1] = '$count=$decoder.GetChars($buffer,0,$read,$characters,0,$false);[Console]::Out.Write($characters,0,$count)};'
    parts[#parts + 1] = '$count=$decoder.GetChars($buffer,0,0,$characters,0,$true);[Console]::Out.Write($characters,0,$count);'
    parts[#parts + 1] = '[Console]::Out.Flush();$stream.Dispose()}finally{$response.Dispose()}'
    parts[#parts + 1] = "}catch{$exception=$_.Exception;while($exception.InnerException){$exception=$exception.InnerException};$message=$exception.Message;$failed=$exception.Response;"
    parts[#parts + 1] = "if($failed){try{$reader=New-Object IO.StreamReader($failed.GetResponseStream(),$utf8);"
    parts[#parts + 1] = "$buffer=New-Object char[] 4096;$count=$reader.Read($buffer,0,$buffer.Length);"
    parts[#parts + 1] = "$body=New-Object string($buffer,0,$count);$reader.Dispose();if($body.Trim()){"
    parts[#parts + 1] = "try{$errorBody=$body|ConvertFrom-Json;$detail=$errorBody.errorMessage;if(-not $detail){$detail=$errorBody.message};"
    parts[#parts + 1] = "if(-not $detail){$detail=$errorBody.error};if($detail){$message=[string]$detail}else{$message=$body}}catch{$message=$body}"
    parts[#parts + 1] = "}}catch{}finally{$failed.Dispose()}};[Console]::Error.WriteLine($message);exit 1}"

    return table.concat(parts)
end

-- Dandanplay identifies local files by the MD5 of their first 16 MiB. Keep the
-- read bounded and pass the path as base64 so arbitrary filenames cannot alter
-- the PowerShell command line.
function M.hash_command(path)
    assert(type(path) == 'string' and path ~= '', 'file path must not be empty')
    return table.concat({
        "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';try{",
        '$utf8=[System.Text.UTF8Encoding]::new($false);',
        '$path=$utf8.GetString(' .. ps_b64(path) .. ');',
        '$stream=[System.IO.File]::OpenRead($path);try{',
        '$length=[int][Math]::Min($stream.Length,16777216);$buffer=New-Object byte[] $length;$read=0;',
        'while($read -lt $length){$count=$stream.Read($buffer,$read,$length-$read);if($count -le 0){break};$read+=$count};',
        '$md5=[Security.Cryptography.MD5]::Create();try{',
        '$digest=$md5.ComputeHash($buffer,0,$read);',
        "[Console]::Out.Write(([BitConverter]::ToString($digest)).Replace('-','').ToLowerInvariant())",
        '}finally{$md5.Dispose()}}finally{$stream.Dispose()}',
        "}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}",
    })
end

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function M.parse_server_entry(value)
    local entry = trim(value)
    if entry == '' then return nil, '线路地址为空' end
    local split = entry:find('[|#]')
    local url, note
    if split then
        url, note = trim(entry:sub(1, split - 1)), trim(entry:sub(split + 1))
        if note == '' then note = nil end
    else
        url = entry
    end
    url = url:gsub('/+$', '')
    local authority = url:match('^https?://([^/%?#]+)')
    if note and (#note>80 or note:find(',',1,true)) then
        return nil, '线路备注不能超过 80 个字符或包含逗号'
    end
    if not authority or authority:find('@', 1, true) or url:find('%s')
        or url:find('[?#]') or url:find(',',1,true) or #url>2048 then
        return nil, '线路必须是无查询参数的 HTTP 或 HTTPS 基础地址'
    end
    return {url = url, note = note}
end

function M.parse_servers(value)
    local out, seen = {}, {}
    for entry in tostring(value or ''):gmatch('[^,]+') do
        local server = M.parse_server_entry(entry)
        if server and not seen[server.url] and #out < 20 then
            seen[server.url] = true
            out[#out + 1] = server
        end
    end
    return out
end

function M.serialize_servers(servers)
    local out = {}
    for _, server in ipairs(servers or {}) do
        out[#out + 1] = server.note and (server.url .. '|' .. server.note) or server.url
    end
    return table.concat(out, ',')
end

function M.urlencode(value)
    local out = {}
    for i = 1, #tostring(value or '') do
        local byte = tostring(value or ''):byte(i)
        local safe = byte >= 48 and byte <= 57 or byte >= 65 and byte <= 90
            or byte >= 97 and byte <= 122 or byte == 45 or byte == 46 or byte == 95 or byte == 126
        out[#out + 1] = safe and string.char(byte) or string.format('%%%02X', byte)
    end
    return table.concat(out)
end

function M.match_body(name,file_size,video_duration,file_hash)
    local value = tostring(name or ''):gsub('^.*[/\\]', ''):gsub('%.[%w%d]+$', '')
    value=M.limit_text(value,256)
    local escaped = value:gsub('[%z\1-\31\\"]', function(char)
        local byte = char:byte()
        if char == '\\' then return '\\\\' end
        if char == '"' then return '\\"' end
        if char == '\b' then return '\\b' end
        if char == '\f' then return '\\f' end
        if char == '\n' then return '\\n' end
        if char == '\r' then return '\\r' end
        if char == '\t' then return '\\t' end
        return string.format('\\u%04x', byte)
    end)
    local fields={'"fileName":"'..escaped..'"'}
    if type(file_hash)=='string' and #file_hash==32 and file_hash:match('^%x+$') then
        fields[#fields+1]='"fileHash":"'..file_hash:lower()..'"'
    end
    local size=tonumber(file_size)
    if size and size==size and size>0 and size<9007199254740992 then
        fields[#fields+1]='"fileSize":'..tostring(math.floor(size))
    end
    local duration=tonumber(video_duration)
    if duration and duration==duration and duration>0 and duration<=2147483647 then
        fields[#fields+1]='"videoDuration":'..tostring(math.floor(duration))
    end
    return '{'..table.concat(fields,',')..'}'
end

function M.query_name(path, media_title, clean)
    path = tostring(path or '')
    if path ~= '' and not path:match('^%a[%w+.-]*://') then
        local name = path:gsub('^.*[/\\]', ''):gsub('%?.*$', '')
        if name ~= '' and not name:match('^[Ss]tream%.[%w]+$') then return name end
    end
    local title = tostring(media_title or ''):gsub('%s+$', '')
    return clean and clean(title) or title
end

local CHINESE_SEASONS={'一','二','三','四','五','六','七','八','九','十','十一','十二'}
function M.season_number(title)
    title=tostring(title or '')
    local number=title:match('[Ss](%d+)[Ee]%d+') or title:match('第%s*(%d+)%s*季')
    if number then return tonumber(number) end
    for n,word in ipairs(CHINESE_SEASONS) do
        if title:find('第'..word..'季',1,true) then return n end
    end
    return nil
end

local function strip_year(title)
    return title:gsub('%s*[（(]%d%d%d%d[)）]%s*$',''):gsub('[%s%-—–]+$','')
end

function M.episode_query(title)
    title=tostring(title or '')
    local season=M.season_number(title)
    local start,finish=title:find('[Ss]%d+[Ee]%d+')
    local episode=start and tonumber(title:sub(start,finish):match('[Ee](%d+)'))
    local anime=start and strip_year(title:sub(1,start-1)) or nil
    if not anime or anime=='' then
        local marker,tail=title:find('第%s*%d+%s*季')
        if marker then
            anime=strip_year(title:sub(1,marker-1))
            episode=tonumber(title:sub(tail+1):match('第%s*(%d+)%s*[集话話]'))
        end
    end
    if not anime or anime=='' then
        for _,word in ipairs(CHINESE_SEASONS) do
            local marker=title:find('第'..word..'季',1,true)
            if marker then
                anime=strip_year(title:sub(1,marker-1))
                episode=tonumber(title:sub(marker):match('第%s*(%d+)%s*[集话話]'))
                break
            end
        end
    end
    if not episode then
        local prefix,n=title:match('^(.-)%s*第%s*(%d+)%s*[集话話]')
        if not prefix then prefix,n=title:match('^(.-)%s*[Ee][Pp]?%s*(%d+)') end
        if not prefix then prefix,n=title:match('^(.-)%s*#%s*(%d+)') end
        if not prefix then prefix,n=title:match('^(.-)%s*[%-—–~～]%s*(%d+)%s*$') end
        if prefix then anime=strip_year(prefix);episode=tonumber(n) end
    end
    if not anime or anime=='' or not episode then return nil,nil,season end
    return anime,episode,season
end

function M.search_keyword(title)
    title = M.limit_text(title,512):gsub('[%z\1-\8\11\12\14-\31\127]', '')
    title = title:gsub('^%s*%[[^%]]+%]%s*', '')
    title = title:gsub('%.[%w%d]+$', '')
    local anime = M.episode_query(title)
    if anime then return M.limit_text(anime,120) end
    title = title:gsub('%s*%[[^%]]*[0-9]+[pPkK][^%]]*%]%s*$', '')
    title = title:gsub('%s*%[[^%]]*[Bb][Dd][^%]]*%]%s*$', '')
    title = title:gsub('[%s._%-]+$', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return M.limit_text(title,120)
end

local function decode_json(text, parse_json)
    if type(text) ~= 'string' or text == '' then return nil, '服务器响应为空' end
    text = text:gsub('^\239\187\191', '')
    local ok, data = pcall(parse_json, text)
    if not ok or type(data) ~= 'table' then return nil, '服务器返回了无效 JSON' end
    if data.errorCode ~= nil and tonumber(data.errorCode) ~= 0 then
        local message = type(data.errorMessage) == 'string' and data.errorMessage or ''
        return nil, message ~= '' and message or ('接口错误 ' .. tostring(data.errorCode))
    end
    if data.success == false then
        return nil, M.limit_text(data.errorMessage or '接口返回失败',180)
    end
    return data
end

function M.match_result(text, parse_json)
    local data, err = decode_json(text, parse_json)
    if not data then return nil, err end
    if data.isMatched ~= true or type(data.matches) ~= 'table' then return nil, nil end
    local match = data.matches[1]
    if type(match) ~= 'table' or match.episodeId == nil then return nil, nil end
    local id=M.episode_id(match.episodeId)
    if not id then return nil, nil end
    return {episodeId=id,animeId=M.episode_id(match.animeId),
        animeTitle=M.limit_text(match.animeTitle,120),episodeTitle=M.limit_text(match.episodeTitle,80)}
end

local PLATFORM_NAMES={tencent='腾讯视频',qq='腾讯视频',iqiyi='爱奇艺',qiyi='爱奇艺',
    bilibili='哔哩哔哩',youku='优酷',migu='咪咕',dandan='弹弹play',
    animeko='Animeko',leshi='乐视',imgo='芒果TV'}
local function platform_name(value)
    value=M.limit_text(value,32)
    return PLATFORM_NAMES[value:lower()] or value
end
local function image_url(value)
    if type(value)~='string' or #value>2048 or value:find('[%z\1-\31]')
        or not value:match('^https?://[^/%?#]+') then return nil end
    return value
end
function M.show_info(value,clean)
    local title=M.limit_text(value,120,clean)
    local year=tonumber(title:match('[（(](%d%d%d%d)[)）]'))
    local season=M.season_number(title)
    local part=tonumber(title:match('[Pp]art%s*(%d+)') or title:match('第%s*(%d+)%s*部分'))
    local kind=(title:find('电影',1,true) or title:find('剧场版',1,true)) and '电影' or '剧集'
    local label=title:gsub('%s*[Ff][Rr][Oo][Mm]%s+.*$',''):gsub('【.-】','')
    label=label:gsub('%s+$','')
    local series=label:gsub('%s*[（(]%d%d%d%d[)）]','')
    series=series:gsub('%s*第%s*%d+%s*季',''):gsub('%s*[Pp]art%s*%d+','')
    for _,word in ipairs(CHINESE_SEASONS) do series=series:gsub('第'..word..'季','') end
    series=series:gsub('%s*第%s*%d+%s*部分',''):gsub('%s+$','')
    return {label=label,series=series,season=season,part=part,year=year,kind=kind}
end

function M.search_results(text, keyword, parse_json, clean)
    local data, err = decode_json(text, parse_json)
    if not data then return nil, err end
    if type(data.animes) ~= 'table' then return {}, nil end
    local out={}
    for _, anime in ipairs(data.animes) do
        if type(anime)=='table' then
            local id=M.episode_id(anime.animeId or anime.bangumiId)
            if id then
                local info=M.show_info(anime.animeTitle or keyword,clean)
                local content_type=M.limit_text(anime.typeDescription or anime.type or '',32,clean)
                if content_type~='' then info.kind=content_type end
                if not info.year then info.year=tonumber(tostring(anime.startDate or ''):match('^(%d%d%d%d)')) end
                local platforms,platform_keys={},{}
                local function add_platform(entry,episode_count)
                    local platform_id=M.episode_id(entry.animeId)
                    if not platform_id then return end
                    local source=M.limit_text(entry.source or '',32)
                    local count=tonumber(episode_count) or 0
                    if platform_keys[source] then
                        local current=platforms[platform_keys[source]]
                        if count>current.episode_count then
                            current.id=platform_id;current.episode_count=count
                        end
                        return
                    end
                    platforms[#platforms+1]={id=platform_id,key=source,name=platform_name(source),
                        episode_count=count,
                        image_url=image_url(entry.imageUrl)}
                    platform_keys[source]=#platforms
                end
                add_platform(anime,anime.episodeCount)
                for _,child in ipairs(type(anime.mergedChildren)=='table' and anime.mergedChildren or {}) do
                    if type(child)=='table' then add_platform(child,child.episodes) end
                end
                out[#out+1]={id=id,label=info.label,series=info.series,season=info.season,
                    part=info.part,year=info.year,kind=info.kind,
                    episode_count=tonumber(anime.episodeCount) or 0,
                    image_url=image_url(anime.imageUrl),platforms=platforms}
            end
        end
    end
    return out, nil
end

local PLATFORM_PREFIXES={tencent='qq',iqiyi='qiyi',bilibili='bilibili',migu='migu'}
local function is_extra_episode(title)
    local lower=title:lower()
    return title:find('预告',1,true) or title:find('花絮',1,true)
        or title:find('特典',1,true) or title:find('插入歌',1,true)
        or lower:find('opening',1,true) or lower:find('ending',1,true)
        or lower:find('ncop',1,true) or lower:find('nced',1,true)
        or lower:match('%f[%a]pv%f[%A]')
end

function M.bangumi_episodes(text, parse_json, clean, platform_key)
    local data, err = decode_json(text, parse_json)
    if not data then return nil, err end
    local bangumi=data.bangumi
    if type(bangumi)~='table' or type(bangumi.episodes)~='table' then return {},nil end
    local out={}
    local selected_prefix=PLATFORM_PREFIXES[platform_key] or tostring(platform_key or ''):lower()
    for _,episode in ipairs(bangumi.episodes) do
        if type(episode)=='table' then
            local id=M.episode_id(episode.episodeId)
            if id then
                local number=M.limit_text(episode.episodeNumber,12)
                local title=M.limit_text(episode.episodeTitle,120,clean)
                local prefix=(title:match('^【(.-)】') or ''):lower()
                local global=tonumber(title:match('第%s*(%d+)%s*[集话話]'))
                out[#out+1]={id=id,number=number,raw_number=tonumber(number),
                    global_number=global,prefix=prefix,extra=not not is_extra_episode(title),
                    label=title~='' and title or ('第'..number..'集')}
            end
        end
        if #out>=500 then break end
    end
    if selected_prefix~='' then
        local matching=0
        for _,item in ipairs(out) do
            if item.prefix:find(selected_prefix,1,true) then matching=matching+1 end
        end
        if matching>0 then
            local selected={}
            for _,item in ipairs(out) do
                if item.prefix=='' or item.prefix:find(selected_prefix,1,true) then
                    selected[#selected+1]=item
                end
            end
            out=selected
        end
    end
    local minimum,offset_counts,total=nil,{},0
    for _,item in ipairs(out) do
        if not item.extra and item.global_number then
            minimum=math.min(minimum or item.global_number,item.global_number)
            if item.raw_number then
                local offset=item.global_number-item.raw_number
                offset_counts[offset]=(offset_counts[offset] or 0)+1
                total=total+1
            end
        end
    end
    local best=0
    for _,count in pairs(offset_counts) do best=math.max(best,count) end
    local raw_numbers_align=total>0 and best/total>=.8
    for _,item in ipairs(out) do
        local number=item.raw_number
        if not item.extra and item.global_number and minimum and not raw_numbers_align then
            number=item.global_number-minimum+1
        end
        item.number_value=number
        item.group=item.extra and '预告与其他' or '正片'
    end
    return out,nil
end

function M.match_verified(match,media_name,episodes)
    if type(match)~='table' or type(episodes)~='table' then return false end
    local anime,episode,season=M.episode_query(media_name)
    if not anime or not episode then return false end
    local info=M.show_info(match.animeTitle)
    if season and info.season~=season and not (season==1 and info.season==nil) then return false end
    local year=tonumber(tostring(media_name):match('[（(](%d%d%d%d)[)）]'))
    if year and info.year and info.year~=year then return false end
    local wanted=anime:lower():gsub('[%s%p]','')
    local actual=info.series:lower():gsub('[%s%p]','')
    if wanted=='' or actual~=wanted then return false end
    for _,item in ipairs(episodes) do
        if item.id==match.episodeId and not item.extra and item.number_value==episode then return true end
    end
    return false
end

local function identity(value)
    return tostring(value or ''):lower():gsub('[%s%p]','')
end

function M.auto_candidates(shows,media_name)
    local anime,episode,season=M.episode_query(media_name)
    if not anime or not episode then return {} end
    local year=tonumber(tostring(media_name):match('[（(](%d%d%d%d)[)）]'))
    local wanted=identity(anime)
    local out={}
    for _,show in ipairs(shows or {}) do
        if identity(show.series)==wanted and wanted~=''
            and (not year or not show.year or show.year==year)
            and (not season or show.season==season or season==1 and show.season==nil)
            and show.kind~='电影' then
            for _,platform in ipairs(show.platforms or {}) do
                if platform.id and #out<20 then
                    out[#out+1]={id=platform.id,key=platform.key,label=show.label}
                end
            end
        end
    end
    return out
end

function M.auto_episode(episodes,media_name)
    local _,wanted=M.episode_query(media_name)
    if not wanted then return nil end
    local selected
    for _,item in ipairs(episodes or {}) do
        if not item.extra and item.number_value==wanted then
            if selected then return nil end
            selected=item
        end
    end
    return selected
end

function M.parse_comments(text, parse_json, core)
    if type(text) ~= 'string' or text == '' then return nil, '服务器响应为空' end
    text = text:gsub('^\239\187\191', '')
    local data, err = decode_json(text, parse_json)
    if not data then return nil, err end
    if type(data.comments) ~= 'table' then return nil, '响应中没有弹幕列表' end
    local out, scanned = {}, 0
    for _, comment in ipairs(data.comments) do
        scanned = scanned + 1
        if type(comment) == 'table' then
            local fields = {}
            for field in (tostring(comment.p or '') .. ','):gmatch('(.-),') do fields[#fields + 1] = field end
            local time, mode, color = tonumber(fields[1]), tonumber(fields[2]), tonumber(fields[3])
            if core.finite(time) and time >= 0 and time < 604800
                and core.finite(mode) and mode>=1 and mode<=9 and mode==math.floor(mode) then
                local value = core.clean(tostring(comment.m or '')):gsub('[\r\n]+', ' ')
                if value ~= '' then
                    out[#out + 1] = {t = time, mode = mode, text = value,
                        color = core.finite(color) and core.clamp(math.floor(color), 0, 16777215) or 16777215}
                end
            end
        end
        if #out >= 50000 or scanned >= 50000 then break end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

return M

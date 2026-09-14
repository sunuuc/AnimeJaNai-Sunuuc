-- A stock updater would overwrite the Chinese frontend and native counter.
-- Application updates are explicit; component management remains available.
local mp = require 'mp'
local url = 'https://github.com/sunuuc/AnimeJaNai-zh-CN/releases'
local function open_releases()
    mp.command_native_async({name='subprocess', playback_only=false,
        args={'rundll32.exe', 'url.dll,FileProtocolHandler', url}},
        function(success, result)
            if not success or not result or result.status ~= 0 then
                mp.osd_message('请打开 sunuuc/AnimeJaNai-zh-CN 的 GitHub 发布页检查更新', 8)
            end
        end)
end
mp.register_script_message("animejanai-update", open_releases)
mp.add_key_binding("Ctrl+u", "animejanai_update", open_releases)

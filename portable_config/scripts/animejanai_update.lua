-- On startup, asks AnimeJaNaiUpdater.exe whether a newer mpv-upscale-2x_animejanai release exists.
-- If so, shows a one-time OSD prompt; Ctrl+U (or the AnimeJaNai > Install Update menu entry, both
-- mapped to the "animejanai-update" script-message) applies it: the updater is launched detached,
-- mpv quits so files unlock, the update is applied in place (user files preserved), and mpv relaunches.

local mp = require 'mp'
local msg = require 'mp.msg'

-- The updater ships at the install root, one level above portable_config (~~/ = config dir).
local exe_name = mp.get_property("platform") == "windows" and "AnimeJaNaiUpdater.exe" or "AnimeJaNaiUpdater"
local updater = mp.command_native({ "expand-path", "~~/../" .. exe_name })
local available_version = nil

-- Inside an AppImage the install tree is a read-only squashfs, so the in-place
-- updater can't apply. AppRun sets ANIMEJANAI_APPIMAGE (APPIMAGE is set by the
-- runtime too); in that case we point the user at the new AppImage instead.
local is_appimage = os.getenv("ANIMEJANAI_APPIMAGE") ~= nil or os.getenv("APPIMAGE") ~= nil
local releases_url = "github.com/the-database/mpv-upscale-2x_animejanai/releases"

local function start_update()
    if not available_version then
        mp.osd_message("AnimeJaNai 已是最新版本。", 3)
        return
    end
    if is_appimage then
        mp.osd_message("AnimeJaNai " .. available_version ..
            " 已发布。\n请下载新的 AppImage：\n" .. releases_url, 12)
        return
    end
    mp.osd_message("正在安装 AnimeJaNai " .. available_version .. "，mpv 将自动关闭并重新打开……", 5)
    -- Detached so it outlives mpv; the updater waits for mpv to exit, applies, then relaunches mpv.
    mp.command_native({
        name = "subprocess",
        args = { updater, "--apply" },
        detach = true,
        playback_only = false,
    })
    mp.add_timeout(1.0, function() mp.command("quit") end)
end

mp.register_script_message("animejanai-update", start_update)

local function on_check(success, result)
    if not success or not result or result.status ~= 0 then
        return -- offline / updater missing / error: stay quiet
    end
    local ver = (result.stdout or ""):match("UPDATE_AVAILABLE%s+(%S+)")
    if ver then
        available_version = ver
        msg.info("有可用更新: " .. ver)
        local how = is_appimage and "按 Ctrl+U 查看下载地址。"
                                 or "按 Ctrl+U 安装更新。"
        mp.osd_message("AnimeJaNai 有新版本 " .. ver .. " - " .. how, 8)
    else
        msg.verbose("AnimeJaNai 已是最新版本。")
    end
end

mp.command_native_async({
    name = "subprocess",
    args = { updater, "--check" },
    capture_stdout = true,
    playback_only = false,
}, on_check)

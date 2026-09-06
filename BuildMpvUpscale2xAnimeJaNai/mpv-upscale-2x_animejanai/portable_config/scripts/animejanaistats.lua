local open = io.open

local showingMessage = false
local MAX_DURATION = 2147483

function show_animejanai_stats()
    if showingMessage then
        mp.osd_message("")
        showingMessage = false
    else
        local message = ""

        if mp.get_property("vf") == "" then
            message = "超分已关闭"
        else
            local data_file_path = (mp.command_native({'expand-path', "~~/../animejanai/currentanimejanai.log"}))
            message = read_file(data_file_path)

            if message == "" then
                message = "超分过程中发生错误；按 ~ 键在控制台查看错误信息"
            end
        end

        mp.osd_message(message, MAX_DURATION)
        showingMessage = true
    end
end

function read_file(path)
    local file = open(path, "r")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end

mp.add_key_binding("Ctrl+j", "show_animejanai_stats", show_animejanai_stats)

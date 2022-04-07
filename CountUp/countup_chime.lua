obs           = obslua
-- カウンタ（テキスト）
activated   = false
source_name = ""
cur_seconds = 0
add_seconds = 1 -- 1秒につき，add_seconds[sec]タイマーが進行
last_text   = ""
stop_text   = ""

-- チャイム
local selected_source
chime_time1 = 0 -- 1st chime
chime_time2 = 0 -- 2nd chime
chime_time3 = 0 -- 3rd chime
chime_log   = 0 -- chime flag
chime_max   = 0 -- chimeの最大時間

local ffi = require("ffi")
local winmm = ffi.load("Winmm")
CHIME_FILEPATH = script_path() .. "chime.wav" -- wav path

ffi.cdef[[
    bool PlaySound(const char *pszSound, void *hmod, uint32_t fdwSound);
]]
function playsound(filepath)
    winmm.PlaySound(filepath, nil, 0x00020003)
end

-- Bar（色ソース）
now_width_size    = 0 -- 現在のBarの幅
color_width_size  = 1920 -- 画面の幅
color_height_size = 1080 -- 画面の高さ

-- color
color0 = 0xffffffff -- white
color1 = 0xff00ff00 -- green
color2 = 0xff00ffff -- yellow
color3 = 0xff0000ff -- red
color4 = 0xff888888 -- grey
color  = color1     -- init color

hotkey_id  = obs.OBS_INVALID_HOTKEY_ID

-- Function to set the time text
function set_time_text()
    local seconds       = math.floor(cur_seconds % 60)
    local total_minutes = math.floor(cur_seconds / 60)
    local minutes       = math.floor(total_minutes % 60)
    local hours         = math.floor(total_minutes / 60)
    local text          = string.format("%02d:%02d", minutes, seconds)

    if cur_seconds < 0 then
        text = stop_text
    end
 
    if text ~= last_text then
        local source = obs.obs_get_source_by_name(source_name)
        if source ~= nil then
            local settings = obs.obs_data_create()
            obs.obs_data_set_string(settings, "text", text)
            obs.obs_source_update(source, settings)
            obs.obs_data_release(settings)
            obs.obs_source_release(source)
        end
    end

    -- チャイム再生
    if minutes == 0 and minutes ~= chime_log then -- Init Color
        chime_log = minutes
        color = color1 -- 色をcolor2に変更
    elseif minutes == chime_time1 and minutes ~= chime_log then -- 1st chime
        playsound(CHIME_FILEPATH)
        chime_log = minutes
        color = color2 -- 色をcolor2に変更
    elseif minutes == chime_time2 and minutes ~= chime_log then -- 2nd chime
        playsound(CHIME_FILEPATH)
        chime_log = minutes
        color = color3 -- 色をcolor3に変更
    elseif minutes == chime_time3 and minutes ~= chime_log then --3rd chime
        playsound(CHIME_FILEPATH)
        chime_log = minutes
        color = color4 -- 色をcolor4に変更
    elseif minutes >= chime_max then -- 3rd chime 以降常にcolor4
        color = color4
    end

    last_text = text
end

function timer_callback()
    cur_seconds = cur_seconds + add_seconds
    if cur_seconds < 0 then
        obs.remove_current_callback()
        cur_seconds = 0
    end

    set_time_text()
    move_source_on_scene()
end
 
function activate(activating)
    if activated == activating then
        return
    end

    activated = activating

    if activating then
        cur_seconds = 0
        chime_set()
 
        set_time_text()
        obs.timer_add(timer_callback, 1000)
    else
        obs.timer_remove(timer_callback)
    end
end

-- Called when a source is activated/deactivated
function activate_signal(cd, activating)
    local source = obs.calldata_source(cd, "source")
    if source ~= nil then
        local name = obs.obs_source_get_name(source)
        if (name == source_name) then
            activate(activating)
        end
    end
end

function source_activated(cd)
    activate_signal(cd, true)
end

function source_deactivated(cd)
    activate_signal(cd, false)
end

function reset(pressed)
    if not pressed then
        return
    end

    chime_set()
    reset_source_on_scene()

    activate(false)
    local source = obs.obs_get_source_by_name(source_name)
    if source ~= nil then
        local active = obs.obs_source_active(source)
        obs.obs_source_release(source)
        activate(active)
    end
end

function chime_button_clicked(props, p)
    playsound(CHIME_FILEPATH)
end
 
function reset_button_clicked(props, p)
    -- chime_set()
    -- reset_source_on_scene()
    reset(true)
    return false
end
 
function chime_set()
    chime_log = 0   -- chime flag
    chime_max = 0   -- chimeの最大時間
    -- 最大時間を決定
    if chime_time1 > chime_max then
        chime_max = chime_time1
    end
    if chime_time2 > chime_max then
        chime_max = chime_time2
    end
    if chime_time3 >= chime_max then
        chime_max = chime_time3
    end

    if chime_time1 > chime_time2 then
        chime_time2 = chime_time1
    end
    if chime_time2 > chime_time3 then
        chime_time3 = chime_time2
    end
end

----------------------------------------------------------

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_int(props, "duration1", "1st chime (minutes)", 1, 59, 1)
    obs.obs_properties_add_int(props, "duration2", "2nd chime (minutes)", 1, 59, 1)
    obs.obs_properties_add_int(props, "duration3", "3rd chime (minutes)", 1, 59, 1)

    local p = obs.obs_properties_add_list(props, "source", "Text Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            source_id = obs.obs_source_get_unversioned_id(source)
            if source_id == "text_gdiplus" or source_id == "text_ft2_source" then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(p, name, name)
            end
        end
    end
    obs.source_list_release(sources)

    local p = obs.obs_properties_add_list(props, "selected_source", "Progress Bar", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            source_id = obs.obs_source_get_unversioned_id(source)
            if source_id == "color_source" then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(p, name, name)
            end
        end
    end
    obs.source_list_release(sources)

    local AUDIO_FILTER = "WAV files (*.wav)"
    obs.obs_properties_add_path(props, "chime", "Start sound",
        obs.OBS_PATH_FILE,
        AUDIO_FILTER,
        nil
    )

    -- obs.obs_properties_add_text(props, "stop_text", "Start Text", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(props, "chime_button", "Chime Start", chime_button_clicked)
    obs.obs_properties_add_button(props, "reset_button", "Reset Timer", reset_button_clicked)

    return props
end

-- A function named script_description returns the description shown to
-- the user
function script_description()
    return "CountUp Timer with Chime.\nMade by Bear・Saito"
end

function add_source()
    current_scene = obs.obs_frontend_get_current_scene()
    scene = obs.obs_scene_from_source(current_scene)
    settings = obs.obs_data_create()

    hotkey_data = nil
    obs.obs_data_set_int(settings, "width", 0)
    obs.obs_data_set_int(settings, "height", color_height_size)
    obs.obs_data_set_int(settings, "color", color1)
    source = obs.obs_source_create("color_source", "background", settings, hotkey_data)
    obs.obs_scene_add(scene, source)

    obs.obs_scene_release(scene)
    obs.obs_data_release(settings)
    obs.obs_source_release(source)
end

function change_source_on_scene()
    current_scene = obs.obs_frontend_get_current_scene()
    scene = obs.obs_scene_from_source(current_scene)
    scene_item = obs.obs_scene_find_source(scene, selected_source)
    if scene_item then
        local source = obs.obs_get_source_by_name(selected_source)
        if source ~= nil then
            local settings = obs.obs_data_create()
            hotkey_data = nil
            obs.obs_data_set_int(settings, "width",now_width_size)
            obs.obs_data_set_int(settings, "height",color_height_size)
            obs.obs_data_set_int(settings, "color", color)
            obs.obs_source_update(source, settings)
            obs.obs_data_release(settings)
            obs.obs_source_release(source)
        end
    end
    obs.obs_scene_release(scene)
end

function move_source_on_scene()
    dx, dy = math.floor(color_width_size/chime_max/60*cur_seconds), 0
    -- now_width_size = now_width_size + dx
    now_width_size = dx
    if now_width_size > color_width_size then
        now_width_size = color_width_size
    end
    change_source_on_scene()
end

function reset_source_on_scene()
        now_width_size = 0
        color = color1
        change_source_on_scene()
end

-- A function named script_update will be called when settings are changed
function script_update(settings)
    activate(false)

    chime_time1 = obs.obs_data_get_int(settings, "duration1")
    chime_time2 = obs.obs_data_get_int(settings, "duration2")
    chime_time3 = obs.obs_data_get_int(settings, "duration3")

    CHIME_FILEPATH = obs.obs_data_get_string(settings, "chime")

    source_name = obs.obs_data_get_string(settings, "source")
    selected_source = obs.obs_data_get_string(settings,"selected_source")

    stop_text = obs.obs_data_get_string(settings, "stop_text")

    reset(true)
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "duration1", 1)
    obs.obs_data_set_default_int(settings, "duration2", 1)
    obs.obs_data_set_default_int(settings, "duration3", 1)
    obs.obs_data_set_default_string(settings, "chime", CHIME_FILEPATH)
    obs.obs_data_set_default_string(settings, "stop_text", "Starting soon (tm)")
end

-- A function named script_save will be called when the script is saved
--
-- NOTE: This function is usually used for saving extra data (such as in this
-- case, a hotkey's save data).  Settings set via the properties are saved
-- automatically.
function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, "reset_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

-- a function named script_load will be called on startup
function script_load(settings)
    -- Connect hotkey and activation/deactivation signal callbacks
    --
    -- NOTE: These particular script callbacks do not necessarily have to
    -- be disconnected, as callbacks will automatically destroy themselves
    -- if the script is unloaded.  So there's no real need to manually
    -- disconnect callbacks that are intended to last until the script is
    -- unloaded.
    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_connect(sh, "source_activate", source_activated)
    obs.signal_handler_connect(sh, "source_deactivate", source_deactivated)

    obs.obs_frontend_add_event_callback(obs_frontend_callback)

    hotkey_id = obs.obs_hotkey_register_frontend("reset_timer_thingy", "Reset Timer", reset)
    local hotkey_save_array = obs.obs_data_get_array(settings, "reset_hotkey")
    obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end
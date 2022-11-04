-- groupwatch_sync.lua
--
-- Because I want to pause and take beautiful screenshots.
--
-- This script speeds up or slows down videos to
-- get back in sync with a group watch.
-- Define a start time with Shift+K and sync with K.
-- Alternatively, define a start timestamp with Ctrl+Shift+K.

local options = {
    -- Prepend group position to osd messages
    show_group_pos = true,

    -- Slow down playback instead of pausing when ahead
    allow_slowdowns = false,

    -- Playback speed modifier when syncing, applied once every second until cap is reached
    speed_increase = 0.2,
    speed_decrease = 0.2,

    -- Playback speed cap
    min_speed = 0.25,
    max_speed = 2.5,

    -- Reset playback speed to 1x when subtitles are displayed
    subs_reset_speed = false,

    -- Use evafast for speedup syncing if available
    use_evafast = true
}

local start = nil
local syncing = false
local pausing = false
local last_correction = 0
local last_pos = nil
local expect_jump = false
local reset = false
local duration = 0
local pause_pos = 0
local pause_timer = nil
local user_time = nil
local edit_time = "hour"
local sync_timer = nil
local last_schedule = ""
local evafast_available = false

mp.options = require "mp.options"
mp.assdraw = require "mp.assdraw"
mp.options.read_options(options, "groupwatch_sync")

local function group_pos(pos)
    if not options.show_group_pos or not start then
        return ""
    end
    if pos == nil then
        pos = mp.get_time() - start
    elseif pos < 0 then
        return "@xx:xx:xx"
    end
    if duration ~= 0 then
        pos = math.min(pos, duration)
    end
    return string.format("@%.2d:%.2d:%.2d", math.floor(pos/(60*60)), math.floor(pos/60%60), math.floor(pos%60))
end

local function group_pos_update()
    if not pausing then
        if pause_timer ~= nil then
            pause_timer:kill()
            pause_timer = nil
        end
        return
    end
    pause_pos = pause_pos + 1
    -- TODO: support groupwatch_start(n, true, true) in the middle of a pause sync
    mp.osd_message("[groupwatch_sync"..group_pos(pause_pos).."] syncing... (pause)", mp.get_property_number("time-pos") - pause_pos + 1)
end

local function sync_cancel(quiet, observed)
    if pausing and not observed then
        mp.set_property_bool("pause", false)
    end
    if not syncing then
        return false
    end
    syncing = false
    pausing = false
    if evafast_available then
        mp.commandv("script-message-to", "evafast", "speedup-target", 0)
    else
        mp.set_property("speed", 1)
    end
    if not quiet then
        mp.osd_message("[groupwatch_sync"..group_pos(nil).."] sync canceled")
    end
end

local function groupwatch_reset()
    start = nil
    user_time = nil
    if sync_timer ~= nil then
        sync_timer:kill()
        sync_timer = nil
    end
    sync_cancel()
end

local function groupwatch_start(from, quiet, ignore)
    user_time = nil
    last_schedule = ""
    if not ignore then
        if sync_timer ~= nil then
            sync_timer:kill()
            sync_timer = nil
        end
        from = from or 0
        mp.set_property_bool("pause", false)
        if options.show_group_pos then
            duration = mp.get_property_number("duration", 0)
        end
        sync_cancel()
    end
    start = mp.get_time() - from
    if not quiet then
        mp.osd_message("[groupwatch_sync"..group_pos(from).."] start time set")
    end
end

local function groupwatch_start_here()
    user_time = nil
    last_schedule = ""
    if sync_timer ~= nil then
        sync_timer:kill()
        sync_timer = nil
    end
    groupwatch_start(mp.get_property_number("time-pos"))
end

local function groupwatch_jump()
    if not start then
        mp.osd_message("[groupwatch_sync"..group_pos(-1).."] " .. (last_schedule ~= "" and ("waiting for group - start scheduled for " .. last_schedule) or "no start time set"))
        sync_cancel(true)
        return
    end
    local groupwatch_pos = mp.get_time() - start
    if pausing then
        sync_cancel(true)
    elseif evafast_available then
        mp.commandv("script-message-to", "evafast", "speedup-target", 0)
    end
    mp.set_property("time-pos", groupwatch_pos)
    mp.osd_message("[groupwatch_sync"..group_pos(groupwatch_pos).."] synced")
    if not pausing then
        mp.set_property_bool("pause", false)
    end
end

local function groupwatch_unpause()
    if not start then return sync_cancel(true) end
    local local_pos = mp.get_property_number("time-pos")
    local groupwatch_pos = mp.get_time() - start
    if pausing and math.abs(groupwatch_pos - local_pos) < 0.4 then
        sync_cancel(true)
        mp.osd_message("[groupwatch_sync"..group_pos(groupwatch_pos).."] synced")
    end
end

local function groupwatch_observe(name, local_pos)
    if local_pos == nil then return end
    if not syncing then
        return false
    end
    if pausing then
        if last_pos ~= local_pos then
            return sync_cancel(false, true)
        else
            return
        end
    end
    local groupwatch_pos = mp.get_time() - start
    if math.abs(groupwatch_pos - local_pos) < 0.2 then
        if name == "manual" then
            mp.set_property_bool("pause", false)
        end
        sync_cancel(true)
        return mp.osd_message("[groupwatch_sync"..group_pos(groupwatch_pos).."] synced")
    end
    local speed_correction = options.speed_increase
    if local_pos >= groupwatch_pos + 0.1 then
        if not options.allow_slowdowns then
            if expect_jump then
                return sync_cancel()
            end
            mp.osd_message("[groupwatch_sync"..group_pos(groupwatch_pos).."] syncing... (pause)", local_pos - groupwatch_pos + 1)
            mp.set_property_bool("pause", true)
            pausing = true
            last_pos = local_pos
            if options.show_group_pos then
                if pause_timer ~= nil then pause_timer:kill() end
                pause_pos = groupwatch_pos
                pause_timer = mp.add_periodic_timer(1, group_pos_update)
            end
            return mp.add_timeout(local_pos - groupwatch_pos, groupwatch_unpause)
        end
        speed_correction = -options.speed_decrease
    end
    if name == "manual" then
        mp.set_property_bool("pause", false)
    end
    if evafast_available then
        mp.osd_message("[groupwatch_sync"..group_pos(groupwatch_pos).."] syncing... (speed correction)")
        expect_jump = true
        return mp.commandv("script-message-to", "evafast", "speedup-target", groupwatch_pos)
    end
    if options.subs_reset_speed then
        if mp.get_property("sub-start") ~= nil then
            if not reset then
                mp.set_property("speed", 1)
            end
            reset = true
        else
            reset = false
        end
    end
    new_correction = math.ceil(local_pos)
    if new_correction ~= last_correction and not reset then
        last_correction = new_correction
        local new_speed = math.max(options.min_speed, math.min(mp.get_property_number("speed") + speed_correction, options.max_speed))
        mp.set_property("speed", new_speed)
    end
    mp.osd_message("[groupwatch_sync"..group_pos(groupwatch_pos).."] syncing... (speed correction)")
    expect_jump = true
end

local function groupwatch_sync()
    expect_jump = false
    if syncing then
        return sync_cancel()
    elseif not start then
        return mp.osd_message("[groupwatch_sync"..group_pos(-1).."] " .. (last_schedule ~= "" and ("waiting for group - start scheduled for " .. last_schedule) or "no start time set"))
    end
    syncing = true
    groupwatch_observe("manual", mp.get_property_number("time-pos"))
end

local function clamp_time_with_range(edit_time, min, max)
    if user_time[edit_time] > max then
         user_time[edit_time] = min 
        return 1
    elseif user_time[edit_time] < min then
         user_time[edit_time] = max 
        return -1
    end
    return 0
end

local function increment_time(edit_time, increment)
    user_time[edit_time] = user_time[edit_time] + increment
    clamp_time(edit_time)
end

function clamp_time(edit_time)
    if edit_time == "sec" then
        increment = clamp_time_with_range(edit_time, 0, 59)
        increment_time("min", increment)
    elseif edit_time == "min" then
        increment = clamp_time_with_range(edit_time, 0, 59)
        increment_time("hour", increment)
    elseif edit_time == "hour" then
        increment = clamp_time_with_range(edit_time, 0, 23)
        if not(
            (user_time["today"] == 1 and increment > 0) or
            (user_time["today"] == -1 and increment < 0)) then
            increment_time("today", increment)
        end
    elseif edit_time == "today" then
        clamp_time_with_range(edit_time, -1, 1)
    end
end

local function groupwatch_clear_time()
    edit_time = "hour"
    mp.set_osd_ass(1280, 720, "")
    mp.remove_key_binding("groupwatch_key_up")
    mp.remove_key_binding("groupwatch_key_down")
    mp.remove_key_binding("groupwatch_key_left")
    mp.remove_key_binding("groupwatch_key_right")
    mp.remove_key_binding("groupwatch_key_esc")
    mp.remove_key_binding("groupwatch_key_enter")
    mp.remove_key_binding("groupwatch_paste")
    mp.remove_key_binding("groupwatch_paste2")
end

local function groupwatch_key_up()
    if user_time == nil then return groupwatch_clear_time() end
    increment_time(edit_time, 1)
    groupwatch_set_time()
end

local function groupwatch_key_down()
    if user_time == nil then return groupwatch_clear_time() end
    increment_time(edit_time, -1)
    groupwatch_set_time()
end

local function groupwatch_key_left()
    if user_time == nil then return groupwatch_clear_time() end
    if edit_time == "hour" then
        edit_time = "today"
    elseif edit_time == "min" then
        edit_time = "hour"
    elseif edit_time == "sec" then
        edit_time = "min"
    else
        edit_time = "sec"
    end
    groupwatch_set_time()
end

local function groupwatch_key_right()
    if user_time == nil then return groupwatch_clear_time() end
    if edit_time == "hour" then
        edit_time = "min"
    elseif edit_time == "min" then
        edit_time = "sec"
    elseif edit_time == "sec" then
        edit_time = "today"
    else
        edit_time = "hour"
    end
    groupwatch_set_time()
end

local function groupwatch_key_esc()
    user_time = nil
    groupwatch_clear_time()
end

local function groupwatch_time_sync()
    if sync_timer ~= nil then
        sync_timer:kill()
        sync_timer = nil
    end
    last_schedule = ""
    mp.set_property_bool("pause", false)
    if options.show_group_pos then
        duration = mp.get_property_number("duration", 0)
    end
    sync_cancel()
    start = mp.get_time()
    mp.osd_message("[groupwatch_sync"..group_pos(0).."] start time set")
end

local function groupwatch_key_enter()
    if user_time == nil then return groupwatch_clear_time() end
    if sync_timer ~= nil then
        sync_timer:kill()
        sync_timer = nil
    end
    local current_time = os.time()
    local desired_time = os.time({day=user_time.day, month=user_time.month, year=user_time.year, hour=user_time.hour, min=user_time.min, sec=user_time.sec})
    desired_time = desired_time + (60 * 60 * 24 * user_time.today)

    if current_time > desired_time then
        groupwatch_reset()
        last_schedule = ""
        start = mp.get_time() + desired_time - current_time
        mp.osd_message("[groupwatch_sync"..group_pos(current_time - desired_time).."] start time set")
    else
        last_schedule = string.format("%.2d:%.2d:%.2d %s", user_time.hour, user_time.min, user_time.sec, user_time.today == -1 and "yesterday" or (user_time.today == 0 and "today" or "tomorrow"))
        groupwatch_reset()
        sync_timer = mp.add_timeout(desired_time - current_time, groupwatch_time_sync)
        mp.osd_message("[groupwatch_sync"..group_pos(-1).."] start scheduled for " .. last_schedule)
    end
    groupwatch_clear_time()
end

local function groupwatch_paste()
    groupwatch_clear_time()
    -- TODO: use mpv-user-input if available
    mp.commandv("script-message-to", "console", "type", "script-message-to " .. mp.get_script_name() .. " start-time ")
end

function groupwatch_set_time()
    if user_time == nil then
        user_time = os.date("*t")
        user_time["today"] = 0
        edit_time = "hour"
    end
    local ass = mp.assdraw.ass_new()
    ass:new_event()
    ass:append("{\\an7\\bord3.8\\shad0\\1a&00&\\1c&FFFFFF&\\fs36}")
    ass:pos(51, 29)
    ass:append(string.format("set start @ local time %s%.2d{\\1c&FFFFFF&}:%s%.2d{\\1c&FFFFFF&}:%s%.2d{\\1c&FFFFFF&} (%s%s{\\1c&FFFFFF&})%s", edit_time == "hour" and "{\\1c&H008AFF&}" or "", user_time.hour, edit_time == "min" and "{\\1c&H008AFF&}" or "", user_time.min, edit_time == "sec" and "{\\1c&H008AFF&}" or "", user_time.sec, edit_time == "today" and "{\\1c&H008AFF&}" or "", user_time.today == -1 and "yesterday" or (user_time.today == 0 and "today" or "tomorrow"), sync_timer == nil and "" or " - sync scheduled for " .. last_schedule))
    mp.add_forced_key_binding("UP", "groupwatch_key_up", groupwatch_key_up, {repeatable = true})
    mp.add_forced_key_binding("DOWN", "groupwatch_key_down", groupwatch_key_down, {repeatable = true})
    mp.add_forced_key_binding("LEFT", "groupwatch_key_left", groupwatch_key_left, {repeatable = true})
    mp.add_forced_key_binding("RIGHT", "groupwatch_key_right", groupwatch_key_right, {repeatable = true})
    mp.add_forced_key_binding("ESC", "groupwatch_key_esc", groupwatch_key_esc)
    mp.add_forced_key_binding("ENTER", "groupwatch_key_enter", groupwatch_key_enter)
    mp.add_forced_key_binding("CTRL+v", "groupwatch_paste", groupwatch_paste)
    mp.add_forced_key_binding("META+v", "groupwatch_paste2", groupwatch_paste)
    mp.set_osd_ass(1280, 720, ass.text)
end

mp.register_event("start-file", groupwatch_reset)
mp.add_key_binding(nil, "groupwatch_start", groupwatch_start)
mp.add_key_binding("Ctrl+k", "groupwatch_jump", groupwatch_jump)
mp.add_key_binding("K", "groupwatch_start_here", groupwatch_start_here)
mp.add_key_binding("k", "groupwatch_sync", groupwatch_sync)
mp.add_key_binding("Ctrl+K", "groupwatch_set_time", groupwatch_set_time)
mp.observe_property("time-pos", "native", groupwatch_observe)

mp.register_script_message("start-time", function(timestamp, quiet, ignore)
    timestamp = tonumber(timestamp) or 0
    quiet = tonumber(quiet) == 1
    ignore = tonumber(ignore) == 1
    if sync_timer ~= nil then
        sync_timer:kill()
        sync_timer = nil
    end
    user_time = nil
    last_schedule = ""
    if timestamp == 0 then return end
    local from = os.time() - timestamp
    if from < 0 then
        local today = tonumber(os.date("%Y%m%d"))
        local time = os.date("*t", timestamp)
        local time_day = tonumber(string.format("%.2d%.2d%.2d", time.year, time.month, time.day))
        last_schedule = string.format("%.2d:%.2d:%.2d %s", time.hour, time.min, time.sec, today > time_day and "yesterday" or (today == time_day and "today" or "tomorrow"))
        if not ignore then
            groupwatch_reset()
        end
        sync_timer = mp.add_timeout(-from, groupwatch_time_sync)
        if not quiet then
            mp.osd_message("[groupwatch_sync"..group_pos(-1).."] start scheduled for " .. last_schedule)
        end
    else
        groupwatch_start(from, quiet, ignore)
    end
end)

mp.register_script_message("evafast-version", function(version)
    evafast_available = true
end)

if options.use_evafast then
    mp.commandv("script-message-to", "evafast", "get-version", mp.get_script_name())
end

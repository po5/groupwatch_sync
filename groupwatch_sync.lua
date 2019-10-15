-- groupwatch_sync.lua
--
-- Because I want to pause and take beautiful screenshots.
--
-- This script speeds up or slows down videos to
-- get back in sync with a group watch.
-- Define a start time with Shift+K and sync with K.

local options = {
    -- If true, slows down playback instead of pausing when ahead
    allow_slowdowns = false,
	
    -- Playback speed modifier when syncing, applied once every second until cap is reached
    speed_increase = .2,
    speed_decrease = .2,

    -- Playback speed cap
    min_speed = .25,
    max_speed = 2.5,
}

local mp = require 'mp'
local start = nil
local syncing = false
local pausing = false
local last_correction = 0
local expect_jump = false

mp.options = require 'mp.options'
mp.options.read_options(options, "groupwatch_sync")

local function groupwatch_reset()
    if syncing then
        mp.set_property("speed", 1)
        mp.osd_message("[groupwatch_sync] sync canceled")
    end
    start = nil
    syncing = false
    pausing = false
end

local function sync_cancel(observed)
    observed = observed or false
    syncing = false
    if pausing then
        pausing = false
        if not observed then
            if mp.get_property_bool("pause") then
                mp.set_property_bool("pause", false)
            end
        end
    end
    mp.set_property("speed", 1)
    mp.osd_message("[groupwatch_sync] sync canceled")
end

local function groupwatch_start(from)
    from = from or 0
    if mp.get_property_bool("pause") then
        mp.set_property_bool("pause", false)
    end
    mp.set_property("speed", 1)
    start = os.time() - from
    syncing = false
    pausing = false
    mp.osd_message("[groupwatch_sync] start time set")
end

local function groupwatch_start_here()
    groupwatch_start(mp.get_property_number("time-pos"))
end

local function groupwatch_sync()
    expect_jump = false
    if syncing or pausing then
        return sync_cancel()
    end
    if not start then
        return mp.osd_message("[groupwatch_sync] no start time set")
    end
    if mp.get_property_bool("pause") then
        mp.set_property_bool("pause", false)
    end
    syncing = true
end

local function groupwatch_unpause()
    local local_pos = mp.get_property_number("time-pos")
    local groupwatch_pos = os.time() - start
    if not pausing or math.abs(groupwatch_pos - local_pos) > .8 then
        return false
    end
    if mp.get_property_bool("pause") then
        mp.set_property_bool("pause", false)
    end
    mp.osd_message("[groupwatch_sync] synced")
    syncing = false
    pausing = false
end

local function groupwatch_observe()
    if not syncing then
        return false
    end
    if pausing then
        return sync_cancel(true)
    end
    local local_pos = mp.get_property_number("time-pos")
    local groupwatch_pos = os.time() - start
    if math.abs(groupwatch_pos - local_pos) < .8 then
        mp.osd_message("[groupwatch_sync] synced")
        mp.set_property("speed", 1)
        syncing = false
        pausing = false
        return true
    end
    local speed_correction = options.speed_increase
    if local_pos >= groupwatch_pos + .8 then
        if not options.allow_slowdowns then
            if expect_jump then
                return sync_cancel()
            end
            mp.osd_message("[groupwatch_sync] syncing... (pause)", local_pos - groupwatch_pos)
            mp.set_property("speed", 1)
            if not mp.get_property_bool("pause") then
                mp.set_property_bool("pause", true)
            end
            pausing = true
            return mp.add_timeout(local_pos - groupwatch_pos, groupwatch_unpause)
        end
        speed_correction = -options.speed_decrease
    end
    new_correction = math.ceil(local_pos)
    if new_correction ~= last_correction then
        last_correction = new_correction
        local new_speed = math.max(options.min_speed, math.min(mp.get_property_number("speed") + speed_correction, options.max_speed))
        mp.set_property("speed", new_speed)
    end
    mp.osd_message("[groupwatch_sync] syncing... (speed correction)")
    expect_jump = true
end

mp.register_event("start-file", groupwatch_reset)
mp.add_forced_key_binding("Ctrl+k", "groupwatch_start_here", groupwatch_start_here)
mp.add_forced_key_binding("K", "groupwatch_start", groupwatch_start)
mp.add_forced_key_binding("k", "groupwatch_sync", groupwatch_sync)
mp.observe_property("time-pos", "native", groupwatch_observe)

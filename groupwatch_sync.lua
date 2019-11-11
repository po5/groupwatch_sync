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

local mp = require "mp"
local start = nil
local syncing = false
local pausing = false
local last_correction = 0
local expect_jump = false

mp.options = require "mp.options"
mp.options.read_options(options, "groupwatch_sync")

local function sync_cancel(quiet, observed)
    observed = observed or false
    if pausing and not observed then
        mp.set_property_bool("pause", false)
    end
    if not syncing then
        return false
    end
    syncing = false
    pausing = false
    quiet = quiet or false
    mp.set_property("speed", 1)
    if not quiet then
        mp.osd_message("[groupwatch_sync] sync canceled")
    end
end

local function groupwatch_reset()
    start = nil
    sync_cancel()
end

local function groupwatch_start(from)
    from = from or 0
    mp.set_property_bool("pause", false)
    sync_cancel()
    start = os.time() - from
    mp.osd_message("[groupwatch_sync] start time set")
end

local function groupwatch_start_here()
    groupwatch_start(mp.get_property_number("time-pos"))
end

local function groupwatch_sync()
    expect_jump = false
    if syncing then
        return sync_cancel()
    elseif not start then
        return mp.osd_message("[groupwatch_sync] no start time set")
    end
    mp.set_property_bool("pause", false)
    syncing = true
end

local function groupwatch_unpause()
    local local_pos = mp.get_property_number("time-pos")
    local groupwatch_pos = os.time() - start
    if pausing and math.abs(groupwatch_pos - local_pos) < .8 then
        sync_cancel(true)
        mp.osd_message("[groupwatch_sync] synced")
    end
end

local function groupwatch_observe(name, local_pos)
    if not syncing then
        return false
    end
    if pausing then
        return sync_cancel(false, true)
    end
    local groupwatch_pos = os.time() - start
    if math.abs(groupwatch_pos - local_pos) < .8 then
        sync_cancel(true)
        return mp.osd_message("[groupwatch_sync] synced")
    end
    local speed_correction = options.speed_increase
    if local_pos >= groupwatch_pos + .8 then
        if not options.allow_slowdowns then
            if expect_jump then
                return sync_cancel()
            end
            mp.osd_message("[groupwatch_sync] syncing... (pause)", local_pos - groupwatch_pos)
            mp.set_property_bool("pause", true)
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

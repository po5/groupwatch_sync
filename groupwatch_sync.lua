-- groupwatch_sync.lua
--
-- Because I want to pause and take beautiful screenshots.
--
-- This script speeds up or slows down videos to
-- get back in sync with a group watch.
-- Define a start time with Shift+K and sync with K.
local allow_slowdowns = false -- if true, slows down playback instead of pausing when ahead
local speed_increase = .2
local speed_decrease = .2
local min_speed = .25
local max_speed = 2.5


-----------------------
local mp = require 'mp'
local start = nil
local syncing = false
local pausing = false
local last_correction = 0

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
            mp.set_property_bool("pause", false)
        end
    end
    mp.set_property("speed", 1)
    mp.osd_message("[groupwatch_sync] sync canceled")
end

local function groupwatch_start()
    mp.set_property_bool("pause", false)
    mp.set_property("speed", 1)
    start = os.time()
    syncing = false
    pausing = false
    mp.osd_message("[groupwatch_sync] start time set")
end

local function groupwatch_sync()
    if syncing or pausing then
        return sync_cancel()
    end
    if not start then
        return mp.osd_message("[groupwatch_sync] no start time set")
    end
    mp.set_property_bool("pause", false)
    mp.osd_message("[groupwatch_sync] syncing")
    syncing = true
end

local function groupwatch_unpause()
    if not pausing then
        return false
    end
    mp.set_property_bool("pause", false)
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
    local speed_correction = speed_increase
    if local_pos >= groupwatch_pos + 2 then
        if not allow_slowdowns then
            mp.osd_message("[groupwatch_sync] syncing...", local_pos - groupwatch_pos)
            mp.set_property_bool("pause", true)
            pausing = true
            return mp.add_timeout(local_pos - groupwatch_pos, groupwatch_unpause)
        end
        speed_correction = -speed_decrease
    elseif local_pos >= groupwatch_pos then
        mp.osd_message("[groupwatch_sync] synced")
        mp.set_property("speed", 1)
        mp.set_property_bool("pause", false)
        syncing = false
        pausing = false
        return true
    end
    new_correction = math.ceil(local_pos)
    if new_correction ~= last_correction then
        last_correction = new_correction
        local new_speed = math.max(min_speed, math.min(mp.get_property_number("speed") + speed_correction, max_speed))
        mp.set_property("speed", new_speed)
    end
    mp.osd_message("[groupwatch_sync] syncing...")
end

mp.register_event("start-file", groupwatch_reset)
mp.add_forced_key_binding("K", "groupwatch_start", groupwatch_start)
mp.add_forced_key_binding("k", "groupwatch_sync", groupwatch_sync)
mp.observe_property("time-pos", "native", groupwatch_observe)

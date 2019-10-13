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
local groupwatch_start = nil
local syncing = false
local last_correction = 0

-- https://stackoverflow.com/a/24037414 --
local ok,ex = pcall(require,"ex")
if ok then
   pcall(ex.install)
   if ex.sleep and not os.sleep then os.sleep = ex.sleep end
end

if not os.sleep then
   local ok,ffi = pcall(require,"ffi")
   if ok then
      if not os.sleep then
         ffi.cdef[[
            void Sleep(int ms);
            int poll(struct pollfd *fds,unsigned long nfds,int timeout);
         ]]
         if ffi.os == "Windows" then
            os.sleep = function(sec)
               ffi.C.Sleep(sec*1000)
            end
         else
            os.sleep = function(sec)
               ffi.C.poll(nil,0,sec*1000)
            end
         end
      end
   else
      local ok,socket = pcall(require,"socket")
      if not ok then local ok,socket = pcall(require,"luasocket") end
      if ok then
         if not os.sleep then
            os.sleep = function(sec)
               socket.select(nil,nil,sec)
            end
         end
      else
         local ok,alien = pcall(require,"alien")
         if ok then
            if not os.sleep then
               if alien.platform == "windows" then
                  kernel32 = alien.load("kernel32.dll")
                  local slep = kernel32.Sleep
                  slep:types{ret="void",abi="stdcall","uint"}
                  os.sleep = function(sec)
                     slep(sec*1000)
                  end
               else
                  local pol = alien.default.poll
                  pol:types('struct', 'unsigned long', 'int')
                  os.sleep = function(sec)
                     pol(nil,0,sec*1000)
                  end
               end
            end
         elseif package.config:match("^\\") then
            os.sleep = function(sec)
               local timr = os.time()
               repeat until os.time() > timr + sec
            end
         else
            os.sleep = function(sec)
               os.execute("sleep " .. sec)
            end
         end
      end
   end
end
-- // https://stackoverflow.com/a/24037414 // --

local function reset_start()
    if syncing then
        mp.set_property("speed", 1)
        mp.osd_message("[groupwatch_sync] sync canceled")
    end
    groupwatch_start = nil
    syncing = false
end

local function sync_cancel()
    syncing = false
    mp.set_property("speed", 1)
    mp.osd_message("[groupwatch_sync] sync canceled")
end

local function set_start()
    mp.set_property_bool("pause", false)
    mp.set_property("speed", 1)
    groupwatch_start = os.time()
    syncing = false
    mp.osd_message("[groupwatch_sync] start time set")
end

local function groupwatch_sync()
    if not groupwatch_start then
        return mp.osd_message("[groupwatch_sync] no start time set")
    end
    mp.set_property_bool("pause", false)
    mp.osd_message("[groupwatch_sync] syncing")
    syncing = true
end

local function groupwatch_observe()
    if not syncing then
        return false
    end
    local local_pos = mp.get_property_number("time-pos")
    local groupwatch_pos = os.time() - groupwatch_start
    local speed_correction = speed_increase
    if local_pos >= groupwatch_pos + 2 then
        if not allow_slowdowns then
            mp.osd_message("[groupwatch_sync] syncing...", local_pos - groupwatch_pos)
            mp.set_property_bool("pause", true)
            os.sleep(local_pos - groupwatch_pos)
            mp.set_property_bool("pause", false)
            return mp.osd_message("[groupwatch_sync] synced")
        end
        speed_correction = -speed_decrease
    elseif local_pos >= groupwatch_pos then
        mp.osd_message("[groupwatch_sync] synced")
        mp.set_property("speed", 1)
        mp.set_property_bool("pause", false)
        syncing = false
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

mp.register_event("start-file", reset_start)
mp.add_forced_key_binding("K", "groupwatch_start", set_start)
mp.add_forced_key_binding("k", "groupwatch_sync", groupwatch_sync)
mp.add_forced_key_binding("Ctrl+k", "groupwatch_cancel", sync_cancel)
mp.observe_property("time-pos", "native", groupwatch_observe)

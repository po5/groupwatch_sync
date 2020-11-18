# groupwatch_sync
Quickly get back in sync with a group watch by adjusting playback speed.

## Installation
Place groupwatch_sync.lua in your mpv `scripts` folder.

## Usage
Set the group watch position at the start of the viewing.  
If you ever pause, press k to catch up with the group.

Default key bindings:
- K (shift+k) to set group watch position to the beginning of the file
- Ctrl+k to set group watch position to the current position
- k to sync

## Behavior

All syncing behavior is implicit based on the current position relative to the group, and the actions taken by the user during syncing.  
This behavior is what I think is most useful, but may be confusing without first reading this.  
If something doesn't behave as described, please file an issue.

You can prepend group position to osd messages with `show_group_pos=yes`.

Setting the group watch position (`groupwatch_start`, `groupwatch_start_here`):
- Playback is unpaused.

Pressing the `groupwatch_sync` key:
- With no group position set: does nothing
- With group position set: initiate syncing if not already synced, see below

If behind:
- Playback is unpaused and speed is increased every second by `speed_increase` until `max_speed` is reached or group position is reached.
- Pausing, unpausing and seeking *will not* interrupt syncing, unless seeking past the group position.

If ahead:
- `allow_slowdowns=no` (default): Playback is paused until group position reaches playback position.
- `allow_slowdowns=yes`: Playback is unpaused and speed is decreased every second by `speed_decrease` until `min_speed` is reached or group position reaches playback position.
- Unpausing and seeking *will* interrupt syncing.
- Explicitly cancelling the current sync will unpause playback.

In both cases:
- `subs_reset_speed=yes`: Playback speed goes back to 1 when a subtitle is displayed then resumes speed increase/decrease.
- Pressing the `groupwatch_sync` key again will cancel the current sync ("explicitly cancelling" refers to this).

If synced:
- Playback is unpaused

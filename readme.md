# My modifications for the game Total War Warhammer 3

## AF Armageddon v8.0.1

[https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094](https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094)

"Armageddon" modification increases difficulty for the middle and late game.

AI gets various bonuses, but only if it has the different culture group than the player.

### Compatibility

It was created to be used with Radious mod, but it's also compatible with any other mod.
Mod order doesn't matter.
You can add it during a campaign. Don't remove it then.

### Recommendations

I recommend using it with Radious mod.

### About balance

Balance depends on many things: mods, factions, random events, player skills/style.
The only thing which you can expect that this mod gradually increases difficulty at some degree.

## General Logger

https://steamcommunity.com/sharedfiles/filedetails/?id=3665837500

Mod "General Logger" creates '!!af_global_logger.csv' in the game folder.

You can open it as a table with LibreOffice (separator: tab).

Each turn it adds a row to this file.

Columns:

log_item_type (header/data),
turn,
faction,
is_human,
culture,
subculture,
regions_number,
region_number_difference (lost/gained),
imperium_level,
is_vassal,
income,
net_income,
treasury,
treasury_percent,
at_war,
difficulty_level (player),
faction_counter (all faction number),

You can use it to judge about AI doing.

## Turn crash debug logger

Some time you can get a repeated crash during AI turns.

It creates the log file '!af_turn_crash_debug_logger.csv' in the game folder,
with different information to hint about what could cause that crash.

Then you can kill faction or character via "Modding Development Tools: Lua Console"
https://steamcommunity.com/sharedfiles/filedetails/?id=2791799449


```lua
    cm:kill_all_armies_for_faction(faction_key)
    
    cm:kill_character(cqi, true)
```


## License

These mods are under MIT license, you are free to use them as you want.
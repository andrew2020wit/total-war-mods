# My modifications for the game Total War Warhammer 3

## AF Armageddon

[https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094](https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094)

"Armageddon" modification increases difficulty for the middle and late game.

All AI factions get various bonuses, the ones of your own culture too. You can make them
smaller or bigger for each culture, or turn them off for it.

### Compatibility

It was created to be used with Radious mod, but it's also compatible with any other mod.
Mod order doesn't matter.
You can add it during a campaign. Don't remove it then.

The mod is made for single player campaigns. It isn't designed for multiplayer and doesn't
support it.

### Settings

The settings are in [Mod Configuration Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=2927955021)
(MCT). It's optional: without it the mod works with the default settings.
The settings are global: one set of values for all campaigns. Only the bonus multipliers of
the cultures are set for each campaign.

- gold: the percent of the AI income per player region and per turn;
- character experience: the amount and the start turn;
- unit experience: the start turn and the turn interval;
- a log file;
- a bonus multiplier for each culture, 0 to 5: it multiplies the gold and the character
  experience and divides the interval of the unit experience, and 0 turns off all the bonuses
  of the culture.

### About balance

Balance depends on many things: mods, factions, random events, player skills/style.
The only thing which you can expect that this mod gradually increases difficulty at some degree.

### see also

[User guide](./docs/af-armageddon-user-guide.md)

[af_armageddon-agent.md](./af_armageddon-agent.md)

## AF Tweaker

[https://steamcommunity.com/sharedfiles/filedetails/?id=3831853119](https://steamcommunity.com/sharedfiles/filedetails/?id=3831853119)

Campaign mod that automates routine work at the start of your turn: it upgrades buildings, and
builds your favorite buildings and spends skill points by the priorities you set.
A button in the global pool of magic items fuses your unequipped common and uncommon items, or
only the common ones if you choose so.
Each feature can be turned off, and it's compatible with other mods, including Radious.

[User guide](./docs/af-tweaker-user-guide.md)

### see also

[af-tweaker-agent.md](./af-tweaker-agent.md)

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

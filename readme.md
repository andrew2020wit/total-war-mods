# My modifications for the game Total War Warhammer 3

## AF Armageddon v6.2.1

[https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094](https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094)

"Armageddon" modification increases difficulty for the game, especially for the middle and late game.

AI gets bonuses, but only if it has the different culture group than the player.

It also changes balance between factions.

### Unit experience

Each unit each second turn is given one chevron (after 18 turns => 3 gold chevrons from zero). Including garrisons.

add_chevron_each_turn = 2, -- each second turn

### Characters experience

Each character each turn is given experience:

experience = (experience_for_character = 100) * turn_number

(So at 10 turn each character is given 1000 exp)

### Gold bonus

Each AI faction (except the same culture) each turn is given gold bonus.

time_multiplier = settings.time_percent * current_turn / 100
region_multiplier = settings.regions_percent * player_regions_number / 100

gold_bonus = (region_multiplier + time_multiplier) * ai_income;

there:

regions_percent = 4,
time_percent = 2,

For example, turn 20, Player has 10 regions, AI has 10000 income 

bonus = (4 (regions_percent) * 10 (regions) /100 + 20 (turn) * 2 (time_percent) /100) * 10000 (AI income) = 8000

AI not always can utilize all money, so a lot of money not always means a lot of armies.

### Effect bundles

There are effect bundles, which add some additional bonuses.

From 10 to 50 turns bonuses are increasing:

1. local unit_recruitment_points are increased by 2-10 slots (10 additional local recruitment slots from 50 turn)
2. technology_research_points are increased by 50-200 points (200 points from 50 turn)
3. growth - 20-100

### Culture groups

```lua
    
local culture_groups = {
    {
        "wh_main_emp_empire",
        "wh_main_brt_bretonnia",
        "wh_main_dwf_dwarfs",
        "wh3_main_ksl_kislev",
        "wh3_main_cth_cathay",
        "wh2_main_hef_high_elves",
        "wh_dlc05_wef_wood_elves",
    },
    {
        "wh_main_chs_chaos",
        "wh3_main_dae_daemons",
        "wh3_main_kho_khorne",
        "wh3_main_nur_nurgle",
        "wh3_main_sla_slaanesh",
        "wh3_main_tze_tzeentch",
        "wh_dlc08_nor_norsca",
        "wh_dlc03_bst_beastmen",
        "wh3_dlc23_chd_chaos_dwarfs",
        "wh2_main_def_dark_elves",
        "wh2_main_skv_skaven",
    },
    {
        "wh2_dlc09_tmb_tomb_kings",
        "wh_main_vmp_vampire_counts",
        "wh2_dlc11_cst_vampire_coast",
    },
    {
        "wh3_main_ogr_ogre_kingdoms",
    },
    {
        "wh2_main_lzd_lizardmen",
    },
    {
        "wh_main_grn_greenskins",
    }
}
```

### Compatibility

It was created to be used with Radious mod, but it's also compatible with any other mod.
Mod order doesn't matter.
You can add it during a campaign. Don't remove it then.

### Recommendations

I recommend using it with Radious mod, VH or Legendary difficulty.

### Settings

You can use "Rusted PackFile Manager" to edit settings.
It allows you to edit .pack file of the mode.
(top menu => packFile => open from content => ...)
Settings at the beginning of the lua file.
Change it and "save PackFile"

See "Rusted PackFile Manager" documentation about how to use it.

Effect bundles:

lua script: effect_bundles_turns = { 50 , 40, 30, 20, 10 } -- turns to activate bundle
db folders - effect values

https://github.com/Frodo45127/rpfm

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
# AF Armageddon — Agent Guide

Source code for the **"AF Armageddon"** mod for *Total War: Warhammer 3*.

Steam Workshop page: https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094

This file is for developers. What a player needs to know is in the
[user guide](docs/af-armageddon-user-guide.md): update it when the behaviour or the settings
change.

## What the mod does

A campaign difficulty mod. On each AI faction's turn start (`FactionTurnStart`), it grants
the faction bonuses. Only the human player and the rebels get none, whatever the settings:
there's no option for it. The AI factions of the player's own culture are like all the others
since v9.7.0: the bonus multiplier of their culture decides, see below. The player can turn off a
culture with its multiplier 0. Such factions lose their effect bundle at once, on their next
turn start, instead of keeping it until it runs out.
The bonuses scale up over the course of
the campaign (later turns / more player regions → bigger bonus). It is meant to be used
together with the Radious mod but works standalone; mod order doesn't matter, and it can
be added mid-campaign (just don't remove it afterwards).

**Multiplayer isn't supported.** The mod is designed for a single player campaign: the rules
know one player, and it has never been run in a multiplayer campaign.

Bonuses applied per eligible AI faction turn:
- **Treasury gold** — proportional to the AI faction's own income, scaled by current
  turn number and by the player's region count (see `settings.time_percent` /
  `settings.regions_percent`), multiplied by the bonus multiplier of the culture. Never
  negative: `faction:income()` can be below 0, and then the faction gets nothing instead of
  losing gold (`math.max(0, ...)`, and no `treasury_mod` call for 0).
- **Character XP** — added to every character in the faction, scaled by turn number
  (`settings.experience_for_character`) and by the bonus multiplier of the culture, rounded,
  starting from turn `settings.character_experience_start_turn`.
- **Unit XP** — +1 experience level per unit in armies that have a general, starting from
  turn `settings.army_experience_start_turn`, on every n-th turn
  (`settings.army_experience_turn_interval`: 1 — every turn, 3 — turns 3, 6, 9...). The
  interval is divided by the bonus multiplier of the culture and rounded half up, never below 1:
  `max(1, floor(interval / multiplier + 0.5))`.
- **Effect bundle** — one of five escalating "ai_buff" effect bundles
  (`af_armageddon_effect_bundle_ai_buff_1..5`) is applied based on turn number
  (see `effect_bundles_turns`); older bundles are removed first so only one is active. The
  bonus multiplier doesn't change it.

The **bonus multiplier** is the `bonus_multiplier_<culture>` option, 0 to 5, by default 1. A
culture without that option (another mod's, or no MCT, or multiplayer) gets 1, and so does a
value that isn't a number or is below 0. 0 turns off all the bonuses of the culture, the effect
bundle included: `help_ai_each_turn` returns before the interval is divided by it.

From v9.5.0 to v9.6.0 the AI factions of the player's culture got no bonuses, whatever their
multiplier. So after the update to v9.7.0 they get the bonuses in a running campaign too, with
the multiplier the save has for their culture, 1 unless the player changed it while it changed
nothing. The multiplier 0 keeps the old behaviour.

## Repository layout

```
mods/warhammer_3/!!af_armageddon/
  script/campaign/mod/af_armageddon.lua   <- the mod logic
  script/mct/settings/af_armageddon.lua   <- the settings window, loaded by MCT
mods/warhammer_3/!!af_armageddon.pack     <- packed, distributable mod (built with RPFM)
tests/af-armageddon/model_test.lua        <- tests of the script, see "Tests" below
af_armageddon-agent.md                    <- this file (lives at repo root, see agent.md's rule on mods/)
docs/af-armageddon-user-guide.md          <- guide for players
imgs/armageddon/!!af_armageddon.png       <- Steam Workshop preview image, 256x256
imgs/armageddon/                          <- screenshots for the user guide
```

Important: **effect bundle definitions themselves (the `af_armageddon_effect_bundle_ai_buff_*`
DB entries) are NOT in this repo as loose files.** They live only inside the `.pack` file,
authored directly with Rusted PackFile Manager (RPFM), in the `db/effect_bundles_tables/`
and `db/effect_bundles_to_effects_junctions_tables/` DB tables. This script only
*references* those bundle keys and applies/removes them via the campaign API — it does not
define them. To inspect or change the actual effect bundle contents, open the `.pack` in
RPFM (or, for an AI agent, read/edit those two DB tables via RPFM's MCP server — see
[private-agent.md](private-agent.md) for the local connection details).

Current contents of those two tables (all five bundles: `bundle_target: faction`,
`priority: 1`, `is_global_effect: true`, applied at `advancement_stage:
start_turn_completed`), scaling from buff 1 (weakest, turn 10+) to buff 5 (strongest,
turn 40+ — see `effect_bundles_turns` in the script for the turn thresholds):

| Effect                                  | Scope                          | buff_1 | buff_2 | buff_3 | buff_4 | buff_5 |
|------------------------------------------|--------------------------------|-------:|-------:|-------:|-------:|-------:|
| `wh_main_effect_technology_research_points` | faction_to_faction_own_unseen | 50 | 70 | 100 | 150 | 200 |
| `wh_main_effect_unit_recruitment_points`    | faction_to_province_own_unseen | 2 | 4 | 6 | 8 | 10 |
| `wh_main_effect_province_growth_events`     | faction_to_province_own_unseen | 20 | 40 | 60 | 80 | 100 |

(Read out via the RPFM MCP server on 2026-11-01; re-verify from the `.pack` if it's been
edited since.)

## Settings

The settings window is provided by
[Mod Configuration Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=2927955021)
(MCT), a separate Workshop mod and an optional dependency. Without it the mod runs on the
defaults from the `settings` table in the script.

| Option                            | Type     | Default | Meaning                                     |
|-----------------------------------|----------|---------|---------------------------------------------|
| `regions_percent`                 | slider   | `4`     | Percent of income per player region, 0-100  |
| `time_percent`                    | slider   | `2`     | Percent of income per turn, 0-100           |
| `experience_for_character`        | slider   | `200`   | Character XP multiplied by the turn number, 0-5000 |
| `character_experience_start_turn` | slider   | `10`    | First turn of character XP, 1-200           |
| `army_experience_start_turn`      | slider   | `10`    | First turn of unit XP, 1-200                |
| `army_experience_turn_interval`   | slider   | `2`     | Unit XP on every n-th turn, 1-50, before the bonus multiplier |
| `enable_logging`                  | checkbox | `false` | Writes `!!af_armageddon.txt`                |
| `bonus_multiplier_<culture>`      | dropdown | `'1'`   | `'0'` (off), `'0.1'`, `'0.25'` to `'2'` in steps of 0.25, `'3'`, `'4'`, `'5'`; one per culture, see [What the mod does](#what-the-mod-does) |

Values are read through `get_finalized_setting()` each time they're needed, and MCT updates
them as soon as they're saved in its window, so a change applies from the next faction turn.

MCT writes every global option to its settings file with its value, the default ones included
(`Registry:save` of MCT, `this_option.setting = option_obj:get_value_for_save()`, read on
2026-11-05), and loads that value later. So a new default reaches only the players who never
had the option saved: `army_experience_turn_interval` became 2 in v9.4.0, and a player who ran
an older version with MCT keeps 1. MCT shows its revert button next to such a value, and the
user guide tells the player about it. Don't change a default without that note.

All options but `bonus_multiplier_<culture>` are global (`set_is_global(true)`): one value for
all campaigns. New options must set it too, unless they belong to a campaign.

The checkboxes `skip_bonuses_<culture>` of v9.3.1-v9.4.0 are gone since v9.5.0, and since
v9.6.0 the multiplier 0 does what a ticked checkbox did. MCT ignores their values in old saves and in its settings file: it looks
every saved key up with `get_option_by_key` and skips a key without an option. So a culture
skipped in a running campaign gets the bonuses after the update, until the player sets its
multiplier to 0.

Multiplayer isn't supported, see [What the mod does](#what-the-mod-does). The code only lowers
the risk of a desync and doesn't make multiplayer a feature: there `get_setting` ignores MCT
and returns the defaults, as each player has their own values of global options, and "the
player" of the region count is the first faction of `cm:get_human_factions()`, not the local
one. It's the same faction in single player.

Keep the defaults in the MCT file and in the `settings` table of the script in sync, the
tests check that. The only exceptions are the options of the cultures, see below: the default
of `bonus_multiplier_<culture>` is `default_bonus_multiplier` of the script.

### The list of cultures

The `cultures` table of the MCT file is the only list of cultures in the repository: the
script builds the option key `bonus_multiplier_<culture>` from the culture of the faction. So
these options have no entry in `settings`, and a culture from another mod has no option and
gets the bonuses as they are. `get_setting` passes `true` to `get_option_by_key`, otherwise MCT
would write a warning to its log on each turn of such a faction. The culture of the player has
its option like any other, and it works for the AI factions of that culture.

- The multiplier is a `dropdown`: its values are string keys (`'0'`...`'5'`), and the
  script turns them into numbers with `tonumber`. Their text is the same string, not a loc key:
  MCT shows a text without a loc entry as it is.

- It's written by hand: MCT creates the options when this file loads, and its `multibox` type
  is an empty stub, `dropdown_game_object` is unfinished. Compare it with
  `db/cultures_tables` when a DLC adds a culture, and raise the number in the test. The `*` row
  isn't a culture, and `wh3_main_pro_ksl_kislev` of the prologue is left out on purpose: its
  name is the same "Kislev", and the main campaign doesn't have it.
- These options belong to a campaign (`set_is_global(false)`): MCT keeps them in the save, so
  the script reads them like any other option. A value set in the main menu applies to the
  next new campaign only. A campaign saved without them, for example one the mod was added
  to or one saved before v9.4.0, has the defaults (all multipliers 1), whatever the menu says.
- `set_text` gets the loc key `cultures_name_<culture>` of the game, so the names are in the
  language of the game. A key without text is shown as it is.
- The section of the cultures is the last one. MCT puts `ceil(n / 2)` sections into the first
  column and the rest into the second, whatever their height (`Settings.lua` of MCT), and the
  columns scroll. With five sections the first column has Gold and both experiences, the
  second has Debug and the long list of the cultures, so the other settings stay in view. A new
  section would break that split. MCT adds its own `default` section only when an option comes
  before any section, which isn't the case here.

## Toolchain

- Packs (`.pack`) are built/edited with **Rusted PackFile Manager (RPFM)**:
  https://frodo45127.github.io/rpfm/manual/intro/what-is-rpfm.html
- Scripting is **Lua 5.1**, running inside CA's campaign script sandbox (`cm` = campaign
  manager global, `core` = event listener global — both provided by the game, not defined
  in this repo).
- `.luarc.json` at the repo root points the Lua language server at RPFM's `tw_autogen`
  stub definitions for the WH3 `global`/`campaign`/`frontend`/`battle` APIs — install/point
  RPFM's autogen output there for autocomplete/diagnostics on `cm`/`core`/etc.
- No build step for the script itself; editing the `.lua` file directly is fine. To produce
  a playable mod you still need to re-import/re-pack it into the `.pack` via RPFM.

## Conventions / gotchas

- `mod_version` lives in both scripts, keep them equal: the MCT file shows it in the mod's
  title, and it runs in the frontend too, where the campaign script doesn't exist. Keep it in
  sync with the repo's `changelog.txt` and the root `readme.md` when behavior changes.
- The start line of the log is written on the first tick, not at load time: the MCT settings
  may not be loaded yet when the script file runs.
- `script/mct/settings/` is loaded by MCT in the frontend and in the campaign, so that file
  must only define settings; `cm` isn't available there.
- Logging is file-based: `!!af_armageddon.txt` in the game folder (relative `io.open`, no
  path), written only with the `enable_logging` option.
- `log_settings` writes all the settings to the log once per turn, on the first
  `FactionTurnStart` of that turn. It takes the keys from `mct_mod:get_options()`, as the
  script doesn't know the cultures, and the values from `get_setting`, so the log shows what
  the mod really uses. New options get there on their own.
- Check `is_logging_enabled()` before a log line whose text takes calls to the game: `log`
  checks it too, but only after the arguments were already evaluated.
- `add_agent_experience` takes effect later, so `level a => a` in the log doesn't mean the
  character got no experience: on 2026-11-01 all 1371 lines of a turn looked like that. The rank
  of a unit changes at once. 454 of those lines were generic lords and heralds at level 0, while
  nearly all the others were at level 6 and above. The log of one turn can't say why, it may be
  garrison commanders: compare the characters over several turns before drawing conclusions.
- This mod only acts on AI factions (`is_human()` and `is_rebel()` factions are skipped
  early in `help_ai_each_turn`, and then the factions of the cultures with the multiplier 0,
  which also lose their effect bundle). The player's culture isn't checked since v9.7.0.
- Lua numbers in the game are single-precision floats: the log of 2026-11-05 shows the
  multiplier `'0.1'` as `0.10000000149012`. The rounded interval and character experience still
  come out whole (`2 / 0.1` rounds to 20), but don't compare such results with `==`, and
  integers above 16,777,216 aren't exact. The tests run on Lua 5.4 with doubles and can't see
  it.
- v9.6.0 in the game, 2026-11-05, turn 51 of a Vampire Counts campaign with multipliers from 0.1
  to 5: 71 factions got gold with the multiplier of their culture, the cultures with 1.5 and
  more got unit experience on the odd turn 51 (interval 1), the two factions of the player's
  culture got nothing, no error. The multiplier 0 and a negative income didn't occur in that
  turn, so only the tests check them. v9.7.0, where the player's culture gets the bonuses,
  hasn't been run in the game yet.

## Tests

`tests/af-armageddon/model_test.lua` lives outside `mods/`, so it never gets into the pack.
It covers the unit XP (when it's added and which units and factions get it), the character
XP, the gold (a negative income included), who gets the bonuses (the culture of the player with
its own multiplier and the multiplier 0 included), the bonus multiplier of the cultures, the effect bundle of
each turn and the settings: the MCT
file against the defaults of the script, work without MCT, the log option. It runs the real
script against a small model of the game, MCT included, and changes the settings through the
MCT options. The local functions of the script aren't reachable, so it checks what they lead
to: the calls to the game. It doesn't talk to the real game or to the real MCT, so what they
answer still needs a run in the game. Run it after changing the scripts, and extend it with
the change.

It needs any Lua 5.4. The one inside the VS Code Lua extension will do. Run it from the
repository root, it prints `ALL PASSED` at the end:

```bash
"$(ls ~/.vscode/extensions/sumneko.lua-*/server/bin/lua-language-server.exe | tail -1)" "$(pwd -W)/tests/af-armageddon/model_test.lua"
```

## Related mods in this repo

Sibling mods under `mods/warhammer_3/` follow the same layout
(`script/campaign/mod/<name>.lua` + a matching `<name>.pack`):
- `af_turn_crash_debug_logger` — writes debug info to help diagnose repeated AI-turn crashes.

Root `readme.md` documents all mods for end users (Steam Workshop descriptions); update it
alongside `changelog.txt` when shipping a new version of this mod.

# AF Armageddon — Agent Guide

Source code for the **"AF Armageddon"** mod for *Total War: Warhammer 3*.

Steam Workshop page: https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094

This file is for developers. What a player needs to know is in the
[user guide](docs/af-armageddon-user-guide.md): update it when the behaviour or the settings
change.

## What the mod does

A campaign difficulty mod. On each AI faction's turn start (`FactionTurnStart`), it grants
the AI faction bonuses — but **only** if that faction's culture is in a different
*culture group* than the human player's culture. Two independent settings, both off by
default, widen that: `settings.bonus_for_same_culture` covers the player's own culture and
`settings.bonus_for_same_culture_group` the other cultures of the player's group. The bonuses
scale up over the course of
the campaign (later turns / more player regions → bigger bonus). It is meant to be used
together with the Radious mod but works standalone; mod order doesn't matter, and it can
be added mid-campaign (just don't remove it afterwards).

**Multiplayer isn't supported.** The mod is designed for a single player campaign: the rules
know one player, and it has never been run in a multiplayer campaign.

Bonuses applied per eligible AI faction turn:
- **Treasury gold** — proportional to the AI faction's own income, scaled by current
  turn number and by the player's region count (see `settings.time_percent` /
  `settings.regions_percent`).
- **Character XP** — added to every character in the faction, scaled by turn number
  (`settings.experience_for_character`), starting from turn
  `settings.character_experience_start_turn`.
- **Unit XP** — +1 experience level per unit in armies that have a general, starting from
  turn `settings.army_experience_start_turn`, on every n-th turn
  (`settings.army_experience_turn_interval`: 1 — every turn, 3 — turns 3, 6, 9...).
- **Effect bundle** — one of five escalating "ai_buff" effect bundles
  (`af_armageddon_effect_bundle_ai_buff_1..5`) is applied based on turn number
  (see `effect_bundles_turns`); older bundles are removed first so only one is active.

Culture groups (`culture_groups` table in the script) cluster related factions/subcultures
(e.g. all Chaos god cultures, all Empire/Bretonnia/Dwarfs/Kislev/Cathay "Order" cultures,
etc.) so that, for example, a Khorne player doesn't get bonuses against Tzeentch AI.

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
| `bonus_for_same_culture`          | checkbox | `false` | Bonuses for the player's own culture        |
| `bonus_for_same_culture_group`    | checkbox | `false` | Bonuses for the rest of the player's group  |
| `regions_percent`                 | slider   | `4`     | Percent of income per player region, 0-100  |
| `time_percent`                    | slider   | `2`     | Percent of income per turn, 0-100           |
| `experience_for_character`        | slider   | `200`   | Character XP multiplied by the turn number, 0-5000 |
| `character_experience_start_turn` | slider   | `10`    | First turn of character XP, 1-200           |
| `army_experience_start_turn`      | slider   | `10`    | First turn of unit XP, 1-200                |
| `army_experience_turn_interval`   | slider   | `1`     | Unit XP on every n-th turn, 1-50            |
| `enable_logging`                  | checkbox | `false` | Writes `!!af_armageddon.txt`                |

Values are read through `get_finalized_setting()` each time they're needed, and MCT updates
them as soon as they're saved in its window, so a change applies from the next faction turn.

All options are global (`set_is_global(true)`): one value for all campaigns. New options must
set it too.

Multiplayer isn't supported, see [What the mod does](#what-the-mod-does). The code only lowers
the risk of a desync and doesn't make multiplayer a feature: there `get_setting` ignores MCT
and returns the defaults, as each player has their own values of global options, and "the
player" of the culture check and of the region count is the first faction of
`cm:get_human_factions()`, not the local one. It's the same faction in single player.

Keep the defaults in the MCT file and in the `settings` table of the script in sync, the
tests check that.

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
- Logging is file-based, written into the game folder (relative `io.open`, no path):
  - `!!af_armageddon.txt` — normal run log, written only with the `enable_logging` option.
  - `!!af_armageddon-errors.txt` — error log, always written (used e.g. when a faction's
    culture isn't found in `culture_group_ids`).
- `culture_group_ids` is built once at load time by flattening `culture_groups`; when adding
  a new faction/subculture (e.g. a new DLC race), add its culture key to the correct group
  in `culture_groups`, not to `culture_group_ids` directly.
- `the_same_culture_group` logs to the error file (not a crash) when a culture key is
  missing from `culture_group_ids`, once per culture until the script loads again — treat that
  log as "a faction culture is missing from `culture_groups` and needs to be added". A missing
  culture is in no group, not even with another missing one, so such a faction gets the bonuses.
- Check `is_logging_enabled()` before a log line whose text takes calls to the game: `log`
  checks it too, but only after the arguments were already evaluated.
- `add_agent_experience` takes effect later, so `level a => a` in the log doesn't mean the
  character got no experience: on 2026-11-01 all 1371 lines of a turn looked like that. The rank
  of a unit changes at once. Generic lords stay at level 0 in that log, about a third of all
  lines, while the other characters are at level 6 and above.
- This mod only acts on AI factions (`is_human()` and `is_rebel()` factions are skipped
  early in `help_ai_each_turn`).

## Tests

`tests/af-armageddon/model_test.lua` lives outside `mods/`, so it never gets into the pack.
It covers the unit XP (when it's added and which units and factions get it), the character
XP, the gold, the culture groups, the effect bundle of each turn and the settings: the MCT
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

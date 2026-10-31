# AF Armageddon — Agent Guide

Source code for the **"AF Armageddon"** mod for *Total War: Warhammer 3*.

Steam Workshop page: https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094

## What the mod does

A campaign difficulty mod. On each AI faction's turn start (`FactionTurnStart`), it grants
the AI faction bonuses — but **only** if that faction's culture is in a different
*culture group* than the human player's culture. The bonuses scale up over the course of
the campaign (later turns / more player regions → bigger bonus). It is meant to be used
together with the Radious mod but works standalone; mod order doesn't matter, and it can
be added mid-campaign (just don't remove it afterwards).

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
  script/campaign/mod/af_armageddon.lua   <- the entire mod logic (only source file)
mods/warhammer_3/!!af_armageddon.pack     <- packed, distributable mod (built with RPFM)
tests/af-armageddon/model_test.lua        <- tests of the script, see "Tests" below
af_armageddon-agent.md                    <- this file (lives at repo root, see agent.md's rule on mods/)
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

(Read out via the RPFM MCP server on 2026-09-26; re-verify from the `.pack` if it's been
edited since.)

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

- Keep `mod_version` at the top of the script in sync with the repo's `changelog.txt` and
  the root `readme.md` when behavior changes.
- Logging is file-based, written into the game folder (relative `io.open`, no path):
  - `!!af_armageddon.txt` — normal run log, gated by `settings.enable_logging`.
  - `!!af_armageddon-errors.txt` — error log, always written (used e.g. when a faction's
    culture isn't found in `culture_group_ids`).
- `culture_group_ids` is built once at load time by flattening `culture_groups`; when adding
  a new faction/subculture (e.g. a new DLC race), add its culture key to the correct group
  in `culture_groups`, not to `culture_group_ids` directly.
- `the_same_culture_group` logs to the error file (not a crash) when a culture key is
  missing from `culture_group_ids` — treat that log as "a faction culture is missing from
  `culture_groups` and needs to be added".
- This mod only acts on AI factions (`is_human()` and `is_rebel()` factions are skipped
  early in `help_ai_each_turn`).

## Tests

`tests/af-armageddon/model_test.lua` lives outside `mods/`, so it never gets into the pack.
It covers the unit XP (when it's added and which units and factions get it), the character
XP, the culture groups and the effect bundle of each turn. It runs the real script against a small model of
the game and changes the `settings` in the text of the script, because they're a local table.
The local functions of the script aren't reachable, so it checks what they lead to: the calls
to the game. It doesn't talk to the real game, so what the game itself answers still needs a
run in the game. Run it after changing the script, and extend it with the change.

It needs any Lua 5.4. The one inside the VS Code Lua extension will do. Run it from the
repository root, it prints `ALL PASSED` at the end:

```bash
"$(ls ~/.vscode/extensions/sumneko.lua-*/server/bin/lua-language-server.exe | tail -1)" "$(pwd -W)/tests/af-armageddon/model_test.lua"
```

## Related mods in this repo

Sibling mods under `mods/warhammer_3/` follow the same layout
(`script/campaign/mod/<name>.lua` + a matching `<name>.pack`):
- `af_general_logger` — writes a per-turn CSV (`!!af_global_logger.csv`) of faction stats.
- `af_turn_crash_debug_logger` — writes debug info to help diagnose repeated AI-turn crashes.

Root `readme.md` documents all mods for end users (Steam Workshop descriptions); update it
alongside `changelog.txt` when shipping a new version of this mod.

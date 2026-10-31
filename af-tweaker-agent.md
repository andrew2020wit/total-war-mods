# AF Tweaker — Agent Guide

Source code for the **"AF Tweaker"** mod for *Total War: Warhammer 3*: a collection of small
campaign tweaks, each switched on and tuned from a settings window.

Not published on the Steam Workshop yet. First in-game run was on 2026-10-31 — see
[Verification status](#verification-status) for what it did and didn't confirm.

## What the mod does

### Automatic building upgrades

At the start of the player's turn the mod queues every building upgrade it can pay for,
spending only the money above a minimum the player sets:

1. `budget = treasury - min_treasury`. If the budget isn't positive, nothing happens.
2. Walk the player's regions and their building slots.
3. For each upgradable building, compare the cost with the budget. If it fits, queue the
   upgrade and subtract the cost from the budget; if not, move on to the next building (a
   cheaper one may still fit).
4. Stop when the budget runs out.
5. Log the result of the cycle: the budget at the start, the number of buildings upgraded,
   the total spent and the budget at the end.

The budget is tracked in the script because commands are asynchronous: `faction:treasury()`
doesn't change during the loop, so re-reading it would overspend.

A building is skipped when:
- the settlement is under siege;
- the slot is empty, already constructing, or is a lifecycle building;
- the upgrade is locked by a technology or by the settlement level;
- its non-gold resource cost can't be paid;
- it needs development points the region doesn't have;
- it has several upgrades inside its chain. That's the player's choice, so it's logged and
  left alone. Upgrades that lead into another chain (for example Cathay's yin/yang pairs)
  are ignored, and the building stays on its current chain.

Single-player only: the UI context objects used here aren't synchronized in multiplayer, so
the feature does nothing when `cm:is_multiplayer()` is true.

## Settings

The settings window is provided by
[Mod Configuration Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=2927955021)
(MCT), a separate Workshop mod and an optional dependency. Without it the mod runs on the
defaults from the `settings` table in the script.

| Option                 | Type     | Default | Meaning                                     |
|------------------------|----------|--------:|---------------------------------------------|
| `auto_upgrade_enabled` | checkbox | `true`  | Turns the automatic upgrades on             |
| `min_treasury`         | slider   | `5000`  | Money that automatic upgrades never touch   |
| `enable_logging`       | checkbox | `false` | Writes `!!af_tweaker.txt`                   |

Values are read when they're needed through `get_finalized_setting()`, and MCT updates them
in memory as soon as they're saved in its window. So a change made during the player's turn
applies from the next turn: this turn's cycle has already run. `enable_logging` is checked
on every log line.

The options aren't marked global, so MCT stores values changed inside a campaign for that
campaign. Values set in the main menu are what new campaigns start with.

Keep the defaults in the MCT file and in the `settings` table of the script in sync.

## Compatibility with other mods

Support for other mods is a hard requirement, Radious first of all. **Never hard-code
building data in this script.** Radious's `building_levels` tables change `create_cost` for
3172 vanilla levels and add about 180 new ones (checked against the installed packs on
2026-10-31), so a table of vanilla costs would be wrong.

Everything is read at runtime from the merged game data:
- `cm:get_building_level_upgrades` — the upgrades of a building;
- `CreateCost(settlement)` on `CcoBuildingLevelRecord` — the cost, the same expression the
  construction panel shows;
- `CanAfford`, `IsLockedByAnyTech`, `IsLockedByLevel` and the like — availability.

## How it works

The Lua campaign API has neither a building cost nor a "this slot is constructing" check, so
the mod talks to the game's UI context objects (CCO) through `common.get_context_value` and
`common.call_context_command`. Expressions are evaluated on `CcoCampaignSettlement`, whose id
is the region cqi, so `this` is the settlement. The building is queued with
`IssueCommandForBuildingBrowser(slot)`, the command the game itself runs when the player
clicks an upgrade.

`cm:add_building_to_settlement_queue` exists but isn't used: no vanilla script calls it, and
nothing confirms that it charges the player.

The expressions come from the vanilla layouts, which are the reference when something
breaks after a game patch: `ui/campaign ui/settlement_building_slot.twui.xml`,
`building_construction_popup.twui.xml` and `building_browser.twui.xml` in `ui3.pack`, plus
`ui/cco/buildings.cco` in `ui.pack`.

## Verification status

| What                                                                 | Status                         |
|----------------------------------------------------------------------|--------------------------------|
| Radious cost changes, upgrade tables                                 | Read from the packs            |
| Region cqi as the `CcoCampaignSettlement` id, reading slots, keys and costs from Lua | Works: 21 upgrades logged on turn 45 of a Vampire Counts campaign |
| The `0.5` s delay after `FactionTurnStart`                           | Works in that run              |
| `IssueCommandForBuildingBrowser` called outside a click              | Runs without errors; the queue on the map and the treasury change are **not confirmed yet** |
| Settings window, `enable_logging`                                    | **Not tested in the game**     |

Next in-game check: compare the `total spent` of the cycle with the treasury change and the
queue on the map.

## Repository layout

```
mods/warhammer_3/af-tweaker/
  script/campaign/mod/af_tweaker.lua      <- the mod logic
  script/mct/settings/af_tweaker.lua      <- the settings window, loaded by MCT
mods/warhammer_3/af-tweaker.pack          <- packed, distributable mod (built with RPFM)
af-tweaker-agent.md                       <- this file
```

The folder and the pack are `af-tweaker`, while the script files, the MCT key and the
listener names use `af_tweaker`. All the mod content is in the loose files, so the pack can
be rebuilt from the folder above at any time; rebuild it after editing the scripts.

## Toolchain

The same as for the other mods, see [agent.md](agent.md): Lua 5.1 in CA's campaign script
sandbox, packs built with RPFM. The vanilla data can be read through RPFM's MCP server (see
[private-agent.md](private-agent.md)).

## Conventions / gotchas

- Logs are written to the game folder: `!!af_tweaker.txt` (gated by the `enable_logging`
  option, off by default) and `!!af_tweaker-errors.txt` (always written).
- The start line of the log is written on the first tick, not at load time: the MCT settings
  may not be loaded yet when the script file runs.
- A new tweak gets its own section in the MCT file with an on/off option, and its own
  section in this guide.
- `script/mct/settings/` is loaded by MCT in the frontend and in the campaign, so that file
  must only define settings; `cm` isn't available there.
- Keep `mod_version` in sync with [changelog.txt](changelog.txt) and [readme.md](readme.md)
  when shipping.

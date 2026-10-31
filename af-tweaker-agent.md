# AF Tweaker — Agent Guide

Source code for the **"AF Tweaker"** mod for *Total War: Warhammer 3*: a collection of small
campaign tweaks, each switched on and tuned from a settings window.

This file is for developers. What a player needs to know is in the
[user guide](docs/af-tweaker-user-guide.md): update it when the behaviour or the settings change.

Not published on the Steam Workshop yet. First in-game run was on 2026-10-31 — see
[Verification status](#verification-status) for what it did and didn't confirm.

## What the mod does

At the start of the player's turn the mod spends the money above a minimum the player sets
(`budget = treasury - min_treasury`). Favorite buildings go first, upgrades get what's left.
Each pass stops when the budget runs out. At the end the cycle is logged: the budget at the
start, the numbers of favorites built and buildings upgraded, the total spent and the
budget at the end.

The budget is tracked in the script because commands are asynchronous: `faction:treasury()`
doesn't change during the loop, so re-reading it would overspend.

### Favorite buildings

The player marks a building with a star button in the popup of its slot. For each free slot
of each settlement, the mod takes the first favorite that can be built there and that fits
the budget.

The button:
- The hovered slot is found by polling every 250 ms on a real-time timer: `settlement_list >
  <settlement> > default_slots_list > <slot>`, asking each slot `IsMouseOverChildren()`.
- Don't use `ComponentMouseOn` here. Only components with a `ScriptEventReporter` send it, and
  vanilla slots have none. `common.force_report_of_all_ui_script_events(true)` sends it for the
  whole UI, but version 0.3.2 with that call crashed the game seconds after a click on a
  settlement, with no Lua error and a native stack, and no vanilla script uses it.
- Don't keep a uicomponent between timer ticks: the game may have destroyed it by then. Every
  poll finds everything anew. An error stops only the step that failed, the star or the skill
  buttons, and goes to the error log.
- The popup comes from the `mouseover` property of `settlement_building_slot`
  (`ContextComponentInitialiserMouseover`), so it isn't in that layout file. It's looked up by
  name with the recursive `Find`, inside the slot first and then in the whole UI. Don't use a
  full path: the one in the prologue scripts has a `popup_holder` that no longer exists, and
  following it silently finds nothing.
- The popup opens some time after the mouse enters, so polls before that find nothing and
  simply wait for the next one.
- With `favorite_buildings_enabled` off the polling does nothing and the button isn't shown.
- The button is created with `core:get_or_create_component` from
  `ui/templates/round_small_button_toggle` in `options_list`, next to the demolish button.
  No vanilla UI file is replaced.
- A click applies to the last building the button was shown for. While the mouse crosses
  another slot the old popup can still be open, so the key changes only when the context of
  `options_list` is the hovered slot, or when it has no such context.
- It's added only for the player's own buildings. The game hides `options_parent` when
  `CanShowOptionsPopup` is false, and the button goes with it.
- The icon goes on image index 0 of the template, which shows it at 38x38 in every state. So
  it must be a 38x38 image with the glyph centered: `af_tweaker_favorite_star.png` in the mod
  is made from the vanilla `icon_reputation_star_gold.png`, which is 26x26 with uneven margins
  and sits too high when used directly.
- The building browser has a separate `options_list`, which doesn't get the button.

The list:
- A favorite is stored as the first level of the chain, whichever level the player clicked,
  because that's what an empty slot can build. Later levels are the job of the upgrades.
- It's kept in `!!af_tweaker-favorites.txt` in the game folder, one key per line, in the order
  of adding, which is also the build priority. The file doesn't depend on a campaign, a save
  or MCT, and can be edited by hand. It's read when the script loads, written on each click.
- Keys the current game doesn't know, from a mod that's off for example, are logged and
  ignored but stay in the file. Keys of other factions are simply never buildable.
- Which building can go where is decided with the same checks as the construction popup:
  `PossibleBuildingChainsList`, `IsActiveForBuildingBrowser`, `DoesBuildingExceedCap`,
  `IsEpisodicRestricted`, `BuildingCanEverBeBuilt`.
- A key is built at most once per settlement per cycle, because the game doesn't see a
  queued building until the command is processed. The building cap across settlements has
  the same blind spot: if the game refuses such a command, the budget of that cycle is
  simply reduced by a building that wasn't built.
- Development points and pooled resources have the same blind spot, and only gold is counted
  in the script. So a cycle queues one building with a development point cost per province
  and one building with a pooled resource cost per faction (555 vanilla levels, the raw
  materials of the Chaos Dwarfs first of all). The rest wait for the next turn. The check for a
  pooled cost comes from `dlc29_vmp_vampire_lair_popup.twui.xml`:
  `IsContextValid(cost) && cost.PooledResourceTransactionList.IsEmpty == false`.

### Automatic character skills

Off by default. At the start of the player's turn, after the buildings, each character with
unspent points gets them spent. Skills go by priority, higher first, and in the order of the
skill tree for equal priorities; skills without a priority go last, so no point stays unspent
while something can be bought.

- `CcoCampaignCharacter` gives `SkillPointsAvailable` and `SkillList`. A skill can take a
  point when its `Status` is `active`, it isn't a background skill, `Level < TotalLevels`
  and the `RankRequired` of `NextLevelContext` is within the character's `Rank`.
- The statuses the game really reports are `active`, `inactive` and `locked_due_to_rank`, as
  seen in the log. The CCO docs say `available`, `complete`, `locked`, and the card states in
  the layout are yet another set: neither of them can be used for `Status`. Fully levelled
  skills are `active` too.
- If nothing could be bought for a character with points, `no skill to buy` in the log lists
  the number of skills per status.
- A point is added with `AddPoint` on the skill and applied with `CommitSkillChoices` on the
  character: the same steps as clicking a card and closing the panel, so the game charges
  the points. Don't use `cm:force_add_skill`: nothing confirms that it charges them.
- Points go in rounds: one point and one commit per character, then `skill_round_delay`
  (0.5 s) before the next round. Commands are asynchronous, so several points in one commit
  would be chosen from stale data. Skills lock each other a lot
  (`character_skill_nodes_skill_locks` has 2694 vanilla rows), no CCO function shows these
  locks, and the rank of a later level would go unchecked. The next round reads `Status`,
  `Level` and `NextLevelContext` after the commit, so all of this comes from the game itself.
- A character whose `SkillPointsAvailable` didn't go down between rounds drops out until the
  next turn, with `skill point not charged` in the log. So a refused command can't loop, and a
  slow commit can't lead to a choice from stale data.
- The rounds stop when the turn ends (`is_factions_turn`). The rest of the points wait for the
  next turn.
- Locked skills are just skipped, points aren't saved for them, and their parents aren't
  prioritized.
- It's independent from the game's own auto management (`AutoManagementContext`), which works
  at the end of the turn, so `IsAutoManaging` isn't checked. The game spends the points first
  on such characters, so the user guide says to keep it off. Wounded characters are skipped.

The priority button:
- With the feature on, the poll finds the visible `character_details_panel_skills` and walks
  `list_box` down to the components named `card`. The real path, from the `[ui]` lines of the
  script log, is `list_box > chain1 > chain > module_<key> > <skill key> > card`, deeper than
  the layout file suggests. The parent of a card is named after the skill, which gives the key.
- Every poll compares the icon with the priority of the skill.
- Each card gets one button that cycles none, 1, 2, 3, none. It's
  `ui/templates/round_extra_small_button` with all images but the icon replaced by a
  transparent one. It's docked to the top left corner of the card with a fixed offset, because
  the script log reports a `card` of about 578x301 while the visible card is 185 wide, so a
  right-side dock would land far from it.
- `af_tweaker_skill_priority_0..3.png` are 30x30, made from the vanilla gold star.

Priorities belong to a skill key, so they apply to every character with that skill, in every
campaign. They're in `!!af_tweaker-skill-priorities.txt` in the game folder, as `key=priority`
lines. The file is read when the script loads and written on each click.

CCO functions are documented at
https://github.com/chadvandy/tw_modding_resources/blob/master/WH3/cco/documentation.html.
Check there first, it lists far more than the vanilla layouts use.

### Automatic building upgrades

For each upgradable building, the cost is compared with the budget. If it fits, the upgrade
is queued; if not, the mod moves on to the next building (a cheaper one may still fit).

A building is skipped when:
- the settlement is under siege;
- the slot is empty, already constructing, or is a lifecycle building;
- the upgrade is locked by a technology or by the settlement level;
- its non-gold resource cost can't be paid;
- it needs development points the region doesn't have, or its province already got such a
  building this cycle;
- it has a pooled resource cost and another such building was queued this cycle;
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
| `min_treasury`         | slider   | `5000`  | Money the mod never touches                 |
| `favorite_buildings_enabled` | checkbox | `true` | Builds favorite buildings; the list itself comes from the star button |
| `auto_skills_enabled`  | checkbox | `false` | Spends skill points and shows the priority buttons |
| `enable_logging`       | checkbox | `false` | Writes `!!af_tweaker.txt`                   |

Values are read when they're needed through `get_finalized_setting()`, and MCT updates them
in memory as soon as they're saved in its window. So a change made during the player's turn
applies from the next turn: this turn's cycle has already run. `enable_logging` is checked
on every log line.

All options are global (`set_is_global(true)`): one value for all campaigns. Without that
call MCT stores a value changed inside a campaign for that campaign only, so new options
must set it too.

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
- `CanAfford`, `IsLockedByAnyTech`, `IsLockedByLevel` and the like — availability;
- the slot's chain — the key of a favorite building.

The star button adds to the vanilla popup from a script and replaces no UI file. Neither
Radious nor its bugfix submod overrides the popup, `settlement_building_slot`, the button
templates or `ui/cco/`, and none of their scripts touch the popup (checked on 2026-10-31).
A mod that replaces `building_construction_popup` and renames its components would lose the
button: `find_options_list` finds nothing and the game keeps working without it.

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
| Settings window, `enable_logging`                                    | Used in the game; global options **not confirmed yet** |
| Favorite buildings: the expressions for an empty slot                | Work: the log of 2026-10-31 shows 2 favorites built on turn 45 |
| Star button: finding the popup, clicks, saving to the file           | Works since 0.3.3, by polling; 0.3.0 and 0.3.1 didn't show it, 0.3.2 crashed the game |
| Centered icon of the star button                                     | **Not tested in the game**     |
| Reading `!!af_tweaker-favorites.txt` in a new campaign               | **Not tested in the game**     |
| Auto skills: `Status` values                                         | Read from the log of 0.4.3     |
| Auto skills: `AddPoint`, `CommitSkillChoices`, priorities            | Work in 0.4.4: 78 points on 22 characters in one cycle, confirmed by the user in the game |
| Auto skills in rounds: the commit is done within `skill_round_delay`, locked skills lose `active` | **Not tested in the game** (0.4.5) |
| One building per cycle for development points and pooled resources   | **Not tested in the game** (0.4.5) |
| Star button: the context of `options_list` is the slot               | **Not tested in the game** (0.4.5), the button works as before if there's no context |
| Priority button: the card hierarchy                                  | Read from the script log; 0.4.0 and 0.4.1 stopped one level too early |
| Priority button: shown on the cards, clicks saved to the file        | Works since 0.4.2              |
| Skill keys of the cards equal to `SkillList` keys                    | Yes: priority 3 applied first in that cycle |

Next in-game check: compare the `total spent` of the cycle with the treasury change and the
queue on the map; with 0.4.5, check that no `skill point not charged` lines appear for
characters with several points, and that a pair of locked skills gets only one point.

## Repository layout

```
mods/warhammer_3/af-tweaker/
  script/campaign/mod/af_tweaker.lua      <- the mod logic
  script/mct/settings/af_tweaker.lua      <- the settings window, loaded by MCT
  ui/skins/default/af_tweaker_favorite_star.png  <- icon of the favorite button
  ui/skins/default/af_tweaker_skill_priority_0..3.png  <- icons of the skill priority button
mods/warhammer_3/af-tweaker.pack          <- packed, distributable mod (built with RPFM)
af-tweaker-agent.md                       <- this file
docs/af-tweaker-user-guide.md             <- guide for players
imgs/tweaker/                             <- screenshots for the user guide
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
  option, off by default) and `!!af_tweaker-errors.txt` (always written). UI listeners go
  through `with_error_log`, since their errors are otherwise lost.
- Check `is_logging_enabled()` before a log line whose text takes context queries: `log`
  checks it too, but only after the arguments were already evaluated.
- Log lines show the in-game name in the game's language next to the key, like
  `Name (key)`. The key alone means the game returned no name: building names come from
  `PlayerVariantRecordContext.Name` on `CcoBuildingLevelRecord`, settlement names from
  `Name` on `CcoCampaignSettlement`.
- The start line of the log is written on the first tick, not at load time: the MCT settings
  may not be loaded yet when the script file runs.
- A new tweak gets its own section in the MCT file with an on/off option, and its own
  section in this guide.
- `script/mct/settings/` is loaded by MCT in the frontend and in the campaign, so that file
  must only define settings; `cm` isn't available there.
- `mod_version` lives in both scripts, keep them equal: the MCT file shows it in the mod's
  title, and it runs in the frontend too, where the campaign script doesn't exist. Keep it in
  sync with [changelog.txt](changelog.txt) and [readme.md](readme.md) when shipping.

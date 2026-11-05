# AF Tweaker — Agent Guide

Source code for the **"AF Tweaker"** mod for *Total War: Warhammer 3*: a collection of small
campaign tweaks, each switched on and tuned from a settings window.

This file is for developers. What a player needs to know is in the
[user guide](docs/af-tweaker-user-guide.md): update it when the behaviour or the settings change.

Steam Workshop page: https://steamcommunity.com/sharedfiles/filedetails/?id=3831853119

First in-game run was on 2026-10-31 — see [Verification status](#verification-status) for what
it did and didn't confirm.

## What the mod does

At the start of the player's turn the mod spends the money above a minimum the player sets
(`budget = treasury - min_treasury`). Favorite buildings go first, the ones with more stars
before the others, and upgrades get what's left. Each pass stops when the budget runs out. At the end the cycle is logged: the budget at the
start, the numbers of favorites built and buildings upgraded, the total spent and the
budget at the end.

The budget is tracked in the script because commands are asynchronous: `faction:treasury()`
doesn't change during the loop, so re-reading it would overspend.

### Favorite buildings

The player gives a building from one to three stars with a button in the popup of its slot,
like the priorities of skills. A building without stars is never put in a free slot, while
the upgrades don't depend on stars at all.

Each priority is a tier, and the tiers go from three stars down. A tier goes through the free
slots of all settlements before the next one starts, so the stars hold when the money runs
out: a one-star building of the first region can't spend what a three-star one of the last
region needs. Inside a tier a free slot takes the first favorite in the order of adding that
can be built there and that fits the budget. So fewer stars can still win when the better
building can't go in that slot or doesn't fit the budget: gold isn't saved up for it.

The button:
- The hovered slot is found by polling every 250 ms on a real-time timer: `settlement_list >
  <settlement> > default_slots_list > <slot>`, asking each slot `IsMouseOverChildren()`.
- Don't use `ComponentMouseOn` here. Only components with a `ScriptEventReporter` send it, and
  vanilla slots have none. `common.force_report_of_all_ui_script_events(true)` sends it for the
  whole UI, but version 0.3.2 with that call crashed the game seconds after a click on a
  settlement, with no Lua error and a native stack, and no vanilla script uses it.
- Don't keep a uicomponent between timer ticks: the game may have destroyed it by then. Every
  poll finds everything anew. An error goes to the error log. After `ui_poll_max_failures`
  errors in a row only the step that failed stops, the star or the skill buttons. A poll that
  works resets the count, because a single error can come from the UI being rebuilt.
- The polls run all the time, so they start from `settlement_panel` and
  `character_details_panel`, direct children of the root (`root > settlement_panel >
  settlement_list`, `root > character_details_panel > ... > character_details_panel_skills` in
  the `[ui]` lines of the script log). `find_child_uicomponent` looks only at the children of
  the root, while `Find` would walk the whole UI each time to learn that a panel is closed.
- The popup comes from the `mouseover` property of `settlement_building_slot`
  (`ContextComponentInitialiserMouseover`), so it isn't in that layout file. It's a child of its
  slot, as the `[ui]` lines of the script log show: `<slot> > building_construction_popup >
  popup_panel > building_tree_holder > options_parent > options_buttons > options_list`. So it's
  looked up by name with the recursive `Find` inside the hovered slot, and can't belong to
  another slot. Don't use a full path: the one in the prologue scripts has a `popup_holder` that
  no longer exists, and following it silently finds nothing.
- The popup opens some time after the mouse enters, so polls before that find nothing and
  simply wait for the next one.
- With `favorite_buildings_enabled` off the button isn't added, and one that's already in a
  popup is hidden when the popup is polled. Clicks are ignored.
- The button is created with `core:get_or_create_component` from
  `ui/templates/round_small_button` in `options_list`, next to the demolish button. It's the
  template of the vanilla buttons of this popup. No vanilla UI file is replaced.
- Each click cycles none, 1, 2, 3, none, and the icon shows the priority. The button isn't a
  toggle one: a toggle flips its state by itself on a click, which doesn't fit four values.
- A click finds its slot by going up from the star through the parents, not from the last
  poll: a popup can already have a star from an earlier hover, and the poll can be behind the
  mouse. So a click always goes to the building of its own popup.
- The icon of the star is set again whenever the hovered slot changes: two slots of the same
  chain can each have a popup with a star, and a click updates only one of them.
- Tooltips go through `SetTooltipText(text, '', true)`: the Assembly Kit docs have
  `text_source` before the flag for all states. Many mods, MCT among them, pass `(text, true)`.
- It's added only for the player's own buildings. The game hides `options_parent` when
  `CanShowOptionsPopup` is false, and the button goes with it.
- The icon goes on image index 0 of the template, which shows it at 38x38 in every state. So
  it must be a 38x38 image with the glyph centered: `af_tweaker_favorite_priority_0..3.png` in
  the mod. They're made from the vanilla `icon_reputation_star_gold.png`, which is 26x26 with
  uneven margins and sits too high when used directly: one gold star, the same star in grey for
  no priority, and for 2 and 3 the glyphs of `af_tweaker_skill_priority_2..3.png`.
- The building browser has a separate `options_list`, which doesn't get the button.

The list:
- A favorite is stored as the first level of the chain, whichever level the player clicked,
  because that's what an empty slot can build. Later levels are the job of the upgrades.
- It's kept in `!!af_tweaker-favorites.txt` in the game folder, as `key=priority` lines in the
  order of adding, which is the build order inside a tier. A new priority doesn't move a
  building in the list. A line with only a key, as versions up to 0.5 wrote it, has one star,
  and the next click rewrites the file in the new format. `key=0` means no favorite and a number
  above 3 means 3. The file doesn't depend on a campaign, a save or MCT, and can be edited by
  hand, a BOM from an editor is ignored. It's read when the script loads, written on each click.
- Keys the current game doesn't know, from a mod that's off for example, are logged and
  ignored but stay in the file. Keys of other factions are simply never buildable.
- Which building can go where is decided with the same checks as the construction popup:
  `PossibleBuildingChainsList`, `IsActiveForBuildingBrowser`, `DoesBuildingExceedCap`,
  `IsEpisodicRestricted`, `BuildingCanEverBeBuilt`.
- A key is built at most once per settlement per cycle, because the game doesn't see a
  queued building until the command is processed.
- Building caps have the same blind spot, and the script doesn't know which building has a
  cap, so all favorites are treated alike. The first copy of a key goes alone in its round, which is enough
  for a cap of one per faction: `DoesBuildingExceedCap` then answers for the rest. After that a
  round takes one copy per province, which is enough for a cap of one per province. A bigger
  cap can still be exceeded by the copies of one round. Such a command is refused, and the
  budget of that cycle is reduced by a building that wasn't built.
- Development points and pooled resources have the same blind spot, and only gold is counted
  in the script. So the cycle goes in rounds, `round_delay` (0.5 s) apart. A round queues one
  building with a development point cost per province and one building with a pooled resource
  cost per faction (555 vanilla levels, the raw materials of the Chaos Dwarfs first of all).
  What didn't fit waits for the next round, which reads what the game has left. Everything
  else, except the repeated favorites above, is queued in the first round. The check for a
  pooled cost comes from
  `dlc29_vmp_vampire_lair_popup.twui.xml`:
  `IsContextValid(cost) && cost.PooledResourceTransactionList.IsEmpty == false`.
- While a favorite waits for a round, the lower tiers and upgrades wait too, and the slot stays
  reserved for it instead of going to the next favorite. A building that waits holds its gold
  until the next round (`reserved`), so what comes later in the order can't take it. A tier
  starts in the round where nothing above it waits, so three tiers take more rounds than one.
- Only the first round of a pass, a tier of favorites or upgrades, goes through all regions.
  The next ones look only where a building waits or where the budget didn't reach, as each slot
  takes several context queries.
- A slot gets one command per cycle (`queued_slots`), and `for_each_slot` skips it after that.
  So a game slower than a round can't get the same command twice, and a refused command can't
  repeat. The next tier skips it too: commands are asynchronous, so a slot queued a moment ago
  still looks free. It also means the rounds end: a building waits only because another one
  was queued in that round.
- The costs are read before the command: after it a level expression through an empty slot may
  no longer resolve.

### Automatic character skills

On by default. At the start of the player's turn, after the first building round, each
character with unspent points gets them spent. Skills go by priority, higher first, and in
the order of the skill tree for equal priorities; skills without a priority go last, so no
point stays unspent while something can be bought.

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
- Points go in rounds: one point and one commit per character, then `round_delay`
  (0.5 s) before the next round. Commands are asynchronous, so several points in one commit
  would be chosen from stale data. Skills lock each other a lot
  (`character_skill_nodes_skill_locks` has 2694 vanilla rows), no CCO function shows these
  locks, and the rank of a later level would go unchecked. The next round reads `Status`,
  `Level` and `NextLevelContext` after the commit, so all of this comes from the game itself.
- A character whose `SkillPointsAvailable` didn't go down waits up to `skill_commit_rounds`
  more rounds, so a slow commit can't lead to a choice from stale data. A level up during the
  rounds can hide a charged point, so the `Level` of the skill going up counts as charged too.
  After that the skill counts as refused until the next turn, with `skill point not charged` in
  the log, and the character goes on with the next skill. A skill the game refuses can't block
  the other ones, and refused commands can't loop, as each one leaves one skill fewer to try.
  The counters in the log come from the points that were really charged.
- The rounds stop when the turn ends (`is_factions_turn`). The rest of the points wait for the
  next turn.
- Locked skills are just skipped, points aren't saved for them, and their parents aren't
  prioritized.
- It's independent from the game's own auto management (`AutoManagementContext`), which works
  at the end of the turn, so `IsAutoManaging` isn't checked. The game spends the points first
  on such characters, so the user guide says to keep it off. Wounded characters are skipped.

The priority button:
- The poll finds the visible `character_details_panel_skills` and walks `list_box` down to the
  components named `card`. The real path, from the `[ui]` lines of the script log, is
  `list_box > chain1 > chain > module_<key> > <skill key> > card`, deeper than the layout file
  suggests. The parent of a card is named after the skill, which gives the key.
- Every poll compares the icon with the priority of the skill. With `auto_skills_enabled` off
  it hides the buttons instead, and clicks are ignored.
- Each card gets one button that cycles none, 1, 2, 3, none. It's
  `ui/templates/round_extra_small_button` with all images but the icon replaced by a
  transparent one. It's docked to the top left corner of the card with a fixed offset, because
  the script log reports a `card` of about 578x301 while the visible card is 185 wide, so a
  right-side dock would land far from it.
- `af_tweaker_skill_priority_0..3.png` are 30x30, made from the vanilla gold star.

Priorities belong to a skill key, so they apply to every character with that skill, in every
campaign. They're in `!!af_tweaker-skill-priorities.txt` in the game folder, as `key=priority`
lines. The file is read when the script loads and written on each click, and it can be edited
by hand too.

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
- it needs development points the region doesn't have;
- it has several upgrades inside its chain. That's the player's choice, so it's logged and
  left alone. Upgrades that lead into another chain (for example Cathay's yin/yang pairs)
  are ignored, and the building stays on its current chain.

Upgrades with a development point or pooled resource cost go in rounds, like favorites: see
[Favorite buildings](#favorite-buildings).

Single-player only: the UI context objects used here aren't synchronized in multiplayer, so
the feature does nothing when `cm:is_multiplayer()` is true, and the UI polling that shows
the buttons doesn't start.

### Auto fuse of magic items

On by default. A button in the header of the global pool of the character panel fuses the
player's unequipped magic items in pairs, one pair per round (`round_delay`), only in the
player's turn. Each round reads the list anew and fuses the first pair of the lowest level, so
all common pairs go before the uncommon ones, and the uncommon items made from commons are
fused too. Nothing above uncommon is fused, and uncommon items only with `auto_fuse_uncommon`
(on by default): with it off a run fuses common items only and keeps every uncommon one, the
new ones included. A fusion can't be undone and the button asks nothing, so that option is the
player's way to keep the uncommon items they already have.

How the game fuses, read from the vanilla files on 2026-11-05:
- The Fuse button of `ui/campaign ui/character_details_panel_details.twui.xml` (`ui3.pack`)
  runs `FirstContext.FuseForPlayer(LastContext)` on the two ticked `CcoCampaignAncillary`
  items and is active when `Size == 2 && FirstContext.CanFuse(LastContext)`. The checkbox of an
  item is inactive when `IsLocalPlayersTurn == false || AncillaryRecordContext.CanBeDestroyed
  == false`.
- The game then sends the script event `AncillariesFused`, and the vanilla listener of
  `script/campaign/wh3_campaign_item_fusing.lua` adds a random item of the next rarity and the
  same category with `cm:add_ancillary_to_faction`. Commons give uncommons, uncommons give
  rares, rares give a unique by chance or scrap. The event has `faction()`,
  `first_ancillary_key()`, `second_ancillary_key()`, `ancillary_category_key()` and
  `ancillary_uniqueness_group_key()`; the keys are the ancillary keys, like
  `wh_main_anc_armour_charmed_shield` (the vanilla listener writes them to the game's script
  log).

What the script does:
- The items are `AncillaryList` of `CcoCampaignFaction`, whose id is the faction cqi, the same
  call as in the vanilla `wh_campaign_interventions.lua`. Pairs are fused with
  `AncillaryList.At(i).FuseForPlayer(AncillaryList.At(j))` on the faction context, so no
  checkbox of the UI is ticked. Indices are read and used in the same round, while the list
  can't change.
- An item takes part when `IsContextValid(CharacterEquippedToContext) == false`, the same check
  as the vanilla "Only show unequipped items" filter, plus `IsFusable`, `CanBeDestroyed`, the
  category filter of the Magic Items tab (`IsHidden == false`, not `general`, not `mount`) and
  `FrameState != "..."` for each level the run keeps. All of it is one query per item, so the
  level and the category of a kept item are never read: a late game pool holds many rares.
- The level is `AncillaryRecordContext.FrameState`: the `ui_state` of the item's row in
  `ancillary_uniqueness_groupings` (`common` 35-50, `uncommon` 80-100, `rare` 130-150,
  `legendary` for unique and unique fusable, `crafted` for scrap, runes and crafted items), the
  states of the vanilla item frame. Only `common` and `uncommon` are fused, so the Necronium
  grimoire and tome (legendary) and the scrap of failed fusions (crafted) are never taken. A
  state that isn't on any list passes the query but has no bucket, so it's skipped too.
- The category is `CategoryContext.Category`. Two items must have the same level and category,
  and `CanFuse` must agree; a pair it refuses is skipped, and the next pair is tried. After the
  script's own filters the vanilla `CanFuse` has nothing left to refuse, so refused pairs aren't
  remembered between rounds.
- A fusion counts as done when `AncillariesFused` comes for the player's faction with the keys
  of the pending pair, in any order. An event with other keys is a fusion the player made by
  hand with the vanilla Fuse button during the run: it's logged and only lowers the number of
  items the pending fusion waits for. A fusion without its event within `fuse_confirm_rounds`
  rounds stops the run with an error.
- The keys of the records (`AncillaryRecordContext.Key`, through `tostring`) are compared with
  the keys of the event, and that equality isn't confirmed in the game. So when the first
  fusion of a session times out while events with other keys came, the script takes one of
  them for it, writes the keys of both to the errors file, and sets `fuse_event_keys_match` to
  false: from then on any event of the faction confirms the pending fusion, as in 0.7.0. The
  first matching event sets it to true, and then a timeout is an error again. A mismatch costs
  `fuse_confirm_rounds` rounds once per session.
- A hand fusion of copies of the pending pair has the same keys and is taken for it. The event
  of the pending pair then counts as another fusion, so the numbers of items stay right. The next
  round may pick the pair still on its way again; its second command finds the items gone and,
  as the model of the tests assumes, does nothing.
- The new item comes from the vanilla listener of the event, later than the event itself, so
  the next round reads the list only when it has `item_number - 1 - other_fusions` items, for
  at most `fuse_confirm_rounds` more rounds: a new item that came later would otherwise be taken
  for the item of the next fusion. After the wait a list that didn't get shorter stops the run
  with an error: each round must take items, or the rounds might never end.
- The run stops when the turn is over. The button is inactive while a run goes and outside the
  player's turn, and a click then is ignored.
- `run_rounds` calls the end of a run in `pcall` too, and the end of the auto fuse resets
  `fuse_run` before anything else, so an error there can't leave the button inactive.

The button:
- `ui/templates/round_extra_small_button`, 30x30, in `global_pool > header`, docked to the
  center right of the header (`SetDockingPoint(6)`, offset -6). The header is the 281x30 title
  banner, its text is centered, so the right side is free. Other components of the panel are
  named `header` too, so the header is taken as a direct child of `global_pool`.
- The icon is `af_tweaker_auto_fuse.png`, 38x38 like the vanilla `icon_cross_small.png` of the
  template, with the glyph of the vanilla `icon_merge.png` (the merging of units) scaled to 24
  px and centered.
- It's added and refreshed by the same UI poll as the stars, so it's never kept between polls.
  With `auto_fuse_enabled` off it's hidden and clicks are ignored. The poll also sets its state:
  `inactive` during a run and outside the local player's turn, `active` otherwise. Without a
  local faction (`cm:get_local_faction_name(true)` gives false) it's inactive, and a click only
  logs it, instead of an error on every poll.
- The sort direction button of the pool stays as it is: the header had room for a new button.

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
| `auto_skills_enabled`  | checkbox | `true`  | Spends skill points and shows the priority buttons |
| `auto_fuse_enabled`    | checkbox | `true`  | Shows the auto fuse button of the global pool |
| `auto_fuse_uncommon`   | checkbox | `true`  | The button fuses uncommon items after the common ones |
| `enable_logging`       | checkbox | `false` | Writes `!!af_tweaker.txt`                   |

Values are read when they're needed through `get_finalized_setting()`, and MCT updates them
in memory as soon as they're saved in its window. So a change made during the player's turn
applies from the next turn: this turn's cycle has already run. `enable_logging` is checked
on every log line.

All options are global (`set_is_global(true)`): one value for all campaigns. Without that
call MCT stores a value changed inside a campaign for that campaign only, so new options
must set it too.

Keep the defaults in the MCT file and in the `settings` table of the script in sync, the
tests check that.

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
| Star button on `round_small_button`: icons of all priorities, their change on a click | **Not tested in the game** (0.6.0) |
| Favorite tiers: more stars get the money first in all settlements    | **Not tested in the game** (0.6.0) |
| Centered icons of the star button                                    | **Not tested in the game**     |
| Reading `!!af_tweaker-favorites.txt` in a new campaign               | **Not tested in the game**     |
| Reading an old list without priorities                               | **Not tested in the game** (0.6.0) |
| Auto skills: `Status` values                                         | Read from the log of 0.4.3     |
| Auto skills: `AddPoint`, `CommitSkillChoices`, priorities            | Work in 0.4.4: 78 points on 22 characters in one cycle, confirmed by the user in the game |
| Auto skills in rounds: the commit is done within `round_delay`       | Works in 0.5.2: 82 points on 23 characters in one cycle, no `not charged` lines |
| Auto skills in rounds: locked skills lose `active`                   | **Not tested in the game** (0.4.5) |
| Auto skills: moving on to the next skill after a refused point       | **Not tested in the game** (0.5.0) |
| Building rounds for development points                               | Work in 0.5.2: upgrades waited with their gold reserved, the rounds ended, the budget adds up with the costs in the log |
| Building rounds for pooled resources                                 | **Not tested in the game** (0.5.0) |
| Star button: the popup is a child of its slot                        | Read from the `[ui]` lines of the script log |
| Star button: a click finds the slot through the parents              | Works in 0.5.2: a click saved the key of its building, no errors |
| Tooltips of both stars on hover, with `text_source`                  | **Not tested in the game** (0.5.2) |
| Auto skills: `Level` goes up after a commit                          | **Not tested in the game** (0.5.2) |
| `{{tr:key}}` in the names of the log, `get_localised_string`         | **Not tested in the game** (0.5.3) |
| Star button: the icon after a click on another slot of the chain     | **Not tested in the game** (0.5.1) |
| Favorites with a cap: refused commands are gone                      | **Not tested in the game** (0.5.1) |
| Panels as direct children of the root                                | Works in 0.5.2: both kinds of stars were shown and clicked |
| Hiding the buttons when an option is turned off                      | **Not tested in the game** (0.5.0) |
| Priority button: the card hierarchy                                  | Read from the script log; 0.4.0 and 0.4.1 stopped one level too early |
| Priority button: shown on the cards, clicks saved to the file        | Works since 0.4.2              |
| Skill keys of the cards equal to `SkillList` keys                    | Yes: priority 3 applied first in that cycle |
| Auto fuse: `FuseForPlayer` and `CanFuse` from the faction context, `IsFusable`, `FrameState` | Work in 0.7.0: 5 common and 3 uncommon pairs on turn 50 of a Vampire Counts campaign, each of the same category, no errors |
| Auto fuse: `AncillariesFused` after `FuseForPlayer` from a script, the new item in the next round | Works in 0.7.0: the vanilla listener logged all 8 fusions, and 2 of the 3 uncommon pairs used items it had just spawned (Nightshroud, Ogre Blade); about 0.7 s per pair, no popups |
| Auto fuse button in `global_pool > header`                           | Works in 0.7.0: the `[ui]` line of the click shows that path and 30x30 |
| Auto fuse: equipped items are kept                                   | Works in 0.7.0: Vlad kept his Nightshroud, while the free Nightshroud of the same run was fused |
| Auto fuse: no pair of the same rarity and category is left           | Works in 0.7.0: the pool after the run, seen by the user, has one free item per common or uncommon category |
| Auto fuse button: to the right of the title, not covering it         | Works in 0.7.0, seen by the user |
| Auto fuse button: inactive during a run                              | **Not confirmed yet**: a run of 8 pairs takes about 5 s; the `[ui]` lines of the log show only the clicked component |
| Auto fuse button: inactive outside the player's turn (0.8.0)         | **Not confirmed yet**          |
| Auto fuse: `first_ancillary_key()` of the event equals `AncillaryRecordContext.Key` (0.8.0) | Works in 0.8.1: 14 fusions on turn 52 of a Vampire Counts campaign, each confirmed by its own keys (no "another fusion" line, no errors file); the vanilla log shows the same keys in the same order, like `wh_main_anc_armour_charmed_shield` + `wh_main_anc_armour_dragonhelm` |
| Auto fuse: the wait for a late new item (0.8.0)                      | Costs nothing in 0.8.1: 14 pairs in 9.5 s, about 0.7 s per pair as in 0.7.0 |
| Auto fuse: a second command for a pair already fused does nothing (0.8.1) | **Not confirmed yet**: only after a hand fusion of copies of the pending pair |
| Auto fuse: `FrameState != "..."` inside the query of the free items (0.8.0) | Works in 0.8.1: the run found 8 common and 6 uncommon pairs, and no rare item was fused; a broken query would have found no item at all |
| Auto fuse: `auto_fuse_uncommon` off keeps the uncommon items (0.8.0) | **Not confirmed yet**: the run of 0.8.1 had it on |

Next in-game check: click the star of a building through all four icons and look at the file;
with a small budget, check in the log that three stars are built before one star; compare the
`total spent` of the cycle with the treasury change and the queue on the map; check that both
kinds of stars show their tooltips on hover; check that a pair of locked skills gets only one
point; with a faction that uses pooled resources, check that several such buildings are queued
in one turn.

## Tests

Tests live in `tests/af-tweaker/`, outside `mods/`, so they never get into the pack. They
check the logic of the script. Neither of them talks to the real game, so what the game itself
answers still needs a run in the game: see [Verification status](#verification-status). Run
them after changing the script, and extend them with the change.

- `model_test.lua` runs the script against a small model of the game, UI included: rounds,
  refused points, the choice of an upgrade, the order of fusions, late new items, fusions by
  hand during a run (of copies of the pending pair too), event keys that differ from the
  records, items that stay, the buttons, no local faction, multiplayer, work without MCT. Its filter of
  the free items checks each part of the query on its own, so a part dropped from the script
  fails a test. It also
  checks the MCT file against the defaults and the version of the script. It needs any Lua 5.4.
  The one inside the VS Code Lua extension will do. Run it from the repository root, it prints
  `ALL PASSED` at the end:

  ```bash
  "$(ls ~/.vscode/extensions/sumneko.lua-*/server/bin/lua-language-server.exe | tail -1)" "$(pwd -W)/tests/af-tweaker/model_test.lua"
  ```

- `rpfm_test.lua` runs the script with the game's real script libraries, so it also checks
  loading, the first tick, the listener and the campaign interfaces of the Assembly Kit docs.
  It needs RPFM's MCP server, the Assembly Kit and the dependencies cache
  (`generate_dependencies_cache`). It reads the scripts from the open pack, so rebuild the
  pack first. Pass the text of the file as `code` of `run_lua_tests`: the test engine can't
  read files from the disk. Don't pass `campaign`. The report is long, its lines of interest
  start with `AFT`.

## Repository layout

```
mods/warhammer_3/af-tweaker/
  script/campaign/mod/af_tweaker.lua      <- the mod logic
  script/mct/settings/af_tweaker.lua      <- the settings window, loaded by MCT
  ui/skins/default/af_tweaker_favorite_priority_0..3.png  <- icons of the favorite button
  ui/skins/default/af_tweaker_skill_priority_0..3.png  <- icons of the skill priority button
  ui/skins/default/af_tweaker_auto_fuse.png  <- icon of the auto fuse button
mods/warhammer_3/af-tweaker.pack          <- packed, distributable mod (built with RPFM)
af-tweaker-agent.md                       <- this file
docs/af-tweaker-user-guide.md             <- guide for players
imgs/tweaker/af-tweaker.png               <- Steam Workshop preview image, 256x256
imgs/tweaker/                             <- screenshots for the user guide
tests/af-tweaker/                         <- tests of the script, not part of the pack
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
  `Name` on `CcoCampaignSettlement`. A name can hold a reference to another text, `{{tr:key}}`,
  which the game returns as it is: `with_name` looks the key up with the prefix
  `ui_text_replacements_localised_text_` (`Spread Corruption`), then as a whole loc key
  (`The Hunger`). Only a reference without any text stays in the log.
- The start line of the log is written on the first tick, not at load time: the MCT settings
  may not be loaded yet when the script file runs.
- A new tweak gets its own section in the MCT file with an on/off option, and its own
  section in this guide.
- `script/mct/settings/` is loaded by MCT in the frontend and in the campaign, so that file
  must only define settings; `cm` isn't available there.
- `mod_version` lives in both scripts, keep them equal: the MCT file shows it in the mod's
  title, and it runs in the frontend too, where the campaign script doesn't exist. Keep it in
  sync with [changelog.txt](changelog.txt) and [readme.md](readme.md) when shipping.

# total-war-mods — Agent Guide

Personal collection of mods for **Total War: Warhammer 3**, published on the Steam
Workshop. See [readme.md](readme.md) for the user-facing description of each mod and
[changelog.txt](changelog.txt) for version history.

## Repository layout

```
mods/warhammer_3/
  !!af_armageddon/                         <- source for "AF Armageddon" (see af_armageddon-agent.md at repo root)
  !!af_armageddon.pack                     <- packed/distributable build of the mod above
  af_turn_crash_debug_logger/
    script/campaign/mod/af_turn_crash_debug_logger.lua
  af_turn_crash_debug_logger.pack
  af-tweaker/                              <- source for "AF Tweaker" (see af-tweaker-agent.md at repo root)
  af-tweaker.pack
imgs/armageddon/                            <- Steam Workshop preview and user guide screenshots of AF Armageddon
imgs/tweaker/                               <- Steam Workshop preview and user guide screenshots of AF Tweaker
docs/                                       <- guides for players
tests/af-armageddon/                        <- tests of AF Armageddon (see af_armageddon-agent.md)
tests/af-tweaker/                           <- tests of AF Tweaker (see af-tweaker-agent.md)
readme.md                                   <- end-user description of all mods (Workshop text)
changelog.txt                               <- version history across mods
af_armageddon-agent.md                      <- per-mod agent guide for AF Armageddon (see rule below)
af-tweaker-agent.md                         <- per-mod agent guide for AF Tweaker
.luarc.json                                 <- Lua language server config (gitignored, local-only)
.mcp.json                                    <- local RPFM MCP server config (gitignored, local-only)
temp/                                        <- scratch/WIP files, gitignored, not part of the project
```

Each mod follows the same pattern: a source folder named after the mod containing
`script/campaign/mod/<mod_name>.lua`, plus a sibling `<mod_name>.pack` file which is the
actual packaged, playable mod built from that source (and, in some cases, additional
data authored directly in the pack — see the per-mod notes below).

**Rule: nothing under `mods/` except what belongs in a pack build (and the `.pack` files
themselves).** `mods/<game>/<mod_name>/` is imported directly into RPFM to build the
`.pack` — it must only contain actual mod source (scripts, tables, assets, etc.), never
agent/AI documentation or other non-pack files (in particular, no `.md` files). Per-mod
`agent.md`-style docs belong at the **repository root**, named `<mod_name>-agent.md` (e.g.
[af_armageddon-agent.md](af_armageddon-agent.md) for `!!af_armageddon`), not inside the
mod's own source folder.

For **AF Armageddon** specifically, its own detailed agent guide is here:
[af_armageddon-agent.md](af_armageddon-agent.md)

### Private, machine-specific instructions

[private-agent.md](private-agent.md) (gitignored, not published) holds non-public
instructions for the agent that are specific to this machine (local tool install paths,
ports, personal workflow notes, etc.). Any future private instruction for the agent must
go there and nowhere else — this file and the per-mod `agent.md` files stay public and
project-wide only.

## The mods

- **AF Armageddon** (`!!af_armageddon`) — campaign difficulty mod; scales AI bonuses over
  time. Single player only: multiplayer isn't supported. See its dedicated
  [af_armageddon-agent.md](af_armageddon-agent.md) for details.
- **Turn crash debug logger** (`af_turn_crash_debug_logger`) — writes debug info
  (`!af_turn_crash_debug_logger.csv`) to help pinpoint what's causing a repeated AI-turn
  crash, so the offending faction/character can then be killed via the in-game Lua console.
- **AF Tweaker** (`af-tweaker`) — small campaign tweaks with a settings window; for now,
  automatic building upgrades, favorite buildings, automatic character skills and the auto fuse
  button of magic items. See its dedicated
  [af-tweaker-agent.md](af-tweaker-agent.md).

## Toolchain

- `.pack` files are the packaged mod format for Total War games, built/edited with
  **Rusted PackFile Manager (RPFM)**:
  https://frodo45127.github.io/rpfm/manual/intro/what-is-rpfm.html
- RPFM v5.0+ ships `rpfm_server`, which exposes an MCP endpoint (150+ tools: open/edit
  packs, decode/edit DB tables, run diagnostics, etc.) for AI agents. When available
  locally, it's wired up via the gitignored `.mcp.json` — see
  [private-agent.md](private-agent.md) for the actual local server details.
- Campaign scripts are **Lua 5.1**, running in CA's campaign script sandbox (globals like
  `cm`, `core` are provided by the game at runtime, not defined in this repo).
- `.luarc.json` points the Lua language server at RPFM's `tw_autogen` stub definitions for
  the WH3 `global`/`campaign`/`frontend`/`battle` APIs, for autocomplete/diagnostics.
- There's no build step for editing the `.lua` sources directly; to produce a playable mod,
  changes still need to be imported/packed into the corresponding `.pack` via RPFM.

## Conventions

- Each mod keeps its own `mod_version` inside its script; bump it and update the relevant
  section of `readme.md` / `changelog.txt` when shipping a behavior change.
- Runtime logs written by these mods land as files in the *game* folder (not this repo),
  using relative `io.open` paths, e.g. `!!af_armageddon.txt`, `!af_turn_crash_debug_logger.csv`.
- `mods/warhammer_3/!!af_armageddon.pack`'s effect-bundle data tables are authored directly
  in RPFM and are not present as loose files in this repo — see
  [af_armageddon-agent.md](af_armageddon-agent.md) for details before assuming all mod
  content is in the `.lua` sources.
- License: MIT (see [readme.md](readme.md)).

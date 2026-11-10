# PZ_Mods

Project Zomboid mods, targeting **Build 42** (the server runs 42.21.0).

## What's here

| Folder | What it is |
|---|---|
| [`batman_LiveWireCoupling/`](batman_LiveWireCoupling) | **Live Wire: Coupled Inverter Zones**, the released add-on for [Live Wire](https://github.com/cyberbobjr/LiveWire). Same files as the [Steam Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3830945476); [its README](batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling/README.md) lists every change. |
| [`batman_LiveWireCoupling_dev/`](batman_LiveWireCoupling_dev) | Work in progress for the next version. Not for use. |
| [`batman_LiveWireCoupling_v2/`](batman_LiveWireCoupling_v2) | Version 2.0, waiting for the next Live Wire release: it plugs into Live Wire's new coupling extension point instead of replacing Live Wire files. Not for use yet; [its release checklist](batman_LiveWireCoupling_v2/RELEASE.md). |
| [`tests/`](tests), [`tools/`](tools) | Offline tests and the Live Wire update checker (see below). |

To play, subscribe on the Workshop rather than downloading from here.

## Layout

Each mod lives in its own top-level folder using the Steam Workshop layout, so it can be uploaded with the in-game Workshop tool:

```
MyMod/
├── workshop.txt              # Workshop title/description/tags (written by the uploader)
├── preview.png               # 256x256 Workshop thumbnail
└── Contents/mods/MyMod/
    ├── common/               # Required in B42 (can be empty); shared assets for all versions
    └── 42/
        ├── mod.info
        ├── poster.png
        └── media/
            ├── lua/
            │   ├── client/   # UI, input, client-only logic
            │   ├── server/   # Server-only logic
            │   └── shared/   # Loaded on both (items, recipes, shared helpers)
            └── scripts/      # Item/recipe script definitions
```

Minimal `mod.info`:

```
name=My Mod
id=MyMod
description=What it does.
poster=poster.png
versionMin=42.0.0
```

## Testing on the server

1. Link the mod into the game's Workshop folder:
   ```bash
   mkdir -p ~/Zomboid/Workshop && ln -s ~/PZ_Mods/MyMod ~/Zomboid/Workshop/MyMod
   ```
2. Add the mod `id` to `Mods=` in `~/Zomboid/Server/servertest.ini` (semicolon-separated).
3. Restart the server.

Mods that aren't on the Workshop don't auto-download to players, so anyone joining needs a local copy too.

## Offline tests

`tests/` holds offline tests for the Live Wire add-on: a syntax check of every Lua
file plus test scripts that run the add-on's code with stand-ins for the game.
`link_couple_test.lua` also runs Live Wire's own files (the link and couple
actions, `LW_Install`, `LW_Defs`) with the add-on's replacements.

They need two local folders, both ignored by git. Create them once:

```bash
python3 -m venv .venv && .venv/bin/pip install "lupa==2.8"
```

```bash
git clone https://github.com/cyberbobjr/LiveWire .livewire && git -C .livewire checkout v1.7.2
```

`.venv` gives Lua 5.1 through the `lupa` package. `.livewire` is Live Wire's
source with every release tag, checked out at the version being tested (the one
in the add-on's mod.info, "Made for Live Wire X.Y.Z").

For the 2.0 build, also clone Live Wire's beta branch, which has the coupling
extension point (until it is in a Live Wire release):

```bash
git clone --branch beta https://github.com/cyberbobjr/LiveWire .livewire-beta
```

`tests/v2/` holds the 2.0 build's tests. The runner picks them, and
`.livewire-beta`, by itself for a 2.0 build (a mod with `LWC_Register.lua`):

```bash
git -C .livewire-beta pull && .venv/bin/python tests/run_tests.py batman_LiveWireCoupling_v2/Contents/mods/batman_LiveWireCoupling_v2/42.21/media/lua
```

Then run every test against the release, or the dev copy's `media/lua` folder:

```bash
.venv/bin/python tests/run_tests.py batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling/42.21/media/lua
```

Name test files after the folder to run only those, and add
`--livewire <folder>` to test against another Live Wire `media/lua` folder.

## When Live Wire updates

The add-on replaces whole Live Wire files, so a Live Wire update to any of them
has to be merged in, or the add-on breaks or undoes the author's fixes. Check a
new release with:

```bash
python3 tools/livewire_update.py
```

It compares the latest Live Wire tag with the version the release is built on:
which replaced files changed, functions Live Wire added to them that the add-on
lacks (what broke 1.3.0 on Live Wire 1.7.2), names the add-on uses that Live
Wire removed (what broke 1.2.0 on 1.7.0), and the offline tests run with the
new version. Exit status 0 means nothing to do.

If the add-on needs an update, start the dev build with `--merge`. It 3-way
merges the changed files into the dev copy, moves `.livewire` to the new tag
and runs the tests. The dev copy's Lua must match the release first. Version
numbers, mod.info, the README and the zip are then done by hand.

Once a Live Wire release has the coupling extension point (`LW_Coupling.lua`),
the check says so, runs the 2.0 build's tests with it, and `--merge` refuses to
merge (exit 2): the release is replaced by the 2.0 build instead, see
[its checklist](batman_LiveWireCoupling_v2/RELEASE.md). For a 2.0 release the
check makes sure Live Wire still has the extension point at the version the
add-on is written for.

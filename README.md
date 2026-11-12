# PZ_Mods

Project Zomboid mods, targeting **Build 42** (the server runs 42.21.0).

## What's here

| Folder | What it is |
|---|---|
| [`batman_LiveWireCoupling/`](batman_LiveWireCoupling) | **LiveWire: Coupled Inverter Zones**, the released add-on for [LiveWire](https://github.com/cyberbobjr/LiveWire). Same files as the [Steam Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3830945476); [its README](batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling/README.md) lists every change. |
| [`batman_LiveWireCoupling_dev/`](batman_LiveWireCoupling_dev) | Dev copy for the next version (mod id `batman_LiveWireCoupling_dev`); same as the release until new work starts. Not for use. |
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

To check the add-on against LiveWire's beta branch (the daily beta watch does
this), also clone it:

```bash
git clone --branch beta https://github.com/cyberbobjr/LiveWire .livewire-beta
```

and point the runner at it:

```bash
git -C .livewire-beta pull && .venv/bin/python tests/run_tests.py batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling/42.21/media/lua --livewire .livewire-beta/Contents/mods/batman_LiveWire/42.21/media/lua
```

Then run every test against the release, or the dev copy's `media/lua` folder:

```bash
.venv/bin/python tests/run_tests.py batman_LiveWireCoupling/Contents/mods/batman_LiveWireCoupling/42.21/media/lua
```

Name test files after the folder to run only those, and add
`--livewire <folder>` to test against another Live Wire `media/lua` folder.

## When LiveWire updates

Since 2.0.0 the add-on replaces no LiveWire files: it registers with LiveWire's
coupling extension point (`LW_Coupling.lua`) and reads LiveWire through
`LiveWire.API`. Check a new LiveWire release with:

```bash
python3 tools/livewire_update.py
```

It compares the latest LiveWire tag with the version the release is built on
("Made for LiveWire X.Y.Z" in mod.info): whether the extension point is still
there at the version the add-on is written for, whether `LiveWire.API` still
has what the add-on calls, and the offline tests run with the new version.
Exit status 0 means nothing to do. If it needs work, make the change in the dev
copy, test it, then fold it into the release.

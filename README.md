# PZ_Mods

Project Zomboid mods, targeting **Build 42** (the server runs 42.21.0).

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

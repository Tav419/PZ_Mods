# Add-on 2.0.0: status and release checklist

## Status (2026-11-10)

- **batman-fr's release: moved to 2026-11-11** (Live Wire and LiveWire
  Extended; he said on 2026-11-10 at 16:00 UTC he had too much left to finish).
  He'll ping Josh with the time before publishing, so 2.0.0 goes out the same
  day. If the beta moves before then, pull it and rerun `tests/v2/`.
- **All of Josh's questions are answered in Live Wire itself** (beta commit
  2be1162, D-57): the inverter screen stays open near any inverter of the
  network, `Coupling.inverterById` finds the master at any distance, Live Wire
  drops the coupled zones at load when no add-on keeps them, and
  `LiveWire.API` revision 3 has what the add-on used Live Wire internals for.
- **Moved onto the API (2026-11-10).** `LWC_ScreenRange.lua` is gone (Live Wire
  does it), the `Menu.onShowRange` wrapper is replaced by `API.onRangeView`, and
  anchors, marks, distances and the range view go through `LiveWire.API`. Only
  `LiveWire.Config` (cable range, powered-area radius and floors) and
  `LiveWire.Coverage.hasDisc` (whether LiveWire Extended took the radius away,
  to hide "Show all powered areas") are still read directly: the API has no
  getter for those. The add-on refuses to register,
  with a console line, on an API older than revision 3.
- **Built and tested offline.** `tests/v2/` passes against Live Wire's beta
  branch (commit 2be1162): 168 checks, including Live Wire's own linking,
  coupling, menu, API and range view code with the add-on registered.
- **Not tested in game.** The new Live Wire isn't on Steam yet.
- The current release, 1.4.0, **breaks with the beta**: its copied files lack
  functions the new Live Wire calls (the offline tests fail). 2.0.0 has to go
  out the same day as the Live Wire release.

## What 2.0.0 is

The same features as 1.4.0, without replacing any Live Wire file:

| 1.4.0 | 2.0.0 |
|---|---|
| 8 modified copies of Live Wire files | none: Live Wire does it once the add-on registers |
| wraps `Install.checkCouple` to swap the cable range | hands Live Wire the coupling range (`range`) |
| "Show all powered areas" added in the copied menu file | added through Live Wire's menu hook (`menu`) |
| `LWC_ScreenRange` keeps the far master's screen open | removed: Live Wire does it |
| wraps `Menu.onShowRange`, reads `Anchor`/`RangeView`/`Marks` | `LiveWire.API` revision 3 (`onRangeView`, `anchors`, `hideRange`...) |
| "uncouple everything before removing the add-on" | not needed: Live Wire cleans up at load |
| `LWC_ZonesView`, the sandbox option | kept |

The mod id, the sandbox option (`LiveWireCoupling.CouplingRange`) and the save
data stay the same, so servers keep their `Mods=` line and their range setting,
and coupled inverters keep their zones in existing saves.

## Keep it current while waiting

Whenever the beta moves (the daily beta watch reports it):

```bash
git -C .livewire-beta pull
```

```bash
.venv/bin/python tests/run_tests.py batman_LiveWireCoupling_v2/Contents/mods/batman_LiveWireCoupling_v2/42.21/media/lua
```

Also re-read `shared/LiveWire/LW_Coupling.lua` and the places that call it
(`grep -rn "Coupling\." .livewire-beta/Contents/mods/batman_LiveWire`).

## Release day

Live Wire's new version shows up on Steam. The server's auto-update holds the
restart (`LIVE WIRE CHECK ... HOLD`), and its check logs `ADD-ON NEEDS AN UPDATE`
then `DEV BUILD NOT MADE (... has the coupling extension point ...)`. That's
expected: it means "release 2.0.0".

1. **Check the release.** `python3 tools/livewire_update.py` must say the new tag
   has the coupling extension point, version 1, `LiveWire.API` revision 3 or
   newer, and the 2.0 build's tests PASS.
   Diff the release tag against the beta commit tested here, for anything
   coupling-related that changed.
2. **Fold 2.0 into the release folder** (`batman_LiveWireCoupling/`):
   - Replace the Lua under `42.21/media/lua/` with the 2.0 build's (this deletes
     the 8 copies under `client/LiveWire/` and `server/LiveWire/`). Keep
     `sandbox-options.txt` and `Translate/EN/Sandbox.json`.
   - `mod.info`: name and id of the release (`batman_LiveWireCoupling`), the
     description's "Official add-on for Live Wire, made by Tav419" kept,
     `modversion=2.0.0`, description with "Made for Live Wire X.Y.Z" (the new
     version; the update check reads it).
   - `README.md`: the 2.0 build's, with the Live Wire version filled in.
   - Tests: move `tests/v2/*` to `tests/`, delete the old ones and the v2 rule in
     `run_tests.py`; check `.livewire` out at the new tag; run the tests.
   - Zip into `dist/` for Josh's PC.
3. **Josh tests in solo** with the new Live Wire from Steam: the test list below.
4. **Josh uploads** the new preview image (with the "Official add-on" ribbon,
   approved by batman-fr 2026-11-10) and the mod to Workshop item 3830945476 from his PC folder
   (`C:\Users\jdshr\Zomboid\Workshop\LiveWireCoupling\`), keeping his
   `workshop.txt` (its `id=` line keeps it the same item) and Public visibility.
   Update the Steam description (draft below).
5. **Server** (rules in `~/pzserver/CLAUDE.md`): check who's online, back up
   the save and config, allow the held Live Wire with
   `echo <version> > ~/.pzserver-livewire-allow` (Josh's OK), restart, and
   check that the server downloaded 2.0.0 and it matches the repo. The console
   must log `[LiveWireCoupling] registered with Live Wire's coupling extension
   point` and `[LiveWire] version X, registry ready`, with no new errors, and
   no `dropped the zone of N coupled inverter(s)` line (that would mean the
   add-on didn't register).
6. **Post in batman-fr's Live Wire Discord**, where many subscribers found the
   add-on (draft below).
7. Commit, push, tell batman-fr it's live.

### Discord post (draft)

```
Live Wire: Coupled Inverter Zones 2.0, now an official Live Wire add-on, is up for the new Live Wire X.Y.Z. If you use it and see errors after the Live Wire update, make sure Steam has updated the add-on to 2.0 (restart the game or server after it updates). Same features and settings, and existing saves keep their coupled areas. https://steamcommunity.com/sharedfiles/filedetails/?id=3830945476
```

### In-game test list

- An existing save from 1.4.0 loads; its coupled inverters still power their
  own zones.
- Couple two inverters 60+ tiles apart (Coupling range 70): the coupled one
  powers its own zone.
- Switch the master off and on: the coupled zones follow.
- The master's screen shows the combined load; an appliance where two zones
  overlap is counted once.
- The breaker panel's circuits and the computer's load shedding reach the
  coupled zones.
- Open the master's screen from a far coupled inverter; it stays open, and I/O
  and Reset work from there.
- "Show range" on a coupled inverter; "Show all powered areas" from the master
  and from a coupled inverter; each replaces the other.
- Pick up a coupled inverter, then a master: zones switch off, circles go
  away, the freed slave becomes independent.
- On a copy of a solo save: disable the add-on and load: the coupled
  inverters' own areas are off (console: `dropped the zone of N coupled
  inverter(s)`). Enable it again: the areas come back.
- With LiveWire Extended enabled too: no errors, coupling still works, and
  "Show all powered areas" is not in the inverter menu.
- Multiplayer: the same on the server with a second player.

## Steam Workshop description (draft for 2.0.0)

```
[h1]Live Wire: Coupled Inverter Zones[/h1]

An [b]official add-on[/b] for [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3821807453]Live Wire – Electrical Skill Overhaul[/url] by batman-fr. Requires Live Wire X.Y.Z or newer.

In Live Wire, coupling an inverter to another one only adds capacity: the coupled inverter loses its own powered area. With this add-on, every coupled inverter keeps its own powered area, while the whole network shares one load and one capacity. Works with the inverter cabinet too.

[h2]Features[/h2]
[list]
[*]Coupled inverters keep their own powered area. Billing, breakers, the management computer and the master's screen cover every area of the network.
[*][b]Show all powered areas[/b]: right-click any inverter to see the whole network's areas at once.
[*][b]Coupling range[/b] sandbox option (own page): couple inverters up to 70 tiles apart. 0 = Live Wire's cable range.
[*]The master's screen works from any coupled inverter, even a far one.
[/list]

[h2]New in 2.0.0[/h2]
The add-on no longer replaces any Live Wire file. It plugs into the coupling extension point batman-fr added to Live Wire, so Live Wire updates no longer break it. Same features, same settings, existing saves keep their coupled areas.

[h2]With LiveWire Extended[/h2]
Works alongside it. Extended takes the radius away from every inverter (power only reaches connected buildings and terminal zones), so coupled inverters keeping their own area changes nothing there, and "Show all powered areas" is not offered. The coupling range and the shared load and capacity still apply.

[h2]Server setup[/h2]
Add [b]batman_LiveWireCoupling[/b] to Mods= after batman_LiveWire. Set the Coupling range on the sandbox page "Live Wire: Coupled Inverter Zones".

[h2]Removing the add-on[/h2]
Nothing to do first: Live Wire switches off the coupled inverters' extra powered areas when a save loads without the add-on.

[h2]Credits[/h2]
Live Wire is by batman-fr (cyberbobjr on GitHub), MIT license. This add-on is made by Tav419 and is an official Live Wire add-on, with batman-fr's blessing. Thanks to batman-fr for building the coupling extension point that 2.0 runs on. Please report add-on issues here, not to batman-fr. Source: https://github.com/Tav419/PZ_Mods
```

Fill in the Live Wire version, and check the GitHub link before posting.

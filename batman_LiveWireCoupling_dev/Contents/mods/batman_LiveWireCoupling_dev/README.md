# Live Wire: Coupled Inverter Zones (DEV)

**Test build.** Mod id `batman_LiveWireCoupling_dev`. It is the released add-on
(`batman_LiveWireCoupling` 1.2.0) updated for Live Wire 1.7.0. Enable this OR
the released add-on, never both: they replace the same Live Wire files.

## New in this build: updated for Live Wire 1.7.0

The add-on's copies of Live Wire's files were made from Live Wire 1.6.4. With
Live Wire 1.7.0 they caused an error when opening the management software
(`__le not defined` in `LW_Simulation.lua`), and they replaced 1.7.0's fixes in
those files with the older code.

In this build, the add-on's changes are applied on top of Live Wire 1.7.0's
files instead. Nothing changes in how coupling, "Show all powered areas" or
"Coupling range" work.

- 6 of the 8 replaced files changed in 1.7.0 and are rebuilt from it:
  `LW_Registry`, `LW_Devices`, `LW_Simulation`, `LW_Commands`, `LW_Circuits`,
  `LW_Computer`. `LW_Demand` and `LW_ContextMenu` did not change in 1.7.0.
- The management software, the inverter screen and load shedding no longer
  error (1.7.0 removed the Electrical level needed for load shedding).
- Live Wire 1.7.0's fixes now apply with the add-on too, including: a coupled
  inverter cabinet's capacity, idle use and wear by its own model; switches no
  longer making time run faster; the pump check when resetting a tripped
  inverter; the circuits error when driving away from a base.
- The new inverter cabinet (4,500 W) can be coupled like an inverter and keeps
  its own powered zone.
- Resetting or switching a master back on checks the whole network's demand,
  using 1.7.0's new check (which now counts the water pumps).
- Breaker commands for the slaves' zones use 1.7.0's faster queue, like the
  master's.

---


An unofficial add-on for **Live Wire – Electrical Skill Overhaul** by batman-fr
(cyberbobjr on GitHub), which is the original work:
https://steamcommunity.com/sharedfiles/filedetails/?id=3821807453

This add-on requires Live Wire (`require=batman_LiveWire`) and replaces some of
its files with modified copies.

## What it changes

In Live Wire, coupling an inverter to another one only adds capacity: the coupled
(slave) inverter loses its own powered zone. With this add-on, a coupled inverter
keeps its own zone, while the whole network still shares one load and one capacity.

Replaced files, under `42.21/media/lua/`:

- `server/LiveWire/LW_Registry.lua`: coupling no longer deletes the slave's anchor;
  removing a slave deletes its anchor; slaves count when finding the panel that
  controls an appliance.
- `server/LiveWire/LW_Devices.lua`: picking up or destroying any inverter, coupled
  or not, switches its anchor off.
- `server/LiveWire/LW_Simulation.lua`: a master's in-service slaves follow its
  on/off state, each in its own zone; the network's demand is measured across all
  zones.
- `server/LiveWire/LW_Demand.lua`: slaves keep their own appliance inventory;
  inverters of the same network count each overlapping appliance only once; new
  `Demand.measureGrid` adds up the zones.
- `server/LiveWire/LW_Commands.lua`: resetting a tripped inverter or wall breaker
  checks the whole network's demand.
- `server/LiveWire/LW_Circuits.lua`: the breaker panel's circuits apply to the
  slaves' zones too.
- `server/LiveWire/LW_Computer.lua`: load shedding switches off lights in the
  slaves' zones too.
- `client/LiveWire/LW_ContextMenu.lua`: coupled inverters have "Show range", and
  every inverter has "Show all powered areas" (below); "Couple to an inverter"
  uses the coupling range (below).

Added files, under `42.21/media/`:

- `lua/client/LiveWireCoupling/LWC_ZonesView.lua`: "Show all powered areas".
- `lua/shared/LiveWireCoupling/LWC_CouplingRange.lua`: makes Live Wire's
  coupling check use the coupling range (it wraps `Install.checkCouple`, so
  `LW_Install.lua` is not replaced) and finds far inverters through Live
  Wire's anchor table.
- `sandbox-options.txt`: the "Coupling range" option.
- `lua/shared/Translate/EN/Sandbox.json`: the option's page title, name and
  tooltip (other languages show the English text). It adds to Live Wire's
  sandbox texts; it does not replace them.

The breaker panel, the management computer (load shedding) and "Show range" now
cover coupled inverters too.

## Show all powered areas

Right-click any inverter, then Live Wire > the inverter > **Show all powered
areas**. It draws the powered area of every inverter coupled into the same
network (the master and its slaves) at once, with a cross on each inverter.
Where areas overlap, the inner arcs are faint, so the outer edge of the whole
network stands out. Click it again (**Hide all powered areas**) to hide it.
"Show range" still shows one inverter's area, and each view replaces the other.
The view hides itself when you walk more than 60 tiles from every inverter.
Only you see the circles you open.

A circle also goes away about half a second after its inverter is picked up,
salvaged or destroyed. That fix covers Live Wire's own "Show range" circle too,
which otherwise stays on screen after its inverter is gone (only the drawing
stayed: the inverter's power was already switched off).

## Coupling range

A sandbox option, on its own page **Live Wire: Coupled Inverter Zones**:
**Coupling range (0 = same as Cable range)**, the farthest a coupled (slave)
inverter can be from its master, 0 to 70 tiles, measured in a straight line.
0 (the default) keeps Live Wire's behaviour: the same as "Cable range" on the
Live Wire page. The cable range for equipment (lights, appliances,
batteries...) does not change.

- Coupling still needs the coupling kit, and wire for the distance as set by
  "Tiles per electric wire" (1 wire per 4 tiles by default), so a longer
  coupling takes more wire.
- Live Wire's other coupling rules stay: up to 3 slaves per master, the floor
  limit of "Cable vertical range", the Electrical level.
- The master must be loaded when you couple: your game keeps about 70 tiles
  loaded around you on a 1080p screen, less on smaller screens (about 48 tiles
  at 1366x768). A master farther than that is not listed. With no master in
  reach, the menu says "No inverter within the coupling range (N tiles)".
- A coupled inverter's menu shows how far its master is, even past the cable
  range, and "Show all powered areas" finds the whole network at any distance.
- Lowering the option later does not uncouple inverters already coupled.
- Tested on a dedicated server: couplings at 39, 63 and 69 tiles, with the
  slaves following the master on and off.

## Before disabling or removing this add-on

Uncouple all slave inverters first. The original mod doesn't clean up the extra
powered zones afterwards, so they could stay powered.

## Updates to Live Wire

This add-on's copies are built on Live Wire 1.7.0. If the original Live Wire mod
is updated, this add-on's changes have to be re-applied on top of the new files.

## Version history

- 1.3.0: updated for Live Wire 1.7.0 (fixes the management software error,
  keeps Live Wire 1.7.0's fixes, works with the inverter cabinet).
- 1.2.0: "Coupling range" sandbox option, to couple inverters farther apart
  than the cable range (up to 70 tiles).
- 1.1.0: "Show all powered areas" for inverters; circles of removed inverters
  go away (including Live Wire's "Show range" circle).
- 1.0.0: coupled inverters keep their own powered zone.

## Credits and license

This add-on contains modified copies of files from Live Wire by batman-fr
(cyberbobjr on GitHub), original repo: https://github.com/cyberbobjr/LiveWire,
Workshop ID 3821807453, used under the MIT license. The full license text is in
the `LICENSE` file.

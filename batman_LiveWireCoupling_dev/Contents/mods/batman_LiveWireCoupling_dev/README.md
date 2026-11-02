# Live Wire: Coupled Inverter Zones (DEV)

**Test build.** Mod id `batman_LiveWireCoupling_dev`. It is the released add-on
(`batman_LiveWireCoupling` 1.0.0) plus the feature below. Enable this OR the
released add-on, never both: they replace the same Live Wire files.

## New in this build: "Show all powered areas"

Right-click any inverter, then Live Wire > the inverter > **Show all powered
areas**. It draws the powered area of every inverter coupled into the same
network (the master and its slaves) at once, with a cross on each inverter.
Where areas overlap, the inner arcs are faint, so the outer edge of the whole
network stands out. Click it again (**Hide all powered areas**) to hide it.
"Show range" still shows one inverter's area, and each view replaces the other.
The view hides itself when you walk more than 60 tiles from every inverter.

A circle also goes away about half a second after its inverter is picked up,
salvaged or destroyed. That fix covers Live Wire's own "Show range" circle too,
which otherwise stays on screen after its inverter is gone (only the drawing
stayed: the inverter's power was already switched off).

Added file: `42.21/media/lua/client/LiveWireCoupling/LWC_ZonesView.lua`.
Changed: `client/LiveWire/LW_ContextMenu.lua` (the menu option).

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
- `client/LiveWire/LW_ContextMenu.lua`: coupled inverters have "Show range".

The breaker panel, the management computer (load shedding) and "Show range" now
cover coupled inverters too.

## Before disabling or removing this add-on

Uncouple all slave inverters first. The original mod doesn't clean up the extra
powered zones afterwards, so they could stay powered.

## Updates to Live Wire

If the original Live Wire mod is updated, this add-on's copies of these files may
need to be re-applied.

## Credits and license

This add-on contains modified copies of files from Live Wire by batman-fr
(cyberbobjr on GitHub), original repo: https://github.com/cyberbobjr/LiveWire,
Workshop ID 3821807453, used under the MIT license. The full license text is in
the `LICENSE` file.

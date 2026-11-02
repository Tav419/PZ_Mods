# Live Wire: Coupled Inverter Zones

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

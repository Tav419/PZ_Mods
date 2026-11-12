# LiveWire: Coupled Inverter Zones

An official add-on for **LiveWire - Electrical Skill Overhaul** by batman-fr
(cyberbobjr on GitHub), which is the original work. The add-on is made by
Tav419; batman-fr made it an official LiveWire add-on in November 2026.
LiveWire:
https://steamcommunity.com/sharedfiles/filedetails/?id=3821807453

This add-on requires LiveWire (`require=batman_LiveWire`). Since version 2.0.0
it replaces no LiveWire files: it plugs into LiveWire's coupling extension
point (`LiveWire.Coupling`), which batman-fr added for it, and reads LiveWire
through its public API (`LiveWire.API`, revision 3 or newer). It needs
LiveWire 2.0.0 or newer (made for LiveWire 2.0.0).

## What it changes

In LiveWire, coupling an inverter to another one only adds capacity: the coupled
(slave) inverter loses its own powered zone. With this add-on, a coupled inverter
keeps its own zone, while the whole network still shares one load and one capacity.
It works the same with LiveWire's inverter cabinet: a coupled cabinet keeps its own
zone, and the network's capacity adds up each inverter's own rating.

Once the add-on is registered, LiveWire itself handles every zone of the network:
billing (the load of all zones, each appliance counted once where zones overlap),
the breaker panel's circuits, the management computer's load shedding, coupled
inverters switching on and off with their master, "Show range" on a coupled
inverter, and the master's screen opened from a coupled inverter (it stays open
near any inverter of the network).

The add-on's files, under `42.21/media/`:

- `lua/shared/LiveWireCoupling/LWC_Register.lua`: registers with LiveWire's
  coupling extension point (coupled inverters keep their zone, the coupling
  range, the far inverter search, the menu option below). It writes one line to
  the console: `[LiveWireCoupling] registered ...`, or why it could not.
- `lua/shared/LiveWireCoupling/LWC_CouplingRange.lua`: the coupling range
  (below) and the search for inverters past the cable range, through LiveWire's
  anchor table.
- `lua/client/LiveWireCoupling/LWC_ZonesView.lua`: "Show all powered areas".
- `sandbox-options.txt`: the "Coupling range" option.
- `lua/shared/Translate/EN/Sandbox.json`: the option's page title, name and
  tooltip (other languages show the English text). It adds to LiveWire's
  sandbox texts; it does not replace them.

## Show all powered areas

Right-click any inverter, then LiveWire > the inverter > **Show all powered
areas**. It draws the powered area of every inverter coupled into the same
network (the master and its slaves) at once, with a cross on each inverter.
Where areas overlap, the inner arcs are faint, so the outer edge of the whole
network stands out. Click it again (**Hide all powered areas**) to hide it.
"Show range" still shows one inverter's area, and each view replaces the other.
The view hides itself when you walk more than 60 tiles from every inverter.
Only you see the circles you open.

A circle also goes away about half a second after its inverter is picked up,
salvaged or destroyed. Since 2.0.0, LiveWire does the same for its own "Show
range" circle.

## Coupling range

A sandbox option, on its own page **LiveWire: Coupled Inverter Zones**:
**Coupling range (0 = same as Cable range)**, the farthest a coupled (slave)
inverter can be from its master, 0 to 70 tiles, measured in a straight line.
0 (the default) keeps LiveWire's behaviour: the same as "Cable range" on the
LiveWire page. The cable range for equipment (lights, appliances,
batteries...) does not change.

- Coupling still needs the coupling kit, and wire for the distance as set by
  "Tiles per electric wire" (1 wire per 4 tiles by default), so a longer
  coupling takes more wire.
- LiveWire's other coupling rules stay: up to 3 slaves per master, the floor
  limit of "Cable vertical range", the Electrical level.
- The master must be loaded when you couple: your game keeps about 70 tiles
  loaded around you on a 1080p screen, less on smaller screens (about 48 tiles
  at 1366x768). A master farther than that is not listed. With no master in
  reach, the menu says "No inverter within N tiles".
- A coupled inverter's menu shows how far its master is, even past the
  coupling range (the option was lowered after coupling), as long as the
  master is loaded. "Show all powered areas" finds the whole network at any
  distance.
- Lowering the option later does not uncouple inverters already coupled.

## Inverter screen

Clicking a coupled inverter opens its master's screen, which shows the whole
network. The screen stays open while you are within 30 tiles of any inverter of
the network, so it also works at a slave coupled far from its master. Its I/O and
Reset buttons work within 3 tiles of any inverter of the network. In multiplayer
the server checks the same distances, and safehouse rules still apply.

## With LiveWire Extended

LiveWire Extended (batman-fr's optional sub-mod) takes the radius away from every
inverter: power only reaches connected buildings and terminal zones. The add-on
works alongside it:

- A coupled inverter keeps its own connected buildings, terminals and breaker
  boards, like an independent one. Without the add-on, Extended doesn't let you
  connect a building to a coupled inverter. Coupled inverters still share one
  load and one capacity, and the coupling range still applies.
- "Show all powered areas" is not offered, since there are no circles to show
  (LiveWire's own "Show range" draws none either).

## Disabling or removing this add-on

Nothing to do first. When a save loads without the add-on, LiveWire switches
off the extra powered zones of coupled inverters (they share their master's
capacity again, as in plain LiveWire). If the add-on is enabled again later,
the zones come back.

## Version history

- 2.0.0 (for LiveWire 2.0.0): uses LiveWire's new coupling extension point instead of replacing 8
  LiveWire files, so LiveWire updates no longer break the add-on or undo
  batman-fr's fixes. Same features. Needs a LiveWire with the extension point.
  LiveWire now keeps the master's screen open near a far coupled inverter, and
  cleans up the coupled zones if the add-on is removed.
- 1.4.0: updated for LiveWire 1.7.2 (fixes the errors when linking equipment,
  a generator or a computer, and when coupling inverters).
- 1.3.0: updated for LiveWire 1.7.0 (fixes the management software error,
  keeps LiveWire 1.7.0's fixes, works with the inverter cabinet). The inverter
  screen opened from a far coupled inverter no longer closes at once.
- 1.2.0: "Coupling range" sandbox option, to couple inverters farther apart
  than the cable range (up to 70 tiles).
- 1.1.0: "Show all powered areas" for inverters; circles of removed inverters
  go away (including LiveWire's "Show range" circle).
- 1.0.0: coupled inverters keep their own powered zone.

## Credits and license

The coupled-zones logic that LiveWire now carries started as this add-on's
modified copies of LiveWire files; batman-fr moved it behind the coupling
extension point. Please report problems with the add-on on its own Workshop
page, not to batman-fr. LiveWire by batman-fr (cyberbobjr on GitHub), original repo:
https://github.com/cyberbobjr/LiveWire, Workshop ID 3821807453, MIT license.
The full license text is in the `LICENSE` file.

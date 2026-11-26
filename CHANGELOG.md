# Changelog

**English** · [Français](CHANGELOG.fr.md)

## Unreleased
- **Fixed-gear gearboxes (powershift, semi-powershift, manual boxes used in automatic).** Automatic downshift under load. When the engine stays under heavy load below the engine speed that keeps 85 % of peak power, FlowDrive asks for the lower gear if it gives more power and leaves room before the rev limit. An upshift is refused for 4 s after this downshift (no hunting).
- FlowDrive only acts when the game itself shifts the gears (gearbox setting on automatic, or a vehicle that cannot be shifted by hand). A player who shifts by hand is never touched.
- **Upshift guard.** The game accepts gears that give only 50 % of peak power and can jump several gears, so under load it climbs into a gear where the engine lugs, then goes back down. FlowDrive now refuses (or reduces) an upshift when the engine would carry more than 80 % load after it. It also stops asking for a downshift during the 3 s the game itself cancels it after an upshift.
- **Engine braking.** With the pedal released for 0.6 s above 6 km/h, the box downshifts when engine speed falls under 30 % of the range (up to 50 % with a heavy attached load), as long as the engine speed after the shift stays under 75 % of the range. The game only did it under 25 %.
- **Automatic gear groups (ranges).** Upshift of the group from the top gear at 90 % of the engine speed range (the game waits until 50 rpm below the maximum), in the gear that gives the most power, only if the engine keeps its load under 80 %. Downshift of the group when the engine struggles under load in the lowest gear. At least 4 s between two group changes.
- Three new general settings (menu, follow the host in multiplayer): downshift under load, engine braking, automatic groups.
- The on/off choice of the menu and the key now also exist on these vehicles; the menu tooltip shows the status. The other FlowDrive functions (ramps, ranges, PTO, boost...) are not available on fixed-gear boxes.
- One log line per vehicle at load (`boite : ...`) gives what the engine says about the gearbox and what FlowDrive does with it. With the measurement key (debug), each gear change is logged (`rapports : ...`), the game's and FlowDrive's.

## 1.1.0.0
- **Multiplayer (experimental).** Per-vehicle settings (keys and menu) are sent to the server and to the other players, and to a player who joins the game.
- In multiplayer, the server computes the transmission. It sends the players what the display, DashboardLive and the messages need (auto ramp, active range, cold engine, boost, engine temperature, preheating).
- Inching and automatic hydraulic engine speed also work for a player who joined the game.
- Hydraulics, preheating and cold protection follow the host's settings (greyed out in the menu for the other players).
- Messages are only shown to the player sitting in the vehicle (no more messages from an AI worker's vehicle).
- In multiplayer, log lines show the role: `[FlowDrive][hote]`, `[FlowDrive][serveur]` or `[FlowDrive][joueur]`. Unchanged in single player.

## 1.0.2.0
- The menu shows the vehicle's power in the game on the "Game power (… hp)" row, to compare it with the real spec sheet and choose the boost.
- Boost tooltips updated (real boosts: 5 to 20 %).
- Code comments in English. No change in behaviour.

## 1.0.1.0
- Preheating no longer starts when getting into a cold vehicle. It starts when the start key (Enter) is pressed, then the engine starts. It starts on entering only when the game's automatic motor start option is on.
- Fix: in 1.0.0, the engine could start by itself after preheating, without the key being pressed.

## 1.0.0.0
- Final title and description.
- Only the menu keeps a default key (`Left Shift + Left Alt + T`). The measurement panel and the cold test can be bound in the controls menu.

## 0.8.0
- Boost off by default on every vehicle.
- Boost percentage typed in (1 to 30, 0 = off).
- New "Game power" setting: boost included or added.
- **Auto** ramp by default: the ramp follows the work, the load and the vehicle type.

## 0.7.0
- Compatibility checked with ADS, Courseplay, EngineBrakeforceCompensation and DashboardLive.
- Range change refused above 10 km/h.

## 0.6.x
- Settings menu, on-screen display, DashboardLive screens, French and English texts.
- Fuel consumption measurement fixed.

## 0.5.0
- Preheating, cold engine protection, ADS temperature, cold test mode.

## 0.4.x
- Harvesters: harvest and road ranges, automatic crop flow.

## 0.3.x
- Loaders, telehandlers and self-propelled machines (HST profile), hydraulic engine speed, inching.

## 0.2.x
- Eco PTO, engine speed memories, boost.

## 0.1.x
- Tractor CVT: ramps, eco engine speed, load limit, field range, engine braking.

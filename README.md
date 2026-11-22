# FlowDrive

**English** · [Français](README.fr.md)

A mod for **Farming Simulator 25** that gives continuously variable (CVT) and hydrostatic (HST) transmissions realistic behaviour. It works on every eligible vehicle, with nothing to buy or configure.

- Website and boost assistant: **https://dev-velris.github.io/FlowDrive/**
- Version: **1.1.0.0** ([changelog](CHANGELOG.md))
- Single player and **multiplayer (experimental since 1.1)**. In multiplayer, the server computes the transmission; hydraulics, preheating and cold protection follow the host's settings. Please [report any problem](https://github.com/DEV-Velris/FlowDrive/issues/new/choose).
- **Do not use together with CVT Addon.** Both change the same things. When CVT Addon is active on a vehicle, FlowDrive does nothing on it.

## What it does

| Vehicles | Features |
|---|---|
| Tractors (CVT) | Acceleration ramps (Auto or 1 to 4); eco engine speed; load limit; field and road ranges; engine braking adapted to the attached weight; eco PTO; engine speed memories; adjustable boost |
| Loaders, telehandlers, self-propelled machines (HST) | Automatic hydraulic engine speed when a cylinder moves; work range; inching |
| Harvesters | Harvest and road ranges (harvest range automatic while threshing); automatic crop flow (speed drops when the engine is overloaded) |
| All | Preheating on the start key in cold weather; cold engine protection; DashboardLive screens that used to read CVT Addon |

Manual gearboxes, electric vehicles and locomotives stay with the game.

How it works in detail: [docs/FONCTIONNEMENT.md](docs/FONCTIONNEMENT.md) (in French).

## Settings

- **FlowDrive menu: `Left Shift + Left Alt + T`**, inside the vehicle. Per vehicle: on/off, ramp, range, eco PTO, engine speed memory, boost, game power (boost included or added) and crop flow. It also holds the general settings: hydraulics, preheating, cold protection, display, DashboardLive.
- The other functions have no default key. Bind them in *Options → Controls* ("FlowDrive: …" lines):
  - next ramp;
  - next range;
  - eco PTO;
  - engine speed memory (off / 1 / 2), + and −;
  - boost;
  - crop flow;
  - inching (hold the key);
  - on / off;
  - measurement panel;
  - cold test.

Per-vehicle settings are stored in the savegame. General settings go to `modSettings/FS25_FlowDrive.xml`.

## Which boost to set?

The boost is **off by default**. The menu shows the vehicle's power in the game on the "Game power (… hp)" row. Compare it with the real tractor's spec sheet. The decision rule is in [docs/BOOST.md](docs/BOOST.md) (in French). The [boost assistant](https://dev-velris.github.io/FlowDrive/#boost) prepares the question for an AI (Google AI Mode, ChatGPT, Claude, Perplexity) from the brand, the model and the game power.

## Tested compatibility

- Advanced Damage System (stable and beta): FlowDrive uses its engine temperature.
- Courseplay: FlowDrive also applies to AI workers.
- DashboardLive.
- EngineBrakeforceCompensation.
- ValtraPackage.

## Repository content

| Folder | Content |
|---|---|
| `FS25_FlowDrive/` | the mod, as it is zipped |
| `docs/` | website (`index.html`, published with GitHub Pages), detailed behaviour, boost guide (in French) |
| `tools/` | `build.ps1` (builds the zip), `luacheck_blocks.js` (checks the structure of the Lua files) |
| `.github/` | bug report forms (French and English) |

## Building the zip

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

The script checks the Lua files (when Node.js is installed). It then creates `dist/FS25_FlowDrive.zip` and a numbered copy `dist/FS25_FlowDrive_<version>.zip`. To install, copy `FS25_FlowDrive.zip` into the `mods` folder **with the game closed**. Do not rename the zip: the game identifies a mod by this name.

## Report a problem

Open an issue with the **[Report a problem](https://github.com/DEV-Velris/FlowDrive/issues/new/choose)** form (French or English). Attach the `log.txt` file from `Documents\My Games\FarmingSimulator2025\`, copied **before restarting the game** (it is erased at every start). In multiplayer, attach the host's log and the log of the player who saw the problem.

## Licence

FlowDrive is free software, under the [GNU General Public License v3.0](LICENSE). You may use, modify and share it, provided you credit the author, keep the same licence and publish the source code of your changes.

## Author

Velris

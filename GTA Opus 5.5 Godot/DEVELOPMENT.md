# Vesper Bay — Godot GTA-style sandbox (Claude Opus 5.5 benchmark)

Original, mission-free open-world sandbox on a compact ~600 × 600 m island. No missions, story or quests:
free roam, vehicles, combat, police, services and activities only.

| Item | Value |
|---|---|
| Engine | **Godot 4.7.2.stable.official.ed1daf0bf** |
| Renderer | **Forward+** on D3D12 (`rendering_device/driver.windows="d3d12"`) |
| Physics | Jolt Physics (project default) |
| Language | GDScript only (≈17 k lines under `gta/code/`) |
| Main scene | `res://gta/scenes/bootstrap/main.tscn` (autoloads `Game`, `Audio`, `VFX`) |
| Blender | 5.2.2 LTS, master file `GodotOpus5.5GTA.blend` |

## Run

* Editor: open the folder in Godot 4.7.2 and press **F5** (main scene is configured).
* Direct: `godot --path .`
* Headless import/parse check: `Godot_…_console.exe --headless --editor --path . --quit`
  (needed once after new GLBs are exported so `.godot/imported` is refreshed).
* Automated in-game validation (real input actions + screenshots + JSON report into
  `.opus-5.5-gta-runs/<run>/screens/`):
  `Godot_…_console.exe --path . --resolution 1600x900 -- --autotest=<scenario>`
  Scenarios: `basic`, `vehicles`, `combat`, `world`, `air` (includes boat, swimming, parachute), `views`,
  `systems`, `perf`, `characters`, `weapons`, `buildings`.
  The bare `--` matters: the game reads its own arguments through `OS.get_cmdline_user_args()`, which
  only sees what follows the separator. Without it the binary just free-roams and never starts a test.

## Build standalone Windows and macOS packages

```powershell
.\tools\build_release.ps1 -GodotPath "C:\path\to\Godot_console.exe"
```

```bash
GODOT=/path/to/godot tools/build_release.sh
```

* Output: `build/windows/VesperBay.exe` — **one self-contained file** (~112 MB) with the PCK embedded
  (`binary_format/embed_pck=true`). Copy it anywhere and double-click it; no other file needed.
* macOS output: `build/macos/VesperBay-macOS.zip`, containing a universal Apple Silicon + Intel app.
  It is ad-hoc signed but not Apple-notarized; see `RUN_MACOS.md` for the first-launch steps.
* The scripts regenerate `icon.ico` with `tools/make_icon.py` and export both presets from
  `export_presets.cfg`. The PowerShell script can also smoke-test the Windows binary.
* Godot stamps the icon and version strings into the PE during export; `rcedit` is not required.
* Export filters (`.md`, `*.blend`, run scratch, `*.sh`) are excluded, so no dev material ships inside
  the binary.
* Needs the **Godot 4.7.2 export templates**; the preset exports both D3D12 and Vulkan-capable binaries
  and the game keeps using D3D12 (`rendering_device/driver.windows="d3d12"`).
* Quirk: the packaged build can abort inside renderer teardown *after* the test has reported. Its exit
  code is therefore meaningless — read the `[AutoTest] DONE x/y` line, not `$?`.

## Controls (keyboard/mouse; gamepad mapped as well)

| Action | Key |
|---|---|
| Move / sprint / jump / crouch (stealth) | W A S D / Shift / Space / Ctrl or C |
| Aim / fire (melee when unarmed) | RMB / LMB |
| Reload / weapon wheel / next-prev weapon / slots | R / Tab (hold) / mouse wheel / 1–9 |
| Cover (snap to nearest cover, again to leave) | Q |
| Enter / exit / carjack vehicle | F |
| Interact (shops, safehouse, garage, POIs) | E |
| Camera view (3rd person near/far, 1st person) / look back | V / X |
| Vehicle: throttle/brake/steer, handbrake | W S A D, Space |
| Vehicle: horn / headlights / siren (emergency) / radio | H / L / G / `,` `.` |
| Helicopter: up / down / yaw / pitch & roll | Space / Ctrl / A D / W S + Q E |
| Plane: throttle up / down, pitch, roll, rudder | Shift / Ctrl, W S, A D, Q E |
| Phone (taxi, services) | ↑ or P |
| Big map + GPS waypoint | M |
| Pause / controls / save | Esc |
| **Admin / benchmark menu** | **F1** or `` ` `` |
| Quick save / quick load | F5 / F9 |
| Toggle HUD / photo mode screenshot | F2 / F12 |

## Architecture

```
res://gta/
  code/core        Game autoload (state, money, events, toggles), input map, constants, mesh builder MB,
                   material factory, util (pooled ray queries), pickups, main (bootstrap, teleport, spawns)
  code/world       WorldMap (layout data, heights, POIs), World (terrain, water, collision helpers),
                   RoadBuilder, CityBuilder (blocks/venues), Landmarks (airfield, docks, pier, beach, hill,
                   wreck, ramps), PropManager/PropLib (street furniture, MultiMesh), ModelLib (bakes Blender
                   building GLBs into the batched world meshes), EnvController (day/night, weather)
  code/player      Player state machine (foot, cover, climb/vault, swim/dive, skydive/parachute, vehicle),
                   CameraRig, Skills
  code/characters  Actor base (health, armour, damage, ragdoll, get-up), HumanoidRig (joint hierarchy,
                   procedural animation layers, two-bone aim IK, ragdoll builder, Blender kit parts)
  code/ai          NPC brains (civilians, police, SWAT, medics, gang, shop staff), PedManager + ped graph,
                   EmergencyServices, WildlifeManager + Animal
  code/vehicles    VehicleBase (RigidBody3D, raycast suspension, damage, dormancy), Car, Boat, Helicopter,
                   Plane, VehicleDB, VehicleMods, VehicleVisuals (procedural rig + Blender GLB swap),
                   GarageStorage
  code/traffic     RoadGraph (lanes, signalised junctions, 36 s cycle), AIDriver, TrafficManager, TaxiService
  code/police      WantedSystem (0–5 stars, witnesses, pursuit/search, LOS escape, busted),
                   PoliceDispatch (cars, helicopter, roadblocks, SWAT), SpikeStrip
  code/weapons     WeaponDB, WeaponUser (hitscan/pellets/projectiles/melee), Projectile, WeaponModels
  code/vfx         pooled particles/decals (muzzle, impacts, blood, explosions, smoke, fire, splashes)
  code/audio       procedural synthesiser + pooled 3D audio, radio stations
  code/ui          HUD, minimap + big map/GPS, weapon wheel, menus (pause, shops, garage, phone, admin)
  code/save        JSON save/load (user://vesperbay_save.json)
  code/debug       AutoTest scenarios
  generated/models Blender exports: props/, vehicles/, characters/, weapons/, buildings/, interiors/
  scenes/          bootstrap/main.tscn (+ folders reserved for sub-scenes)
  shaders/         building facades (windows, night lights), ground, road, terrain, water
```

Collision layers: 1 WORLD, 2 PLAYER, 3 NPC, 4 VEHICLE, 5 PROP, 6 TRIGGER, 7 PROJECTILE, 8 RAGDOLL.

### Render pipeline
Forward+ with ACES tonemapping, SSAO, glow, directional sun with shadows, procedural sky that follows the
day/night cycle and weather (clear, cloudy, rain, storm, fog), volumetric-looking distance fog, custom
shaders for facades (window grid with per-window night lighting, anti-aliased at distance), ground/road
markings, terrain and animated water. All albedo colours are authored in sRGB and converted (`to_lin`).

### Performance notes
* Static city geometry (blocks, landmarks, baked Blender buildings) is merged into a few large multi-surface
  meshes; props use MultiMesh.
* Unoccupied vehicles at rest go dormant (frozen static bodies, no per-tick work) and wake on contact,
  damage, nearby traffic or entry; light/material writes are cached; ray queries reuse one parameter object.
* Measured on the development machine (1600×900, all effects on, ~22 traffic cars, 30–55 pedestrians):
  65–109 fps in the `perf`/`systems` samples; heaviest remaining cost is NPC script/physics time.

## Scene / map layout (X/Z ∈ [-300, 300], north = −Z, sea level y = 0, land y = 1)

| District | Area | Content |
|---|---|---|
| Meridian (downtown) | x −70…90, z −130…80 | towers, shops, police HQ, plaza, parking, signalised junctions |
| Palm Terrace (residential) | x 90…290, z −60…150 | Blender houses, apartments, park, hospital, safehouse, gas station |
| Ironside (industrial) | x −300…−70, z −130…80 | warehouses, yards, mod garage, weapon shop + range |
| Lantern Pier / Coral Beach | z 150…300 | coastal highway, promenade, Ferris-wheel pier, docks with gantry cranes, marina, beach bar, lifeguard tower, lighthouse, offshore shipwreck (dive site) |
| Crown Hill | x 90…300, z −300…−60 | hill up to ~45 m, woods, lookout deck, radio mast, wildlife, stunt ramps |
| Vesper Airfield | x −300…90, z −300…−130 | runway, taxiway, apron, hangars, helipad |

## Blender asset workflow

1. **Connection check before every write session**: a read call on `custom-blender-godot-gta-opus55` prints
   `bpy.data.filepath` and `scene.blendermcp_port`; work proceeds only when the path is exactly
   the project-local `GodotOpus5.5GTA.blend` (port 9881). The add-on reports protocol 7
   (server expects 13); the add-on was **not** updated or patched — Safe Mode was kept.
2. **Backup**: `blender_backups/GodotOpus5.5GTA.original-20261003-1215.blend` (SHA-256 `2c4718…54e93`,
   identical to the master before the first change).
3. **Authoring**: every asset is built by a self-contained `bpy`/`bmesh` script (Safe Mode: no file I/O, no
   `sys`/`os`, no dynamic execution). Geometry is written in Godot coordinates (Y-up, front = −Z) and rotated
   into Blender space with one matrix, so dimensions in GDScript and Blender match after `export_yup`.
   Collection tree: `GTA_GODOT/{Characters, NPCs, Vehicles/{Cars, Motorcycles, Boats, Helicopters, Airplanes},
   Weapons, Buildings/Landmarks, StreetProps, Interiors, Nature, VFX_HelperMeshes, CollisionHelpers}`.
4. **Naming contract with Godot**: vehicles `<id>__Body`, `<id>__Mod_<key>_<value>`, `Steering`, `Rotor`,
   `TailRotor`, `Prop`; rim set `WHEEL_rim0..3`; character kits `M_<joint>` / `X_<joint>_<variant>`; weapons
   `<id>__Body` + `<id>__Muzzle`, attachments `ATT_<mod>`; buildings use materials named
   `<world surface>__<role>` so they can be baked and re-tinted.
5. **QA**: EEVEE renders from a dedicated `QA_Camera` (viewport screenshots did not refresh over MCP), then the
   same assets are checked in game with the autotest screenshots.
6. **Export**: glTF binary (`.glb`) per asset with `use_selection`, applied modifiers, Y-up, no animation,
   roots zeroed → `gta/generated/models/<category>/`. Godot imports them (`.import` files are committed).
7. **Godot integration**: gameplay data stays procedural (wheel pivots, seats, colliders, hit boxes), the
   Blender meshes replace the visuals with material remapping (paint/livery/tint/lights/rims, clothing and
   skin colours, weapon finishes). Static buildings are baked into the batched world meshes (`ModelLib`), so
   they add triangles but no draw calls. Missing GLBs fall back to the procedural builders.

Blender asset inventory (65 GLB files, ≈79 assets): 17 street props, 20 vehicles + 4-style rim set, male and
female character kits (35 parts each: body segments, hair/beard/hat/glasses variants, jacket/hood/vest/badge/
skirt overlays), 14 weapons + 6 attachments, 2 house types, gas station, lighthouse, lifeguard tower, radio
mast, gantry crane, beach bar, shipwreck and a 10-piece safehouse furniture set.

## Known limitations

* Characters use a joint hierarchy with procedural animation (no Skeleton3D / skinned meshes); faces are
  stylised blocks.
* Downtown towers, apartments, warehouses and the enterable safehouse shell remain procedural (shader-driven
  facades); only the house types, gas station and landmarks are Blender models.
* Car door seams are modelled straight through the wheel-arch area (cosmetic).
* Physics-interpolation warning when the autotests move the camera from outside physics (benign); Jolt
  reports leaked shape RIDs only at process exit.
* See `FEATURE_MATRIX.md` for the per-feature status and `OPUS_5.5_FINAL_REPORT.md` for the final report.

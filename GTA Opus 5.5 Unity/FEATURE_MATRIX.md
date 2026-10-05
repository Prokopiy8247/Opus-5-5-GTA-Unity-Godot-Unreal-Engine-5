# FEATURE MATRIX — Port Halcyon (Unity 6000.6.0f1, URP)

Status values: `WORKING` · `PARTIAL` · `NOT IMPLEMENTED`.
**WORKING** = has a functional in-game path **and** was exercised in the Windows build by the `-autotest` validation run
(check names in brackets, log `QA/Game/run7/autotest_log.txt`), unless the note says "code-reviewed only".
**PARTIAL** = reachable in game but simplified, missing sub-features, or not verified at runtime.
Evidence for everything below comes from the built player, not from the editor.
Final full run (run7): **57 PASS / 0 FAIL** of 57 checks. The shipped build differs from the run7 build only by the
"never wanted" fix and was re-checked with the weapons/police/damage/busted subset (run7b: 14/14). Earlier runs and the
bugs they exposed are kept in `QA/Game/run1…run6`.

## Core, world, presentation

| Feature | Status | Notes |
|---|---|---|
| Launch straight into free roam, no missions/quests/markers | WORKING | [boot.*] Player spawns at the Palm Row safehouse; there is no mission, quest or objective code anywhere (code audit) |
| Compact map ~600×600 m, 7 districts, sea around | WORKING | [world.districts] 11 landmarks visited; downtown, residential, industrial, docks/beach, hill, airfield, highway loop |
| Road network, intersections, arterial/highway loop | WORKING | 111 segments, coastal highway + airfield ring + 60 m grid, 214 traffic-light props |
| Day/night cycle | WORKING | [world.time_weather] 24-min day, sun/moon, sky, street lamps (nearest 56 lit), emissive windows/neon at night |
| Weather (clear/cloudy/rain/fog/storm) | WORKING | [world.time_weather] fog/rain shots; wet grip; rain particles fixed (were magenta in build); no thunder sound |
| HUD (health, armour, breath, ammo, cash, clock, stars, status) | WORKING | Visible in every autotest frame |
| Minimap (player arrow, landmarks, police, waypoint) | WORKING | Police dots moved into the minimap and player arrow added in segment 5 |
| Full map + waypoint | WORKING | [ui.map] click sets a waypoint, shown on the minimap; **no GPS route line** |
| Crosshair | WORKING | Added in segment 5; follows the real aim point |
| Admin / benchmark menu (F1) | WORKING | [ui.admin_menu] teleports, vehicle/weapon spawners, wanted 0–5, police squads, time/weather, toggles (traffic, peds, wildlife, deformation, invulnerability, never wanted), FPS + coordinates readout, save/load |
| Pause menu, settings, controls list | WORKING | [ui.pause] settings are not persisted between launches |
| Phone (services, taxi, garage, waypoints) | WORKING | [ui.phone] |
| Save / load | WORKING | [save.load_roundtrip] position, health, money, weapons/ammo, skills, gear, garage, outfit, time, weather, wanted. Not saved: attachments, cars left in the world |
| Performance for recording | WORKING | Full autotest run at 1600×900 on an RTX 5070: average 166 FPS, lowest 0.5 s window 104 FPS, no frame over 120 ms logged |
| Procedural audio (guns, engines, rotors, sirens, horns, ambience) | PARTIAL | ~47 synthesised sounds, plays in the build; quality not reviewed by listening. Some generated clips (ocean, city) are never played |
| Radio stations | PARTIAL | Off + 4 stations; two stations share a track |

## Player

| Feature | Status | Notes |
|---|---|---|
| Third-person walk / run / sprint / jump | WORKING | [player.walk_sprint_jump] 8.3 m / 13.5 m per 2 s, 0.8 m jump |
| Crouch / stealth | WORKING | [player.stealth_crouch] crouch halves NPC sight range/FOV and footstep noise; officers hear footsteps |
| Stealth takedown | PARTIAL | Melee from behind while crouched — code-reviewed only |
| Cover (take/leave, edge swap, blind fire) | WORKING | [player.cover]; peeking out from high cover is weak |
| Melee (light, heavy, block, dodge) | WORKING | [combat.melee] bat 100 → 24 HP |
| Swimming / diving / breath / drowning | WORKING | [water.swim, water.dive] |
| Parachute (freefall, deploy, steer, land) | WORKING | [player.parachute, player.parachute_landing] |
| Vault / mantle / ladders | PARTIAL | In code; ladders only at the docks (6); not autotested |
| Ragdoll / knockdown / bail out of a moving vehicle | PARTIAL | In code; seen indirectly (bail-out at speed), not explicitly checked |
| Death → hospital respawn | WORKING | [player.death_respawn] bill up to $500 |
| First-person / far camera | PARTIAL | V cycles near / far / first person (screenshot `cam_view2`); no first-person arms |
| Player model (Blender, rigged) | WORKING | 17-bone rig, fully procedural animation (no keyframed clips) |
| Clothing / barber / wardrobe | PARTIAL | Colour + on/off variations (sleeves, shorts, hats, glasses, beard, 6 haircuts); no separate clothing meshes; player is always the male body |
| Skill progression (7 skills) | PARTIAL | Trains with use, toast on level-up; "Flying" has no gameplay effect |
| Character stats: health / armour | WORKING | Armour absorbs 75 %, headshots |

## NPCs, traffic, police

| Feature | Status | Notes |
|---|---|---|
| Pedestrians (ambient wander, day/night density) | WORKING | [peds.population] 7–20 within 60 m downtown across the last three runs; caps 46 by day / 24 at night |
| Pedestrian reactions (hear gunfire, flee, panic, fight back) | WORKING | [peds.react_gunfire] all nearby pedestrians reacted (8/8 in run7); hearing wired to gunfire/explosions in segment 5 |
| Witnesses → wanted level | WORKING | [wanted.crime_raises_level] heat = crime severity × witness factor |
| NPC variety | PARTIAL | Two Blender base bodies (male/female) with outfit/hair/colour variation; civilians, gang (Ironside), police, tactical; paramedic/firefighter models exist in code but no emergency response |
| Combat AI | PARTIAL | Range keeping, line-of-sight shooting, melee; no cover use, flanking or grenades |
| Traffic (lanes, lights, junction turns, gap keeping, honking, brake for people) | WORKING | [traffic.moving, traffic.stays_on_road] cars slow down for turns and turn where the lane lines cross (they used to cut corners over the pavement), back up with counter-steer when stuck, drive around wrecks and abandoned cars; no lane changes |
| Parked cars | WORKING | 90 kerb-parked; kinematic far away, real bodies within 45 m of the player |
| Wanted 0–5 stars | WORKING | [wanted.crime_raises_level] stars 2–3 for a witnessed shooting |
| Police dispatch (cars, officers, SWAT at 4+, roadblocks 3+, helicopter 3+) | WORKING | [police.dispatch, police.helicopter] 9–11 cars and 14–30 officers at 3 stars across runs, heli with pilot and marksmen; SWAT vans at 4+ are code-reviewed only |
| Pursuit vs search, last known position, escape | WORKING | [wanted.escape_by_search_timeout] police drive to the last known position when they lose sight |
| Busted (arrest at 1–2 stars) | WORKING | [police.busted] officers close in on an unarmed suspect; fine + release at the police station |
| Police shooting from cars (3+) | PARTIAL | Passengers fire at a visible suspect — code-reviewed only |
| PIT / ramming tactics | NOT IMPLEMENTED | Cruisers ram by driving at the player; no PIT manoeuvre |

## Vehicles

| Feature | Status | Notes |
|---|---|---|
| Vehicle roster from Blender (20 models) | WORKING | [vehicles.spawn_all] 20/20: compact, sedan, sports, muscle, SUV, pickup, van, police, taxi, ambulance, fire truck, box truck, SWAT, motorbike, bicycle, speedboat, heli, police heli, prop plane, jet |
| Enter / exit (driver) | WORKING | [vehicle.enter.*, vehicle.exit.*] |
| Car driving (accel, steering, brakes, handbrake, reverse) | WORKING | [drive.sedan] 84 km/h in 6 s, steering/brake checks; reverse added in segment 5 |
| Motorcycle | WORKING | [drive.motorbike] 64 km/h in 6 s |
| Bicycle | WORKING | [drive.bicycle] pedalling fixed in segment 5 |
| Boat | WORKING | [water.boat] 70 m in 5 s, buoyancy |
| Helicopter | WORKING | [air.heli] climbs and flies forward |
| Airplane (prop + jet) | WORKING | [air.plane] prop plane reached 138 km/h on the runway and climbed 10.9 m (ground friction/drag fixed in segment 5); gentle climb rate; jet uses the same code, not separately tested |
| Carjacking (pull driver out) | WORKING | [vehicle.carjack, vehicle.stolen_car_obeys_player] passed in run5, run5d, run6, run7 (15–23 km/h). The stolen car did not move in two re-checks: run5b — the AI car had ended up nose-first against a palm on the pavement (traffic AI bug, fixed); run5c — the car stood on the road, cause not determined (the test now logs wheel/contact diagnostics when this happens) |
| Passenger seats | PARTIAL | G enters as passenger (taxi); no passenger free-aim camera |
| Drive-by shooting | WORKING | [vehicle.driveby] one-handed guns + thrown; not from planes |
| Vehicle damage, smoke, fire, explosion | WORKING | [vehicle.damage_explosion] deformation, smoke < 40 %, fire < 15 %, explosion; no tyre bursts or detaching parts |
| Lights, horn (3 horn types), siren, radio | PARTIAL | In code; not autotested |
| Mod shop: repair, paint, finish, tint, body kit, wheels, performance | WORKING | [vehicle.mods_repair] performance upgrades change handling; the Bay 7 UI opens in game |
| Garage storage / retrieval | PARTIAL | E at a garage stores the car (removed from the world), phone retrieves — fixed in segment 5, not autotested |
| Vehicle purchase | PARTIAL | Showroom lot opens the spawner; there is no car economy |
| Emergency services response (ambulance/fire) | NOT IMPLEMENTED | Vehicles exist and drive as traffic, no dispatch to incidents |

## Weapons and combat

| Feature | Status | Notes |
|---|---|---|
| 16 weapons (melee, handguns, SMG, shotguns, rifles, DMR, sniper, grenade, RPG, grenade launcher) | WORKING | [weapons.fire_all] 11/11 firearms fire and use ammo; melee checked separately |
| Reload, recoil, spread, ammo | WORKING | [weapons.reload] |
| Weapon wheel + slots | WORKING | [ui.weapon_wheel] shows one weapon per class |
| Explosions (rockets, grenades, barrels, pumps) | WORKING | [weapons.explosive_vs_vehicle] |
| Attachments (suppressor, scope, grip, flashlight, ext. mag, tints) | PARTIAL | Bought in the gun shop and affect stats; not saved; no scope overlay |
| Impacts, tracers, bullet holes | PARTIAL | Present; no per-surface decals beyond basic types |
| Weapon pickups / drops | NOT IMPLEMENTED | |

## Economy, services, activities

| Feature | Status | Notes |
|---|---|---|
| Money, shops (weapons, armour, clothes, barber, food) | WORKING | [shops.purchase_ui] clicking "Heavy body armour" takes $900 and fills armour |
| ATM / robbery | PARTIAL | ATM gives $500 with no limit; register robbery pays and counts as a crime |
| Safehouse (sleep = time skip + heal + save, wardrobe) | PARTIAL | Interaction points auto-moved outside the solid building collider; not autotested |
| Taxi (call, ride as passenger, skip trip, fare) | WORKING | [world.taxi] rewritten in segment 5 |
| Trains / public transit line | NOT IMPLEMENTED | |
| Wildlife (deer, boar, coyote, rabbit, cat, dog, seagulls, fish, shark) | WORKING | [world.wildlife] wander/flee, coyotes bite; no hunting rewards; sharks don't attack |
| Shooting range | PARTIAL | Bullets now register on targets (they were triggers); targets are plain primitives; not autotested |
| Stunt jumps | PARTIAL | Any vehicle air time over 0.8 s counts; no placed stunt ramps with markers |
| Street race | PARTIAL | Checkpoints invisible |
| Boat rental, wreck dive, rooftop elevators | PARTIAL | In code; not autotested |

## Blender / pipeline

| Feature | Status | Notes |
|---|---|---|
| Blender MCP on localhost:9880 verified against the master file | WORKING | `bpy.data.filepath` = `…\Unity Opus5.5 GTA\UnityOpus5.5GTA.blend`, Safe Mode on |
| Assets authored through MCP (143) | WORKING | 2 characters, 20 vehicles, 16 weapons + attachments, 38 buildings, 43 props, 14 nature, 9 animals, 1 wreck |
| FBX export → prefab → world placement pipeline | WORKING | `Halcyon/…` menu / batch methods; 0 missing asset types |
| LODs | PARTIAL | LODGroups only cull at distance; no reduced meshes |
| Pooling / AI tiers / spawn radii | PARTIAL | NPC update tiers (45 m / 110 m), spawn/despawn radii, VFX/audio pooling; vehicles and NPCs are instantiated, not pooled |
| Interiors | NOT IMPLEMENTED | Buildings are solid; shops are used from the door |

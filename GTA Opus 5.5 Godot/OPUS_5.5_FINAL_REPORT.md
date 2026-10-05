# Vesper Bay — final report (Claude Opus 5.5, Godot 4.7 + Blender MCP)

## What was built
An original, mission-free GTA-style free-roam sandbox in the existing Godot 4.7.2 project (Forward+, D3D12,
Jolt, GDScript): a compact ~600 × 600 m island with six districts, traffic and pedestrians, 20 drivable
vehicles (cars, emergency vehicles, motorbike, bicycle, boat, two helicopters, two planes), 15 weapons with
attachments, a 0–5 star witness-based wanted system with police/SWAT/helicopter/roadblocks, cover and stealth,
shops, a safehouse, garages, a phone with taxi and services, parachuting, diving, wildlife, day/night and
weather, save/load, and an admin/benchmark menu. Art direction "Sunset Vector": clean stylised low-poly with a
warm coastal palette and neon accents at night.

All important visible 3D assets — player and NPC character kits, every vehicle, every weapon and attachment,
houses, gas station, landmarks, street props and safehouse furniture — were authored by script in the master
`GodotOpus5.5GTA.blend` through the project's Blender MCP server, exported to GLB, imported into Godot and
checked in game. No downloaded asset packs, Asset Library content, generators or external models were used.

## Build / run result
* `Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit` imports all 65 GLBs and parses
  every script without errors.
* The main scene `res://gta/scenes/bootstrap/main.tscn` launches straight into free roam (no missions).
* Final regression through the real game with real input actions (`--autotest=<scenario>`):
  basic 6/6, vehicles 1/1, combat 5/5, world 1/1, air 7/7 (heli, plane, boat, swimming, parachute), views 1/1,
  systems 16/16 (save/load, shop, carjack, drive-by, radio, damage/repair, garage, cover, takedown, emergency
  services, busted, wanted escape, wildlife, taxi call + ride, downtown performance), perf 1/1,
  characters 1/1, weapons 2/2, buildings 2/2. Screenshots and JSON reports are in
  `.opus-5.5-gta-runs/run-20261003-121512-opus55-godot/screens/` (not committed).
* Run it: open the folder in Godot 4.7.2 and press F5, or `Godot_v4.7.2-stable_win64.exe --path <project>`.
* **Standalone builds** (no Godot needed): a self-contained Windows executable and a universal macOS
  app are published in GitHub Releases. Rebuild both with `tools/build_release.ps1` or
  `tools/build_release.sh`; see `RUN_WINDOWS.md` and `RUN_MACOS.md`.

## Controls (full table in DEVELOPMENT.md)
WASD move · Shift sprint · Space jump · Ctrl/C crouch-stealth · RMB aim · LMB fire/melee · R reload ·
Tab weapon wheel · 1–9 / wheel switch · Q cover · F enter/exit/carjack · E interact · V camera · X look back ·
H horn · L lights · G siren · `,` `.` radio · Space handbrake · helicopter Space/Ctrl up/down, W/S pitch, A/D yaw, Q/E roll ·
plane Shift/Ctrl throttle, W/S pitch (W = nose down), A/D roll, Q/E rudder · ↑/P phone · M map + GPS · Esc pause ·
**F1 or ` admin/benchmark menu** · F5/F9 quick save/load · F2 hide HUD · F12 photo.

## What works (see FEATURE_MATRIX.md for every item and how it was verified)
* Player: on-foot movement, sprint/jump/crouch, falls and ragdolls, vault/ladders/roll, swimming and diving,
  skydiving and parachute, third/first-person cameras, shoulder aim with two-bone arm IK (stock in the shoulder,
  support hand on the fore-end).
* Combat: hitscan, pellets, projectiles, grenades and rockets, recoil/spread/headshots, scope, melee combos,
  stealth takedowns, cover with low/high states, weapon wheel, workshop attachments and finishes.
* Vehicles: raycast-suspension cars with damage/fire/explosions, carjacking, drive-by, sirens/lights/radio,
  mod shop (cosmetic + performance) and repair, garage storage, helicopter and airplane flight, boats.
* World: six districts, signalised traffic with routing, pedestrians with panic/flee/witness behaviour,
  emergency services, wildlife, day/night, five weather types, minimap/big map/GPS, taxi service, shooting
  range, stunt jumps, skills, economy, save/load, admin menu.
* Police: witness-based reporting, escalation to 5 stars, pursuit vs search with last-known position and
  growing search area, line-of-sight escape timer, helicopter, roadblocks, spike strips, SWAT, arrests.

## Partial / not implemented (honest summary)
* Downtown towers, apartments, warehouses, hangars and the enterable safehouse shell are still procedural
  shader-facade boxes; only the house types, gas station and landmarks are Blender buildings.
* Characters animate procedurally on a joint hierarchy (no skinned Skeleton3D clips); blocky stylised faces.
* AI traffic: no lane changes for moving traffic, no pulling over for sirens; AI only goes around driverless
  blockers (added in the final pass). AI shoots from vehicles only from the police helicopter.
* No vehicle deformation/detachable parts, no shell ejection or bullet penetration, no trains, no shop staff,
  no AI flanking or NPC-vs-NPC fights, no occlusion culling. Melee block does not reduce damage.
* See FEATURE_MATRIX.md for the complete list (PARTIAL and NOT IMPLEMENTED rows).

## Known bugs / rough edges
* Lane-graph routing can still choose detours around a block; the taxi now stops when close.
* Footstep hearing, the AI overtake of blockers and the regen-timer reset were added in the last pass and are
  covered only by code review plus the regression suite, not by dedicated tests.
* Car door seams run straight through the wheel-arch area (cosmetic, all car GLBs).
* Godot prints a benign physics-interpolation warning when tests move the camera, and Jolt reports leaked
  shape RIDs at process exit.
* Frame rate depends heavily on pedestrian count and time of day (27–109 fps across runs).

## Major assets created in Blender (all through MCP `custom-blender-godot-gta-opus55`, master file verified)
* Characters: male and female kits (35 parts each: segmented body, hair ×N, beards, hats, glasses, jacket,
  hood, vest, police badge, skirt) used by the player and all NPC archetypes with per-NPC colour remaps.
* Vehicles (20 + rim set): Pico Hatch, Meridian Sedan, Vortex GT, Brawler SS, Trailhound SUV, Haulbuck Pickup,
  Courier Van, VBPD Interceptor, Gold Line Taxi, Medic One, Ladder 7, Bulwark Tactical, Hauler Box Truck,
  Razorback 600, Pedalfast BMX, Wavecutter 24, Skylark H2, VBPD Sentinel, Gull Trainer, Stiletto Jet — with
  steering wheels, rotors/props and mod parts (spoilers, hood scoops, roof racks, liveries).
* Weapons (14 + 6 attachments): knife, bat, pistol, revolver, SMG, pump and auto shotgun, assault rifle,
  carbine, DMR, sniper, grenade, rocket launcher, grenade launcher; suppressor, two scopes, grip, extended
  magazine, flashlight.
* Buildings and landmarks: one- and two-storey houses, gas station canopy with pumps, lighthouse, lifeguard
  tower, radio mast with dishes and equipment hut, gantry cranes, beach bar, shipwreck (dive site), and a
  10-piece safehouse furniture set.
* Street props and nature (17): street lamp, traffic light, bench, bin, hydrant, bollard, cone, barrier,
  utility box, bus stop, sign post, palm, round tree, pine, bush, rock, flowers.

## Vehicle roster
13 cars (compact, sedan, sports, muscle, SUV, pickup, van, police interceptor, taxi, ambulance, fire truck,
SWAT truck, box truck), motorbike, BMX, speedboat, civil and police helicopters, prop trainer plane, jet.

## Weapon roster
Fists, Field Knife, Alloy Bat, P9 Compact, Hammer .44, Viper SMG, Breacher Pump, Auto-12 Riot, AR-7 Assault,
K4 Carbine, DMR-11 Marksman, Longshot .50, Frag Grenade, RPL-7 Launcher, GL-6 Launcher; mods: suppressor,
extended magazine, flashlight, optic, grip, four finish tints.

## Map regions
Meridian downtown (towers, police HQ, plaza, shops), Palm Terrace residential (Blender houses, park, hospital,
safehouse, gas station), Ironside industrial (warehouses, mod garage, gun shop + range), Lantern Pier / Coral
Beach (promenade, Ferris-wheel pier, docks with gantry cranes, marina, beach bar, lifeguard tower, lighthouse,
offshore shipwreck), Crown Hill (lookout, radio mast, woods, wildlife, stunt ramps), Vesper Airfield (runway,
apron, hangars, helipad).

## Wanted / police implementation
Crimes are only reported when witnessed (civilians within ~35 m phone it in after 3.5–6 s, cancelled if they
are silenced) or seen by police; gunfire heard nearby triggers an indirect report. Stars 1–5 escalate from foot
officers and patrol cars to more units, a helicopter and roadblocks (3★), SWAT and spike strips (4★+). Police
track the last-known position; while they see the player the state is pursuit, otherwise search with a growing
radius shown on the minimap with officer vision cones. Staying out of sight for the level's escape time
(10–42 s) clears the stars; changing outfit or vehicle reduces recognition. Unarmed, slow players on foot below
4★ can be arrested (Busted: fine and confiscation). Officers within 5 m notice a suspect even if a car roof
blocks their eye ray.

## Performance notes
Static geometry is merged into a few multi-surface meshes (Blender buildings are baked in by `ModelLib`, no
extra draw calls), props use MultiMesh, idle vehicles go dormant, light/material writes are cached and ray
queries reuse one parameter object. Final `perf` run: 106 fps with all effects at 1600×900 (≈1 800 draw calls,
22 traffic cars, 52 pedestrians); downtown samples in `systems` ranged 36–109 fps average. Physics plus NPC
scripts (~16 ms + ~10 ms) are the main costs.

## Claude Opus 5.5 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier: local benchmark run (private runtime identifier removed)
Working directory: project root (local absolute path removed from the public copy)
Start timestamp and timezone: 2026-10-03T12:15:12.5682579+02:00 (UTC+02:00; first agent shell command 12:14:34, first transcript event 12:14:05)
End timestamp and timezone: 2026-10-03T23:10:28+02:00 (UTC+02:00; written to end_time.txt after the final validation and report)
Elapsed wall-clock time (HH:MM:SS): 10:55:15
Elapsed minutes: 655.2
Elapsed hours: 10.92
Known pauses / resumed segments: 16:07:07 -> 17:38:55 (92 min, agent idle waiting for user input); 19:07:33 -> 20:44:12 (97 min, agent idle waiting for user input). Wall-clock minus these idle gaps: 07:46:48 (derived from transcript timestamps, not a separately tracked active time). The session was continued once after automatic context compaction.

Requested model: Claude Opus 5.5
Actual model identifier(s): claude-opus-5-5 (all task requests, main loop and the one Explore sub-agent; session runtime id claude-opus-5-5[1m])
Thinking/effort setting (if exposed): extended thinking active (505 thinking blocks in the main transcript); effort level not exposed in usage metadata
Input tokens (state whether uncached or inclusive): 2,826,934 uncached (`input_tokens`, excludes cache reads/writes)
Cache-read tokens: 205,410,463
Cache-write tokens: 16,477,461
Cache-write duration breakdown (if exposed): 5-minute 16,477,461 / 1-hour 0
Output tokens: 1,221,600
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens; not exposed separately
Deduplicated total tokens: 225,936,458 (input + cache read + cache write + output, 526 unique API messages)
Usage source and observation cutoff: local transcript usage metadata, deduplicated by API message id (private transcript and agent identifiers removed); cutoff 2026-10-03T23:10:28+02:00. Breakdown: main loop: 464 requests, in 2,826,810 / cache-read 184,207,803 / cache-write 15,451,430 / out 1,146,250; sub-agent: 62 requests, in 124 / cache-read 21,202,660 / cache-write 1,026,031 / out 75,350. Service tier/speed reported: standard/None x2, standard/standard x524
Unmeasured work / limitations: the final chat response written after this cutoff; the host's context-compaction summarisation request and the WebFetch tool's page-summarisation model are not recorded in the transcript usage. No other Claude sessions were counted.

Token-only API-equivalent cost (USD): $159.21
Per-model subtotals (if applicable): claude-opus-5-5 only — main loop $148.33; Explore sub-agent $10.88
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing, read 2026-10-03, Standard Claude API tier (global routing, no batch, no fast mode); field semantics checked at https://platform.claude.com/docs/en/build-with-claude/prompt-caching
Rates and formula used: Opus 5.5 per MTok — input $4.00, 5-min cache write $5.00, 1-h cache write $8.00, cache hit $0.20 (0.05x input), output $20.00; cost = (input*4 + cw5m*5 + cw1h*8 + cache_read*0.20 + output*20) / 1,000,000 per request, summed
Cache/context/tier adjustments or explicit assumptions: 1M context billed at standard rates for Opus 5.5 (no long-context premium per the pricing page); every request reported service_tier=standard (speed=standard on 524, speed not reported on 2), so no fast-mode premium was applied; no data-residency multiplier assumed
External tool/API fees (known / excluded / unknown): none known — local Blender and Godot have no API fee; WebFetch/WebSearch server-side fees not applicable/unknown and excluded
Measured / estimated / unavailable, with reasons: time measured (OS timestamps); tokens measured from transcript usage metadata (deduplicated); cost calculated from measured tokens x verified official rates (an API-equivalent, not the user's subscription bill)

Blender MCP server/tool namespace actually used: custom-blender-godot-gta-opus55 (user name blender_godot_gta_opus55; tools mcp__custom-blender-godot-gta-opus55__*)
Blender host: localhost
Blender port: 9881
Blender master file: GodotOpus5.5GTA.blend
Verified master file: project-local `GodotOpus5.5GTA.blend` (bpy.data.filepath was read through the MCP before writes; scene.blendermcp_port = 9881)
Approximate number of major Blender assets created: ~79 (65 GLB files: 17 props, 20 vehicles + rim set, 2 character kits with 35 parts each, 14 weapons + 6 attachments, 9 buildings/landmarks, 10-piece furniture set)

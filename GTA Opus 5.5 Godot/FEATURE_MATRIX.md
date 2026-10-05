# Feature matrix — Vesper Bay (Godot 4.7, Claude Opus 5.5 benchmark)

Statuses: **WORKING** / **PARTIAL** / **NOT IMPLEMENTED**. Verification tag in the notes:
**[T]** checked by an in-game autotest that drives the real game (`--autotest=<scenario>`, PASS in the final
regression), **[S]** seen working in in-game screenshots, **[C]** implemented and code-reviewed only — not
exercised in play during this session. Untested features are never described as tested.

| Feature | Status | Notes |
|---|---|---|
| **World** | | |
| Compact island ~600 × 600 m, 6 districts | WORKING | [T][S] Meridian downtown, Palm Terrace, Ironside, Lantern Pier/Coral Beach + docks, Crown Hill, Vesper Airfield; `world` scenario: 24 POIs |
| Road grid, coastal highway, junctions with signals | WORKING | [T][S] lane graph, 36 s signal cycle; no alleys |
| Key venues (police HQ, hospital, gun shop + range, mod garage, safehouse, gas, dealer, clothes, barber) | WORKING | [T][S] shops/garage/safehouse driven by the `systems` scenario; gas station sells snacks (no fuel system) |
| Blender buildings and landmarks | PARTIAL | [S] 2 house types, gas station, lighthouse, lifeguard tower, radio mast, gantry cranes, beach bar, shipwreck from Blender; downtown towers, apartments, warehouses, hangars and the enterable safehouse shell stay procedural (shader facades) |
| Street props / nature from Blender | WORKING | [S] 17 Blender props (lamps, signals, benches, bins, hydrants, bus stop, trees, palms, rocks…) |
| Safehouse interior | WORKING | [S] Blender furniture set (bed, sofa, TV, kitchen, wardrobe, shelf…); bed saves/skips time, wardrobe changes outfit [T for save] |
| Occlusion culling / city LOD | NOT IMPLEMENTED | merged city mesh is always drawn; props have visibility ranges |
| **Player** | | |
| Walk/run/sprint/jump/crouch, falling and landing damage | WORKING | [T] `basic` (moves 8 m), fall/ragdoll paths exercised in `air` |
| Third-person camera, collision, shoulder aim, first person | WORKING | [T][S] `views`; no first person inside aircraft |
| Character model (Blender kit, male/female, clothing/hair variants) | WORKING | [T][S] `characters`: 8/8 NPC archetypes + player use the Blender kit |
| Skeletal animation clips | NOT IMPLEMENTED | joint hierarchy with procedural animation layers instead of Skeleton3D clips |
| Aim pose (two-bone arm IK, stock in shoulder, support hand on fore-end) | WORKING | [S] `weapons` side views for rifle, pistol, RPG |
| Swimming, diving, breath, drowning | WORKING | [T] `air` → swimming PASS; underwater fog/tint [S] at the wreck |
| Ragdoll, knockdown, get-up | WORKING | [T][S] combat/air scenarios |
| **Cover, stealth, traversal, melee (10A)** | | |
| Cover (snap, low/high, aim/fire from cover) | WORKING | [T] `systems` cover PASS |
| Cover corners / peeking around corners | PARTIAL | [C] lean/stand-to-aim only, no corner wrap |
| AI using cover | PARTIAL | [C] AI picks a spot out of sight; cover hint boxes are not used |
| Stealth crouch: smaller sight range, footstep noise heard by NPCs | WORKING | [C] footstep hearing added in the final pass (sprint ≈22 m, walk 12 m, crouch 3 m × stealth skill) — not exercised by a test |
| Stealth takedown | WORKING | [T] `systems` stealth_takedown PASS |
| Suppressor lowers detection | PARTIAL | [C] lower noise radius, but gunfire still produces an indirect police report |
| Vault/mantle, ladders, dodge-roll | WORKING | [C] few ladders are placed in the world |
| Melee combos, knife, bat, kick, knockdown | WORKING | [T] takedown/punch paths in `systems`; others [C] |
| Melee block | PARTIAL | [C] slows movement and allows a roll; does not reduce damage |
| Directional hit reactions | PARTIAL | [C] generic flinch or knockdown |
| **NPCs (11, 20)** | | |
| Pedestrians with varied looks, sidewalks, crossings | WORKING | [T] 30–57 peds in tests [S] |
| Panic / flee / cower / hands-up / witness phone calls / fight back | WORKING | [T] witness reported crimes in `combat` and `systems` |
| Gangs, police, SWAT, medics | WORKING | [T][S] police/SWAT/medics spawned by tests; gang [C] |
| Shop staff NPCs in venues | NOT IMPLEMENTED | look exists, never spawned |
| Combat AI (LOS, bursts, reload, strafe, melee) | WORKING | [T] police responded and engaged in `combat` |
| Flanking / NPC-vs-NPC fights | NOT IMPLEMENTED | AI only targets the player |
| **Traffic (12)** | | |
| Lane following, signals, intersections, routing, despawn | WORKING | [T] `basic` traffic_spawned (22 cars); taxi route across town [T] |
| Parked cars, dormancy of idle cars | WORKING | [T] perf scenario |
| Lane changes / overtaking | NOT IMPLEMENTED | lane chosen only at junctions |
| Obstacle avoidance | PARTIAL | [C] brakes/honks/reverses; since the final pass AI cars go around a driverless or wrecked car blocking their lane (clear neighbouring lane checked) — added after a stuck-taxi failure, not covered by a dedicated test |
| Drivers reacting to danger / pulling over for sirens | NOT IMPLEMENTED | panic mode exists but is never triggered |
| **Vehicles (13, 13A, 14, 15, 16, 22)** | | |
| Car physics (raycast suspension, grip, handbrake, reverse) | WORKING | [T] `basic` car_drives 11 m/s |
| Roster: 13 cars incl. police/taxi/ambulance/fire/SWAT/truck, motorbike, bicycle, boat, 2 helicopters, prop plane, jet | WORKING | [T] `vehicles`: 19 upright on the apron; all 20 have Blender models [S] |
| Enter/exit, carjacking (driver pulled out) | WORKING | [T] `systems` carjack PASS |
| Drive-by shooting (player) | WORKING | [T] `systems` drive_by PASS |
| AI shooting from vehicles | PARTIAL | [C] police helicopter marksman only |
| Lights, brake/reverse lights, horn, siren, radio | WORKING | [T] radio_switch PASS; lights/siren [S] |
| Doors opening, seat choice, trunk/hood | NOT IMPLEMENTED | player always takes the driver seat (passenger in taxis) |
| Mod shop: paint ×2, finish, rims, tint, body kits, spoiler, livery, plate, lights, horn | WORKING | [S] mod shop panel + Blender mod parts; purchase path [C] |
| Performance upgrades (engine, brakes, transmission, turbo, armour, bulletproof tyres, downforce) | WORKING | [C] suspension upgrade only changes grip |
| Repair | WORKING | [T] vehicle_damage_repair PASS |
| Vehicle damage, smoke, fire, explosion | WORKING | [T] `combat` vehicle_destroyed (RPG) |
| Tyre puncture | PARTIAL | [C] handling only, no flat-tyre visual |
| Detachable parts / deformation / broken lights | NOT IMPLEMENTED | burnt look after explosion only |
| Helicopter flight | WORKING | [T] `air` heli_lifts 34 m |
| Airplane flight | WORKING | [T] `air` plane_takes_off 43 m (after the run-over contact fix) |
| Boats | WORKING | [T] `air` boat_moves 21.6 m/s |
| Garage storage (4 slots, mods kept, saved) | WORKING | [T] garage_store PASS |
| **Weapons (17, 17A)** | | |
| 15 weapons: fists, knife, bat, pistol, revolver, SMG, pump & auto shotgun, assault rifle, carbine, DMR, sniper, grenade, RPG, grenade launcher | WORKING | [T] `combat` fires rifle/RPG; all 14 armed models are Blender GLBs [T] weapon_glb_models 14/14 |
| Ammo, magazines, reload, recoil, spread, headshots, scope zoom | WORKING | [T] weapon_fires PASS; scope [C] |
| Weapon wheel, slots, mouse-wheel switching | WORKING | [S] `views` weapon wheel |
| Weapon mods (suppressor, ext. mag, flashlight, scope, grip, finish tint) | WORKING | [T] weapon_attachments PASS (Blender attachment meshes) |
| Impact effects / decals / material sounds | WORKING | [S] |
| Shell ejection, bullet penetration | NOT IMPLEMENTED | |
| Breakable glass | PARTIAL | [C] particles/sound only |
| **Police and wanted (18, 18A, 19)** | | |
| 0–5 stars with escalation and crime list | WORKING | [T] wanted_raised, set_level paths |
| Witness-based reporting (no global omniscience) | WORKING | [T] crime reported only after a witness call |
| Response per level: cars, foot officers, helicopter, SWAT, roadblocks, spike strips | WORKING | [T] police_responded (4 units + 1 heli); roadblocks/spikes [C] |
| Pursuit vs search, last-known position, growing search area, LOS-based escape timer | WORKING | [T] wanted_escape PASS (lost after 9 s out of sight) |
| Busted / arrest | WORKING | [T] busted PASS (officers now notice a suspect within 5 m even if a car roof blocks the eye ray) |
| PIT manoeuvre / boxing in | PARTIAL | [C] police aim at the rear corner; no boxing in |
| Minimap vision cones and search circle | WORKING | [S] |
| **World systems** | | |
| Day/night cycle, lit windows, street lights | WORKING | [S] only the 12 nearest lamps cast real light |
| Weather: clear, cloudy, rain, storm, fog; wet roads, less grip | WORKING | [S] weather notifications in tests; rain grip [C] |
| Minimap, big map, GPS waypoint | WORKING | [S] `views` big map |
| Taxi service (call, ride, choose destination, skip trip) | WORKING | [T] taxi_arrives + taxi_passenger PASS; the cab pulls over once it is within 40 m and its lane route starts leading away (avoids block-sized detours) |
| Trains / public transit | NOT IMPLEMENTED | |
| Parachute | WORKING | [T] `air` parachute PASS |
| Diving to shipwreck, underwater ambience | WORKING | [S] wreck dive site screenshot |
| Scuba gear | PARTIAL | [C] admin menu only |
| Wildlife (deer, rabbits, boar, coyotes, dogs, gulls, fish, sharks) | WORKING | [T] wildlife PASS (13 animals) |
| Emergency services (ambulance to bodies, fire truck to wrecks) | WORKING | [T] emergency_dispatch PASS |
| Clothing store, barber | WORKING | [C] |
| Phone (taxi, mechanic, medic, map, photo, save, radio) | WORKING | [C] F12 photo key now calls the same capture |
| Economy, cash pickups, hospital bills | WORKING | [T] shop_purchase PASS |
| Save / load | WORKING | [T] save_load PASS |
| Skills progression (7 skills) | WORKING | [C] |
| Shooting range, stunt jumps | WORKING | [C] |
| Admin / benchmark menu (teleports, spawns, weapons, wanted, time, weather, toggles, perf) | WORKING | [S] `views` debug menu; buttons used by tests through the same APIs |
| HUD (health, armour, stamina, breath, ammo, stars, money, speed, minimap) | WORKING | [S] |
| Procedural audio, radio stations, vehicle audio, ambience | WORKING | [C] generated at start-up; not judged by ear in this session |
| VFX (muzzle, impacts, blood, explosions, smoke, fire, splashes, tyre smoke) | WORKING | [S] explosion/muzzle screenshots |
| Skid marks | NOT IMPLEMENTED | |
| Missions / story | NOT IMPLEMENTED | intentionally absent (requirement) |
| **Pipeline / tech** | | |
| Blender MCP asset pipeline (verified master file, backups, scripted assets, GLB export, in-game check) | WORKING | [T][S] 65 GLBs, ≈79 assets; checks in `characters`, `weapons`, `buildings`, `vehicles` |
| Performance (~22 traffic cars, 30–58 peds, all effects) | WORKING | [T] `perf` full scene 106 fps; downtown samples in `systems` 36–109 fps avg (min 27) at 1600×900 on the dev machine; NPC script/physics time is the main cost |
| AI simulation tiers | PARTIAL | [C] pedestrians have 3 think-rate tiers; traffic/police run full AI until despawn |

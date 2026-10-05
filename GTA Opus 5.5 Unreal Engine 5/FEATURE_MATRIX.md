# Feature matrix — Port Halcyon

Updated 2026-10-05T19:12:18.644145+02:00. Status describes evidence, not a marketing completion claim.

Packaged runtime checks: 26 passed, 0 failed.

| Feature | Status | Notes |
|---|---|---|
| Existing project / UE 5.8.2 / C++ Editor and Game targets | WORKING | BuildCookRun succeeded; EngineAssociation remains 5.8. |
| Standalone Windows executable | WORKING | Packaged/Windows/Unreal_Opus5_5_GTA.exe; directly launched with packaged content. |
| Blender MCP route and source | WORKING | custom-blender-unreal-gta-opus55, localhost:9882, full project path read through MCP; Safe Mode preserved. |
| Blender export/import, scale and materials | WORKING | Corrected 100x static export error; metre source converted once to centimetres; checked in runtime. |
| Player/NPC rigs, four body variants | WORKING | Consistent centimetre skeleton, palette materials, PhysicsAsset (20 bodies / 19 constraints). |
| 41 authored animation clips | PARTIAL | All imported and source actions saved with fake users; simple animation quality, not every blend manually reviewed. |
| Walk/run/sprint/jump/crouch | WORKING | On-foot movement checked in packaged game; custom C++ CharacterMovement and Enhanced Input. |
| Camera: third-person, aim, chase | PARTIAL | Functional runtime views; tight corners and some vehicle exits can obscure the view. |
| First-person toggle | PARTIAL | Implemented on V; no exhaustive visual test for every vehicle. |
| Cover and corner peeking | PARTIAL | Contextual wall traces and movement implemented; corner cases not fully play-tested. |
| Stealth / suppression / takedown | PARTIAL | Noise, stance, witness logic and takedown code present; full stealth scenario unverified. |
| Vault / mantle / ladders / dodge | PARTIAL | Traversal code present; not all obstacle types validated. |
| Melee / block / knockdown | PARTIAL | Combat code and clips exist; not every attack/reaction combination tested. |
| Damage / ragdoll / hospital respawn | PARTIAL | PhysicsAsset configured; final runtime checks report damage/ragdoll separately; full death/respawn edge cases remain. |
| Arrest / BUSTED | PARTIAL | Police arrest logic and respawn implemented; independent arrest scenario not verified. |
| Compact world ~600 x 600 m | WORKING | 3938 city instances with zero missing city mesh references; original districts and flight/water areas. |
| Buildings, street kit, nature models | WORKING | Blender authored modular meshes imported; visibly simple stylized geometry. |
| Road and lane graph | WORKING | Lane following and junctions active in packaged simulation. |
| Pedestrians / drivers / visual variation | WORKING | Population spawns and reacts in runtime; distance-based updates and despawning. |
| Traffic / signals / parked cars | PARTIAL | Traffic runs; can bunch up, collide and block junctions. Not production traffic AI. |
| Vehicle enter/drive/exit | WORKING | Sedan movement and ground contact checked; raycast suspension stabilized. |
| Eight required car classes | WORKING | Distinct authored silhouettes share the car framework and are available via F1. |
| Motorcycle / bicycle | PARTIAL | Meshes, wheels and balancing physics available; sustained handling not separately verified. |
| Boat | WORKING | Buoyancy and propulsion checked in packaged runtime. |
| Civilian helicopter | WORKING | Takeoff and altitude checked. |
| Police helicopter | PARTIAL | Model and pursuit flight logic available; prolonged high-star pursuit unverified. |
| Propeller airplane | WORKING | Acceleration and takeoff altitude checked. |
| Jet / additional vehicles | PARTIAL | All bodies load; individual handling, landings and camera behavior need more testing. |
| Carjacking | PARTIAL | Driver ejection, transition and theft reporting implemented; separate occupied-vehicle scenario unverified. |
| Drive-by shooting | PARTIAL | Weapon restrictions and aiming path exist; broad vehicle tests incomplete. |
| Lights / siren / horn / roof | PARTIAL | Runtime components and original sounds; Sports/Muscle open meshes added. No detachable doors/hood. |
| Vehicle damage / fire / explosions | PARTIAL | Health, impact damage, handling effects and explosions implemented; prolonged physics/chain-reaction stability unverified. |
| Repair and customization | PARTIAL | Purchases, paint, parts and handling upgrades implemented; repair checked separately, all upgrades not exhaustively compared. |
| Weapon inventory / firing / reload | WORKING | Models load, pistol firing consumes ammunition; ammo/reload and projectile framework present. |
| Weapon wheel | WORKING | Shown in packaged test; inventory populated with all weapon categories. |
| Weapon attachments / ballistic material effects | PARTIAL | Attachments and gameplay modifiers implemented; every combination unverified. |
| Wanted 0–5 / witnesses / police dispatch | WORKING | Witnessed gunfire escalates response; police units and vehicles spawn. Level controls checked separately. |
| Search / line of sight / escape | WORKING | Controlled packaged test clears responding units and moves the player away, then verifies unseen search decay. Complex chase evasion is not exhaustively verified. |
| Police tactics / roadblocks / tactical response | PARTIAL | Code paths present; extended 3–5 star balance and tactics not fully verified. |
| Combat AI / navigation | PARTIAL | Navigation invoker, combat, flee and reload states; imperfect avoidance and cover choices. |
| Physics props / destruction | PARTIAL | Impact effects and force reactions; no building destruction or structural deformation. |
| Swimming / diving / breath / scuba | WORKING | Water volume activates swimming in packaged test; breath and scuba logic included. |
| Parachute | WORKING | Packaged checks confirm deployment and slower descent; extreme landing cases remain untested. |
| Wildlife | PARTIAL | 12 circling gulls with flapping wings, 16 fish and 4 deer; deer flee nearby player. No hunting/ecosystem or skeletal gait. |
| Taxi service | PARTIAL | Call/passenger/waypoint route code present; full destination ride not tested. |
| Trains / subway | NOT IMPLEMENTED | Optional transit stretch goal. |
| Emergency responders | PARTIAL | Ambulance/fire-truck models and paid phone healing; no autonomous incident dispatch. |
| Radio | PARTIAL | Three original synthesized loops and cycling; station persistence incomplete. |
| Economy / pickups | PARTIAL | Cash, payments and pickups implemented; transaction branches not exhaustively tested. |
| Weapon store | WORKING | Catalog opens with purchasable weapons/ammo/mods; UI path checked. |
| Clothes / barber | PARTIAL | Visible material/body/accessory options; every combination not reviewed. |
| Safehouse / garage storage | PARTIAL | Menus, ownership and serialized garage data; interior/collision and retrieval edge cases need polish. |
| Phone | PARTIAL | Save, taxi, vehicle service, skills, healing and lawyer utilities; no camera/photo mode. |
| HUD / minimap / full map / waypoint | WORKING | Visible in packaged runtime; original Slate/UMG widgets. |
| Day/night / weather | WORKING | Day, night and rain screenshots; clear/cloudy/fog/storm available. |
| Audio | PARTIAL | 51 original synthesized SoundWaves imported and routed; sound-design quality is basic. |
| VFX | PARTIAL | Pooled mesh particles, rain and impacts; simple visuals, not a full Niagara effects library. |
| Skills | PARTIAL | Use-based stats and menu controls; long-term progression balancing unverified. |
| Activities: range / stunts / races | PARTIAL | Stunt tracking and range scoring hooks; races and complete range activity absent. |
| Save / load / position / settings | WORKING | Isolated save-slot round trip restored money and position; health, weapons, time and settings serialized. |
| Benchmark menu | WORKING | F1 exposes teleport, vehicles, weapons, time/weather, wanted and testing toggles. |
| Performance / LOD / simulation tiers | PARTIAL | Instancing and limited population updates; test hardware only, no broad hardware certification. |
| Missions / campaign / quest markers | NOT IMPLEMENTED | Intentionally excluded as required. No mission runtime system. |

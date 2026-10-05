"""One-off source patch (segment 5): wanted heat model, busted, police search, heli pilot, NPC hearing."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("Police/WantedSystem.cs", [
("""        readonly Queue<(float t, Vector3 pos, GameObject perp)> pendingReports = new Queue<(float, Vector3, GameObject)>();""",
 """        readonly Queue<(float t, Vector3 pos, float heat)> pendingReports = new Queue<(float, Vector3, float)>();
        float bustTimer;
        /// <summary>Heat per unit of (severity x witness factor); 1 heat = 1 star.</summary>
        const float HeatScale = 1.6f;"""),
("""            reportDelay = c == CrimeType.Gunfire ? 0.35f : 0.8f;
            pendingReports.Enqueue((Time.time + reportDelay * UnityEngine.Random.Range(0.7f, 1.3f), pos, perp));""",
 """            reportDelay = c == CrimeType.Gunfire ? 0.35f : 0.8f;
            pendingReports.Enqueue((Time.time + reportDelay * UnityEngine.Random.Range(0.7f, 1.3f), pos, reported * HeatScale));"""),
("""        public static void Report(Vector3 pos, float severity, GameObject perp, bool byPolice)""",
 """        /// <summary>Police saw the suspect: refreshes the last known position (does not add stars by itself).</summary>
        public static void Spotted(Vector3 playerPos)
        {
            if (I == null || Level == 0) return;
            LastKnownPos = playerPos;
        }

        public static void Report(Vector3 pos, float severity, GameObject perp, bool byPolice)"""),
("""                var r = pendingReports.Dequeue();
                if (Level < 5) AddHeat(0.55f);""",
 """                var r = pendingReports.Dequeue();
                if (Level < 5) AddHeat(r.heat);"""),
("""            // little decay while hidden for very low levels so a stray shot fades out""",
 """            // BUSTED: an officer on foot reaches a 1-2 star suspect who is on foot and not fighting back
            if (Level <= 2 && !Busted && !pc.actor.InVehicle && pc.state != MoveState.Swim)
            {
                Actor cop = null;
                foreach (var b in NPCBrain.All)
                {
                    if (b == null || !b.officer || b.vehicle != null) continue;
                    var ba = b.GetComponent<Actor>();
                    if (ba == null || ba.IsDead) continue;
                    if ((b.transform.position - ppos).sqrMagnitude < 1.8f * 1.8f) { cop = ba; break; }
                }
                bool calm = pc.cc != null && pc.cc.velocity.magnitude < 3.2f && !pc.IsAiming;
                if (cop != null && calm)
                {
                    if (bustTimer <= 0f) HUD.Notify("Police: hands where we can see them!", 1.4f);
                    bustTimer += Time.deltaTime;
                    if (bustTimer > 1.4f) { bustTimer = 0f; TryBust(cop); return; }
                }
                else bustTimer = Mathf.Max(0f, bustTimer - Time.deltaTime * 2f);
            }

            // little decay while hidden for very low levels so a stray shot fades out"""),
])

edit("AI/NPCBrain.cs", [
("""        void OnEnable() { All.Add(this); }
        void OnDisable() { All.Remove(this); }""",
 """        void OnEnable() { All.Add(this); WorldEvents.Noise += OnNoise; WorldEvents.Explosion += OnExplosion; }
        void OnDisable() { All.Remove(this); WorldEvents.Noise -= OnNoise; WorldEvents.Explosion -= OnExplosion; }

        /// <summary>Hearing: gunfire/explosions scare civilians and alert police; player footsteps help officers find a hidden suspect.</summary>
        void OnNoise(Vector3 p, float radius, GameObject src)
        {
            if (actor == null || actor.IsDead || src == gameObject) return;
            float d2 = (transform.position - p).sqrMagnitude;
            if (d2 > radius * radius) return;
            if (radius >= 30f) { OnGunfireHeard(p, radius); return; }
            var pc = PlayerController.I;
            if (officer && pc != null && src == pc.gameObject && WantedSystem.Level > 0)
            {
                lastKnownPlayerPos = p;
                var look = U.Flat(p - transform.position);
                if (vehicle == null && state != NPCState.Combat && look.sqrMagnitude > 0.01f) { Alerted = true; transform.rotation = Quaternion.LookRotation(look.normalized); }
            }
        }

        void OnExplosion(Vector3 p, float r) { OnGunfireHeard(p, Mathf.Max(r * 8f, 60f)); }"""),
("""            if (vehicle != null)
            {
                // inside a vehicle: only panic logic runs
                if (state == NPCState.Flee) { }
                return;
            }""",
 """            if (vehicle != null && actor.vehicle != vehicle)
            {
                // pulled out / ejected / vehicle cleaned up: resume walking AI
                vehicle = null;
                if (cc != null) cc.enabled = true;
            }
            if (vehicle != null) return;   // inside a vehicle the driving AI is in charge"""),
("""            if (seePlayer && playerViolent && officer && !Alerted)
            {
                Alerted = true;
                WantedSystem.Report(transform.position, 1f, gameObject, true);
            }
            if (actor.lastAttacker != null && Time.time - actor.lastDamageTime < 6f && actor.lastAttacker == pc.gameObject)
            {
                if (!officer && UnityEngine.Random.value < bravery) SetState(NPCState.Combat);
                else SetState(NPCState.Flee);
            }""",
 """            if (seePlayer && WantedSystem.Level > 0 && officer)
            {
                WantedSystem.Spotted(pc.transform.position);
                lastKnownPlayerPos = pc.transform.position;
                if (!Alerted) { Alerted = true; if (vehicle == null) SetState(NPCState.Combat); }
            }
            if (actor.lastAttacker != null && Time.time - actor.lastDamageTime < 6f && actor.lastAttacker == pc.gameObject)
            {
                if (officer || UnityEngine.Random.value < bravery) SetState(NPCState.Combat);
                else SetState(NPCState.Flee);
            }"""),
])

edit("Police/PoliceDispatch.cs", [
("""        readonly List<(Vehicle v, VehicleAI ai)> units = new List<(Vehicle, VehicleAI)>();""",
 """        readonly List<(Vehicle v, VehicleAI ai)> units = new List<(Vehicle, VehicleAI)>();
        readonly Dictionary<Vehicle, float> shootTimer = new Dictionary<Vehicle, float>();"""),
("""                if (v == null || v.IsDestroyed || (pc != null && Vector3.Distance(v.transform.position, pc.transform.position) > MaxDist) || (v.Driver == null && v.Speed < 0.2f) || WantedSystem.Level == 0)""",
 """                float dist = (pc != null && v != null) ? Vector3.Distance(v.transform.position, pc.transform.position) : 0f;
                // driverless units (officers out on foot, roadblocks) stay while they are close to the action
                bool abandoned = v != null && v.Driver == null && v.Speed < 0.2f && !v.persistent && dist > 70f;
                if (v == null || v.IsDestroyed || dist > MaxDist || abandoned || WantedSystem.Level == 0)"""),
("""                if (v.Speed > 0.5f && !v.sirenOn && Random.value < 0.01f) v.ToggleSiren();
                ai.pursuing = true;""",
 """                if (v.Speed > 0.5f && !v.sirenOn && Random.value < 0.01f) v.ToggleSiren();
                ai.pursuing = true;
                // passengers lean out and shoot at a suspect they can see (3+ stars)
                if (lvl >= 3 && d < 32f && v.seats.Length > 1)
                {
                    shootTimer.TryGetValue(v, out float st);
                    st -= Time.deltaTime;
                    if (st <= 0f)
                    {
                        st = Random.Range(0.35f, 0.9f);
                        for (int s = 1; s < v.seats.Length; s++)
                        {
                            var occ = v.seats[s].occupant;
                            if (occ == null || occ.IsDead || occ.weapons == null) continue;
                            if (!U.LineOfSight(occ.HeadPos, pc.actor.Center, v.transform, pc.transform, Layers.Sight)) continue;
                            occ.weapons.accuracyMul = 2.6f;
                            occ.weapons.Fire(pc.actor.Center + Random.insideUnitSphere * 0.6f, 1.8f, true);
                            break;
                        }
                    }
                    shootTimer[v] = st;
                }"""),
("""            if (lvl >= 3)
            {
                for (int i = 0; i < 2; i++)
                {
                    var a = NPCFactory.Spawn(i == 0 ? NPCFactory.Archetype.Tactical : NPCFactory.Archetype.Police, v.transform.position + Vector3.up * 2f, v.transform.rotation);
                    if (a == null) continue;
                    a.GetComponent<NPCBrain>().EnterVehicle(v, Mathf.Min(i + 1, v.seats.Length - 1));
                    crew.Add(a);
                }
            }""",
 """            // pilot in seat 0 (helicopters ignore input without a driver), marksmen in the back
            var pilot = NPCFactory.Spawn(NPCFactory.Archetype.Police, v.transform.position + Vector3.up * 2f, v.transform.rotation);
            if (pilot != null) pilot.GetComponent<NPCBrain>().EnterVehicle(v, 0);
            if (lvl >= 3)
            {
                for (int i = 0; i < 2 && i + 1 < v.seats.Length; i++)
                {
                    var a = NPCFactory.Spawn(i == 0 ? NPCFactory.Archetype.Tactical : NPCFactory.Archetype.Police, v.transform.position + Vector3.up * 2f, v.transform.rotation);
                    if (a == null) continue;
                    a.GetComponent<NPCBrain>().EnterVehicle(v, i + 1);
                    crew.Add(a);
                }
            }"""),
("""            if (PoliceDispatch.HeliSeesPlayer) WantedSystem.Report(player.position, 0.02f, PlayerController.I.gameObject, true);""",
 """            if (PoliceDispatch.HeliSeesPlayer) WantedSystem.Spotted(player.position);"""),
])

edit("Traffic/VehicleAI.cs", [
("""            if (police && pursuing && playerT != null)
            {
                Vector3 chase = hasChasePos ? chasePos : playerT.position;""",
 """            if (police && pursuing && playerT != null)
            {
                // direct chase only while the suspect is seen; otherwise search around the last known position
                if (!WantedSystem.Pursuing)
                {
                    searchT -= dt;
                    if (searchT <= 0f) { searchT = Random.Range(5f, 9f); searchOffset = Random.insideUnitSphere * Mathf.Lerp(18f, 45f, Random.value); searchOffset.y = 0f; }
                }
                Vector3 chase = WantedSystem.Pursuing ? (hasChasePos ? chasePos : playerT.position) : WantedSystem.LastKnownPos + searchOffset;"""),
("""                wantSpeed = dP > 25f ? 30f : dP > 12f ? 20f : 12f;""",
 """                wantSpeed = dP > 25f ? 30f : dP > 12f ? 20f : 12f;
                if (!WantedSystem.Pursuing) wantSpeed = dP > 30f ? 20f : 8f;   // search patrol"""),
("""        void Update()
        {
            if (v == null || v.IsDestroyed) { enabled = false; return; }""",
 """        float searchT; Vector3 searchOffset;

        void Update()
        {
            if (v == null || v.IsDestroyed) { enabled = false; return; }"""),
])
print("patched")

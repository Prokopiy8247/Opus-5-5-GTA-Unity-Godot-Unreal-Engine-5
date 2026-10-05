using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>
    /// 0-5 star wanted system. Crimes only escalate if they are witnessed or reported; police need line of sight to
    /// pursue, and the level decays only while the player stays unseen (pursuit vs search states).
    /// </summary>
    public class WantedSystem : MonoBehaviour
    {
        public static WantedSystem I;
        public static int Level { get; private set; }
        public static bool Pursuing { get; private set; }
        public static float SearchProgress { get; private set; }   // 0..1 escape timer
        public static float LastCrimeTime { get; private set; } = -99f;
        public static Vector3 LastKnownPos { get; private set; }
        public static bool Busted { get; private set; }

        float[] heat = new float[6];
        float crimeCooldown, reportDelay;
        readonly Queue<(float t, Vector3 pos, float heat)> pendingReports = new Queue<(float, Vector3, float)>();
        float bustTimer;
        /// <summary>Heat per unit of (severity x witness factor); 1 heat = 1 star.</summary>
        const float HeatScale = 1.6f;
        public float searchRadius = 60f;
        float unseenTime, seenTime;
        static float decayRate => 1f / Mathf.Lerp(24f, 75f, Level / 5f);

        void Awake() { I = this; }
        void OnEnable() { WorldEvents.Crime += OnCrime; }
        void OnDisable() { WorldEvents.Crime -= OnCrime; }

        void OnCrime(CrimeType c, Vector3 pos, GameObject perp)
        {
            if (perp == null || perp.GetComponent<PlayerController>() == null || Suppressed) return;
            LastCrimeTime = Time.time;
            LastKnownPos = pos;
            float severity;
            switch (c)
            {
                case CrimeType.Gunfire: severity = 0.12f; break;
                case CrimeType.Assault: severity = 0.25f; break;
                case CrimeType.Murder: severity = 0.75f; break;
                case CrimeType.AssaultCop: severity = 0.9f; break;
                case CrimeType.KillCop: severity = 1.4f; break;
                case CrimeType.CarJack: severity = 0.3f; break;
                case CrimeType.StealCopCar: severity = 1.1f; break;
                case CrimeType.Explosion: severity = 0.9f; break;
                case CrimeType.VehicleHit: severity = 0.35f; break;
                case CrimeType.DestroyCopCar: severity = 1.5f; break;
                case CrimeType.Ramming: severity = 0.5f; break;
                case CrimeType.Robbery: severity = 0.6f; break;
                default: severity = 0.2f; break;
            }
            float witnessK = WitnessFactor(pos, c);
            float reported = severity * witnessK;
            if (reported <= 0.001f) return;
            reportDelay = c == CrimeType.Gunfire ? 0.35f : 0.8f;
            pendingReports.Enqueue((Time.time + reportDelay * UnityEngine.Random.Range(0.7f, 1.3f), pos, reported * HeatScale));
        }

        float WitnessFactor(Vector3 pos, CrimeType c)
        {
            // police that see it report immediately
            foreach (var b in NPCBrain.All)
            {
                if (!b.officer) continue;
                if (Vector3.Distance(b.transform.position, pos) < 60f) return 1.3f;
            }
            if (c == CrimeType.Explosion || c == CrimeType.Gunfire)
            {
                float best = 0.35f; // loud crimes travel
                foreach (var a in Actor.All)
                {
                    if (a.IsPlayer || a.IsDead || a.faction == Faction.Animal) continue;
                    float d = Vector3.Distance(a.transform.position, pos);
                    if (d < 45f) best = Mathf.Max(best, 1f - d / 60f);
                }
                return best;
            }
            foreach (var a in Actor.All)
            {
                if (a.IsPlayer || a.IsDead || a.faction == Faction.Animal) continue;
                float d = Vector3.Distance(a.transform.position, pos);
                if (d > 40f) continue;
                if (!U.LineOfSight(a.HeadPos, pos + Vector3.up, a.transform, null, Layers.Sight)) continue;
                if (UnityEngine.Random.value < 0.85f) return 1f;
            }
            return 0.15f;
        }

        /// <summary>Police saw the suspect: refreshes the last known position (does not add stars by itself).</summary>
        public static void Spotted(Vector3 playerPos)
        {
            if (I == null || Level == 0) return;
            LastKnownPos = playerPos;
        }

        /// <summary>Admin "never wanted" switch (also used by the autotest while it shoots at test targets).</summary>
        public static bool Suppressed;

        public static void Report(Vector3 pos, float severity, GameObject perp, bool byPolice)
        {
            if (I == null || Suppressed) return;
            LastKnownPos = pos;
            LastCrimeTime = Time.time;
            I.AddHeat(severity * (byPolice ? 1.3f : 1f));
        }

        void AddHeat(float amount)
        {
            heat[Level] += amount;
            float need = Level < 5 ? 1f : 1.4f;
            while (heat[Level] >= need && Level < 5 && Time.time - crimeCooldown > 0.05f)
            {
                heat[Level] -= need;
                SetLevel(Level + 1);
                crimeCooldown = Time.time;
            }
        }

        /// <summary>Debug/admin entry point (benchmark menu and save loading).</summary>
        public static void SetLevelExternal(int level)
        {
            if (I == null) return;
            I.SetLevel(level);
            I.unseenTime = 0f;
        }

        void SetLevel(int lvl)
        {
            lvl = Mathf.Clamp(lvl, 0, 5);
            if (lvl == Level) return;
            bool up = lvl > Level;
            Level = lvl;
            SearchProgress = 0f;
            for (int i = 0; i < heat.Length; i++) if (i > lvl) heat[i] = 0f;
            unseenTime = 0f;
            HUD.OnWantedChanged();
            AudioFX.Play(up ? (lvl >= 4 ? "stinger_busted" : "beep") : "stinger_good", up ? 0.7f : 0.5f);
            if (up) HUD.Notify("WANTED LEVEL " + lvl + (lvl >= 3 ? " - roadblocks and air support" : ""), 2.4f);
            else if (lvl == 0) HUD.Notify("Wanted level cleared", 2f);
        }

        public static void Clear() => I?.SetLevel(0);

        void Update()
        {
            if (GameManager.Paused) return;
            var pc = PlayerController.I;
            if (pc == null) return;
            while (pendingReports.Count > 0 && Time.time >= pendingReports.Peek().t)
            {
                var r = pendingReports.Dequeue();
                if (Level < 5 && !Suppressed) AddHeat(r.heat);
            }

            if (Level == 0) { Pursuing = false; SearchProgress = 0f; return; }

            // is the player seen by any police right now?
            bool seen = false; Vector3 seenPos = Vector3.zero;
            var ppos = pc.transform.position;
            foreach (var a in Actor.All)
            {
                if (a.faction != Faction.Police || a.IsDead) continue;
                if (Vector3.Distance(a.transform.position, ppos) > 95f) continue;
                if (U.LineOfSight(a.HeadPos, pc.actor.Center, a.transform, pc.transform, Layers.Sight)) { seen = true; seenPos = ppos; break; }
            }
            if (!seen && PoliceDispatch.HeliSeesPlayer) { seen = true; seenPos = ppos; }
            if (seen)
            {
                Pursuing = true;
                LastKnownPos = seenPos;
                seenTime += Time.deltaTime;
                unseenTime = 0f;
                SearchProgress = 0f;
            }
            else
            {
                if (Pursuing) { Pursuing = false; }
                unseenTime += Time.deltaTime;
                searchRadius = Mathf.Max(searchRadius, 30f);
                float need = Mathf.Lerp(18f, 42f, Level / 5f);
                SearchProgress = Mathf.Clamp01(unseenTime / need);
                if (SearchProgress >= 1f)
                {
                    Level--;
                    unseenTime = 0f;
                    SearchProgress = 0f;
                    heat[Mathf.Clamp(Level, 0, 5)] = 0f;
                    HUD.OnWantedChanged();
                    if (Level == 0) { HUD.Notify("You lost the cops", 2.4f); AudioFX.Play("stinger_good", 0.6f); }
                    else { HUD.Notify("Wanted level reduced", 1.6f); AudioFX.Play("beep", 0.4f); }
                }
            }

            // BUSTED: an officer on foot reaches a 1-2 star suspect who is on foot and not fighting back
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

            // little decay while hidden for very low levels so a stray shot fades out
            if (!seen && Level == 1 && Time.time - LastCrimeTime > 20f)
            {
                heat[0] = Mathf.Max(0f, heat[0] - Time.deltaTime * 0.2f);
                if (heat[0] <= 0.01f && !PoliceDispatch.AnyPursuing) SetLevel(0);
            }

            // hiding in a garage / house helps lose the search
            if (!seen && pc.actor.InVehicle && pc.actor.vehicle != null && GameTime.IsDark && Vector3.Distance(pc.transform.position, LastKnownPos) > 120f)
                unseenTime += Time.deltaTime * 0.4f;
            if (!seen && pc.HasChangedAppearanceRecently && Vector3.Distance(pc.transform.position, LastKnownPos) > 60f)
                unseenTime += Time.deltaTime * 0.3f;
        }

        public static bool TryBust(Actor cop)
        {
            var pc = PlayerController.I;
            if (pc == null || I == null) return false;
            if (pc.IsAiming || (pc.weapons != null && pc.weapons.LastShotTime > Time.time - 1.5f)) return false;
            Busted = true;
            I.SetLevel(0);
            GameManager.I.StartCoroutine(BustedRoutine(pc, cop));
            return true;
        }

        static System.Collections.IEnumerator BustedRoutine(PlayerController pc, Actor cop)
        {
            HUD.Notify("BUSTED", 4f);
            AudioFX.Play("stinger_busted", 0.8f);
            yield return new WaitForSeconds(1.1f);
            float tx = GameManager.I != null ? 0f : 0f;
            var ps = PlayerState.I;
            int fine = Mathf.Min(ps.money, 250 + Level * 120);
            ps.money -= fine;
            HUD.Notify("Fine paid: " + U.Money(fine), 2.5f);
            var spawn = WorldMarkers.PoliceStation + new Vector3(0f, 1.2f, 0f);
            pc.Teleport(spawn, 180f);
            yield return new WaitForSeconds(1.4f);
            HUD.Notify("Released", 1.6f);
            Busted = false;
        }
    }
}

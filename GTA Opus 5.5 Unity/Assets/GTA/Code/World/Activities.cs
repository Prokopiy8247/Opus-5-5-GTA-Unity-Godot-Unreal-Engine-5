using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Free-roam activities: shooting range, stunt jumps, street race checkpoints and time trials.</summary>
    public class Activities : MonoBehaviour
    {
        public static Activities I;
        public static int StuntJumpsDone, StuntJumpsTotal;
        static float airStart;
        float airTime, lastGroundY;
        public static int RangeScore, RangeBest;
        public static bool RangeActive { get; private set; }
        static readonly List<RangeTarget> targets = new List<RangeTarget>();
        static readonly List<Transform> raceCheckpoints = new List<Transform>();
        static int checkpointIdx;
        public static float RaceTime;
        public static bool RaceActive;

        void Awake() { I = this; }

        public static void Init() { var g = new GameObject("[Activities]"); I = g.AddComponent<Activities>(); }

        public static void StartRange()
        {
            var centre = WorldMarkers.WeaponShop + new Vector3(0f, 0f, 26f);
            foreach (var t in targets) if (t != null) Destroy(t.gameObject);
            targets.Clear();
            RangeScore = 0; RangeActive = true;
            for (int i = 0; i < 6; i++)
            {
                var p = centre + new Vector3((i - 2.5f) * 3.4f, 1.1f, 0f);
                p.y = U.GroundHeight(p + Vector3.up * 2f, p.y);
                var g = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                g.name = "RangeTarget";
                g.transform.SetPositionAndRotation(p + Vector3.up * 0.55f, Quaternion.Euler(90f, 0f, 0f));
                g.transform.localScale = new Vector3(0.5f, 0.06f, 0.5f);
                var r = g.GetComponent<Renderer>();
                var m = new Material(Shader.Find("Universal Render Pipeline/Lit"));
                m.SetColor("_BaseColor", new Color(0.85f, 0.25f, 0.2f));
                r.sharedMaterial = m;
                g.layer = Layers.Prop;   // solid so hitscan bullets register (RangeTarget is IDamageable)
                var t2 = g.AddComponent<RangeTarget>();
                t2.Reset(p + Vector3.up * 0.55f, Quaternion.Euler(90f, 0f, 0f));
                targets.Add(t2);
            }
            HUD.Notify("Shooting range started - 6 targets. Score counts hits.", 3f);
        }

        public static void ResetStunts() { StuntJumpsDone = 0; }

        public static void RegisterRangeHit(int points)
        {
            RangeScore += points;
            RangeBest = Mathf.Max(RangeBest, RangeScore);
            HUD.Notify("Range score: " + RangeScore, 1.4f);
            PlayerState.I.Train(Skill.Shooting, 0.01f);
        }

        void Update()
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            var v = pc.actor.vehicle;
            bool inVehicle = v != null && v.Driver == pc.actor;
            bool grounded = !inVehicle ? pc.state == MoveState.Ground : true;
            bool airborne = !grounded && !pc.Underwater && pc.state != MoveState.Swim && pc.state != MoveState.Parachute;

            if (airborne) { airTime += Time.deltaTime; }
            else
            {
                if (airTime > 1.0f && !inVehicle)
                {
                    HUD.Notify("Stunt: " + airTime.ToString("F1") + "s airtime", 1.6f);
                    StuntJumpsDone++;
                    PlayerState.I.Train(Skill.Driving, 0.005f);
                }
                airTime = 0f;
            }
            // vehicle jumps count too
            if (inVehicle && v.Rb != null)
            {
                bool onGround = Physics.Raycast(v.transform.position + Vector3.up, Vector3.down, out _, 2f, Layers.Ground, QueryTriggerInteraction.Ignore);
                if (!onGround) { airStart += Time.deltaTime; }
                else if (airStart > 0.8f)
                {
                    HUD.Notify("Stunt jump complete: " + Mathf.RoundToInt(airStart * 10f) + " points", 1.8f);
                    StuntJumpsDone++;
                    PlayerState.I.Earn(Mathf.RoundToInt(airStart * 25f), "stunt jump");
                    airStart = 0f;
                }
                else airStart = 0f;
            }

            // shooting range reset when the player leaves
            if (RangeActive && Vector3.Distance(pc.transform.position, WorldMarkers.WeaponShop) > 80f)
            {
                RangeActive = false;
                foreach (var t in targets) if (t != null) Destroy(t.gameObject);
                targets.Clear();
            }

            // taxi trip timer / race
            if (RaceActive)
            {
                RaceTime += Time.deltaTime;
                if (checkpointIdx < raceCheckpoints.Count && raceCheckpoints[checkpointIdx] != null)
                {
                    if (Vector3.Distance(pc.transform.position, raceCheckpoints[checkpointIdx].position) < 7f)
                    {
                        checkpointIdx++;
                        if (checkpointIdx >= raceCheckpoints.Count)
                        {
                            RaceActive = false;
                            PlayerState.I.Earn(2500, "street race won");
                            HUD.Notify("Race finished in " + RaceTime.ToString("F1") + "s", 3f);
                            AudioFX.Play("stinger_good", 0.7f);
                        }
                        else HUD.Notify("Checkpoint " + checkpointIdx + " / " + raceCheckpoints.Count, 1.2f);
                    }
                }
            }
        }

        public static void StartStreetRace(List<Transform> checkpoints)
        {
            raceCheckpoints.Clear();
            raceCheckpoints.AddRange(checkpoints);
            checkpointIdx = 0; RaceTime = 0f; RaceActive = true;
            HUD.Notify("Street race: hit all " + checkpoints.Count + " checkpoints", 3f);
        }
    }

    public class RangeTarget : MonoBehaviour, IDamageable
    {
        Vector3 home; Quaternion rot; float respawn;
        void Awake() { home = transform.position; rot = transform.rotation; }
        public void Reset(Vector3 p, Quaternion q) { home = p; rot = q; transform.SetPositionAndRotation(p, q); }
        void Update()
        {
            if (respawn > 0f)
            {
                respawn -= Time.deltaTime;
                if (respawn <= 0f) { transform.SetPositionAndRotation(home, rot); SetShown(true); }
            }
        }
        public void TakeDamage(DamageInfo d) { if (respawn <= 0f) Hit(); }

        void SetShown(bool on)
        {
            var r = GetComponent<Renderer>(); if (r) r.enabled = on;
            var c = GetComponent<Collider>(); if (c) c.enabled = on;
        }
        void Hit()
        {
            Activities.RegisterRangeHit(10);
            AudioFX.PlayAt("hit_metal", transform.position, 0.5f, 1.6f);
            VFX.Impact(transform.position, Vector3.up, Surface.Metal);
            SetShown(false);   // stays active so Update can respawn it
            respawn = 1.6f;
        }
    }
}

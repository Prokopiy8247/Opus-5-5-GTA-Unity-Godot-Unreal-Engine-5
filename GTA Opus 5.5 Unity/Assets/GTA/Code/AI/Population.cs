using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Builds NPC actors from the Blender character prefabs and dresses them per archetype.</summary>
    public static class NPCFactory
    {
        static System.Random rng = new System.Random(7);

        public enum Archetype { Civilian, Police, Tactical, Gang, Paramedic, Firefighter, Shopkeeper }

        public static Actor Spawn(Archetype type, Vector3 pos, Quaternion rot, bool? femaleOverride = null)
        {
            bool female = femaleOverride ?? rng.NextDouble() < 0.45;
            if (type == Archetype.Tactical || type == Archetype.Firefighter) female = rng.NextDouble() < 0.2;
            var prefab = GameDatabase.I != null ? GameDatabase.I.Get(female ? "CHR_Female" : "CHR_Male") : null;
            if (prefab == null) prefab = GameDatabase.I != null ? GameDatabase.I.Get("CHR_Male") : null;
            if (prefab == null) return null;
            var go = Object.Instantiate(prefab, pos, rot);
            go.name = "NPC_" + type;
            Layers.SetRecursive(go, Layers.NPC);
            float scale = (float)(0.94 + rng.NextDouble() * 0.12);
            go.transform.localScale = Vector3.one * scale;
            var cc = go.GetComponent<CharacterController>() ?? go.AddComponent<CharacterController>();
            cc.height = 1.78f; cc.radius = 0.3f; cc.center = new Vector3(0f, 0.9f, 0f); cc.stepOffset = 0.4f; cc.slopeLimit = 50f; cc.skinWidth = 0.04f;
            var rig = go.GetComponent<CharacterRig>() ?? go.AddComponent<CharacterRig>();
            rig.Init();
            var look = go.GetComponent<CharacterAppearance>() ?? go.AddComponent<CharacterAppearance>();
            look.female = female;
            var actor = go.GetComponent<Actor>() ?? go.AddComponent<Actor>();
            var wc = go.GetComponent<WeaponController>() ?? go.AddComponent<WeaponController>();
            var brain = go.GetComponent<NPCBrain>() ?? go.AddComponent<NPCBrain>();
            actor.rig = rig; actor.look = look; actor.weapons = wc;
            wc.owner = actor;
            Outfit o;
            switch (type)
            {
                case Archetype.Police: o = CharacterAppearance.Police(rng, female); actor.faction = Faction.Police; brain.officer = true; brain.armed = true; brain.faction = Faction.Police; actor.maxHealth = actor.health = 140f; actor.armor = 40f; brain.bravery = 1f; brain.aggression = 0.8f; wc.infiniteAmmo = true; actor.displayName = "Officer"; break;
                case Archetype.Tactical: o = CharacterAppearance.Tactical(rng, female); actor.faction = Faction.Police; brain.officer = true; brain.tactical = true; brain.armed = true; brain.faction = Faction.Police; actor.maxHealth = actor.health = 180f; actor.armor = 100f; brain.bravery = 1f; brain.aggression = 1.3f; wc.infiniteAmmo = true; actor.displayName = "Tactical"; break;
                case Archetype.Gang: o = CharacterAppearance.Gang(rng, female); actor.faction = Faction.Gang; brain.armed = rng.NextDouble() < 0.7; brain.bravery = 0.9f; brain.aggression = 0.9f; brain.faction = Faction.Gang; wc.infiniteAmmo = true; actor.displayName = "Dock Rat"; break;
                case Archetype.Paramedic: o = CharacterAppearance.Paramedic(rng, female); actor.faction = Faction.Emergency; actor.displayName = "Paramedic"; break;
                case Archetype.Firefighter: o = CharacterAppearance.Firefighter(rng, female); actor.faction = Faction.Emergency; actor.displayName = "Firefighter"; break;
                case Archetype.Shopkeeper: o = CharacterAppearance.Shopkeeper(rng, female); actor.faction = Faction.Civilian; brain.armed = rng.NextDouble() < 0.4; brain.bravery = 0.8f; actor.displayName = "Clerk"; break;
                default: o = CharacterAppearance.Civilian(rng, female); actor.faction = Faction.Civilian; brain.bravery = (float)rng.NextDouble() * 0.5f; brain.armed = rng.NextDouble() < 0.06; actor.displayName = "Citizen"; break;
            }
            look.Apply(o);
            return actor;
        }

        public static Actor SpawnDriver(Vehicle v, Vector3 pos)
        {
            var type = v.def != null && v.def.police ? Archetype.Police : Archetype.Civilian;
            if (v.def != null && v.def.id == "swat") type = Archetype.Tactical;
            if (v.def != null && v.def.id == "ambulance") type = Archetype.Paramedic;
            if (v.def != null && v.def.id == "firetruck") type = Archetype.Firefighter;
            var a = Spawn(type, pos, v.transform.rotation);
            if (a == null) return null;
            var brain = a.GetComponent<NPCBrain>();
            brain.isDriverCiv = type == Archetype.Civilian;
            brain.EnterVehicle(v, 0);
            return a;
        }

        public static void AddPassenger(Vehicle v, Archetype type)
        {
            int seat = v.FreePassengerSeat();
            if (seat < 0) return;
            var a = Spawn(type, v.transform.position + Vector3.up * 2f, v.transform.rotation);
            if (a == null) return;
            a.GetComponent<NPCBrain>().EnterVehicle(v, seat);
        }
    }

    /// <summary>Spawns pedestrians on the sidewalk network around the player with simulation tiers and despawning.</summary>
    public class PopulationManager : MonoBehaviour
    {
        public static PopulationManager I;
        public static bool Enabled = true;
        public int maxDay = 46, maxNight = 24;
        readonly List<Actor> peds = new List<Actor>();
        float timer;
        readonly List<Vector3> sidewalk = new List<Vector3>();

        void Awake() { I = this; }

        public void Begin()
        {
            var net = RoadNetwork.I;
            if (net != null)
            {
                foreach (var l in net.lanes)
                {
                    var side = Vector3.Cross(Vector3.up, l.Dir);
                    int n = Mathf.Max(2, Mathf.RoundToInt(l.Length / 10f));
                    for (int i = 1; i < n; i++)
                    {
                        var p = l.Point((float)i / n) + side * (l.halfWidth + 3.1f);
                        p.y = U.GroundHeight(p + Vector3.up * 3f, p.y) + 0.05f;
                        sidewalk.Add(p);
                    }
                }
            }
            foreach (var p in WorldMarkers.ExtraPedSpots) sidewalk.Add(p);
        }

        void Update()
        {
            var pc = PlayerController.I;
            if (pc == null || GameManager.Paused) return;
            for (int i = peds.Count - 1; i >= 0; i--)
            {
                var a = peds[i];
                if (a == null) { peds.RemoveAt(i); continue; }
                float d = Vector3.Distance(a.transform.position, pc.transform.position);
                bool deadLong = a.IsDead && Time.time - a.lastDamageTime > 25f;
                if ((d > 130f && !a.InVehicle) || deadLong || (a.IsDead && d > 70f))
                {
                    peds.RemoveAt(i);
                    Destroy(a.gameObject);
                }
            }
            if (!Enabled) return;
            timer -= Time.deltaTime;
            if (timer > 0f) return;
            timer = 0.25f;
            int max = GameTime.IsDark ? maxNight : maxDay;
            if (Weather.Current == Weather.Kind.Rain || Weather.Current == Weather.Kind.Storm) max = Mathf.RoundToInt(max * 0.6f);
            if (peds.Count >= max || sidewalk.Count == 0) return;
            // refill quickly after a teleport / long drive, then trickle
            int budget = peds.Count < max / 2 ? 3 : 1;
            for (int k = 0; k < 40 && budget > 0; k++)
            {
                var p = sidewalk[Random.Range(0, sidewalk.Count)];
                float d = Vector3.Distance(p, pc.transform.position);
                if (d < 24f || d > 90f) continue;
                var cam = PlayerCamera.I != null ? PlayerCamera.I.cam : null;
                if (cam != null && d < 60f)
                {
                    var vp = cam.WorldToViewportPoint(p + Vector3.up);
                    if (vp.z > 0 && vp.x > 0 && vp.x < 1 && vp.y > 0 && vp.y < 1) continue;
                }
                var zone = WorldMarkers.ZoneAt(p);
                var type = NPCFactory.Archetype.Civilian;
                if (zone == "Ironside Yards" && Random.value < 0.18f) type = NPCFactory.Archetype.Gang;
                var a = NPCFactory.Spawn(type, p, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
                if (a != null) peds.Add(a);
                budget--;
            }
        }

        public void KillAll()
        {
            foreach (var p in peds) if (p != null) Destroy(p.gameObject);
            peds.Clear();
        }
    }
}

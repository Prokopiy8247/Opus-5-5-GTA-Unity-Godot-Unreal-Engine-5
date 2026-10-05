"""One-off source patch (segment 5): UI tab residue, range targets, load outfit, siren key, skill-up toasts,
horn variants, removal of no-op mod rows, animal death pose."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("UI/UIBuilder.cs", [
("""        public void Clear()
        {
            foreach (var b in buttons) if (b != null) UnityEngine.Object.Destroy(b.gameObject);
            buttons.Clear();
            y = 0f;
        }""",
 """        public void Clear()
        {
            // headers, sliders and labels are children of the content rect too, not only the tracked buttons
            for (int i = content.childCount - 1; i >= 0; i--)
            {
                var ch = content.GetChild(i).gameObject;
                ch.SetActive(false);
                UnityEngine.Object.Destroy(ch);
            }
            buttons.Clear();
            y = 0f;
        }"""),
])

edit("Save/SaveSystem.cs", [
("""                    for (int i = 0; i < d.weapons.Length; i++)
                    {
                        wc.owned.Add(d.weapons[i]);""",
 """                    for (int i = 0; i < d.weapons.Length; i++)
                    {
                        if (!wc.owned.Contains(d.weapons[i])) wc.owned.Add(d.weapons[i]);"""),
("""                    try { ps.outfit = JsonUtility.FromJson<Outfit>(d.outfitJson); } catch { }""",
 """                    try { ps.outfit = JsonUtility.FromJson<Outfit>(d.outfitJson); pc.actor.look?.Apply(ps.outfit); } catch { }"""),
])

edit("World/Activities.cs", [
("""                g.GetComponent<Collider>().isTrigger = true;""",
 """                g.layer = Layers.Prop;   // solid so hitscan bullets register (RangeTarget is IDamageable)"""),
("""    public class RangeTarget : MonoBehaviour
    {""",
 """    public class RangeTarget : MonoBehaviour, IDamageable
    {"""),
("""                if (respawn <= 0f) { transform.SetPositionAndRotation(home, rot); gameObject.SetActive(true); }""",
 """                if (respawn <= 0f) { transform.SetPositionAndRotation(home, rot); SetShown(true); }"""),
("""        void OnTriggerEnter(Collider c)
        {
            var act = c.GetComponentInParent<Actor>();
            if (act != null && act.IsPlayer) return;
            var bullets = c.GetComponentInParent<Projectile>();
            if (bullets == null && c.gameObject.layer != Layers.Projectile) return;
            Hit();
        }""",
 """        public void TakeDamage(DamageInfo d) { if (respawn <= 0f) Hit(); }

        void SetShown(bool on)
        {
            var r = GetComponent<Renderer>(); if (r) r.enabled = on;
            var c = GetComponent<Collider>(); if (c) c.enabled = on;
        }"""),
("""            gameObject.SetActive(false);
            respawn = 1.6f;""",
 """            SetShown(false);   // stays active so Update can respawn it
            respawn = 1.6f;"""),
])

edit("Player/PlayerController.cs", [
("""                if (GameInput.Down(Key.H) && v.def != null && v.def.siren) v.ToggleSiren();""",
 """                if (GameInput.Down(Key.N) && v.def != null && v.def.siren) v.ToggleSiren();   // H = horn, N = siren"""),
])

edit("Core/GameBootstrap.cs", [
("""            state.outfit = CharacterAppearance.PlayerDefault();""",
 """            state.outfit = CharacterAppearance.PlayerDefault();
            state.SkillUp += msg => HUD.Notify(msg, 2.2f);"""),
])

edit("Vehicles/Vehicle.cs", [
("""                if (h && !hornSrc.isPlaying) { hornSrc.Play(); WorldEvents.EmitNoise(transform.position, 25f, gameObject); }""",
 """                if (h && !hornSrc.isPlaying) { hornSrc.pitch = mods.horn == 1 ? 0.68f : mods.horn == 2 ? 1.38f : 1f; hornSrc.Play(); WorldEvents.EmitNoise(transform.position, 25f, gameObject); }"""),
])

edit("Vehicles/VehicleApi.cs", [
("""            menu.Row("Plate style " + (m.plate + 1) + "/4  - $50", () => { if (Pay(50)) { m.plate = (m.plate + 1) % 4; menu.SelectTab(0); } });
            menu.Row("Bulletproof tires: " + (m.bulletproofTires ? "FITTED" : "no") + "  - $2,500", () => { if (!m.bulletproofTires && Pay(2500)) m.bulletproofTires = true; menu.SelectTab(0); });
""", ""),
])

edit("World/Wildlife.cs", [
("""        void Update()
        {
            if (actor != null && actor.IsDead) return;
            float dt = Time.deltaTime;
            wanderTimer -= dt;""",
 """        bool deathPosed;

        void Update()
        {
            if (actor != null && actor.IsDead)
            {
                if (!deathPosed)
                {
                    // fall over on the side and stop all procedural motion (gait / wings)
                    deathPosed = true;
                    foreach (var g in GetComponentsInChildren<AnimalGait>()) g.enabled = false;
                    foreach (var f in GetComponentsInChildren<Flapper>()) f.enabled = false;
                    if (cc != null) cc.enabled = false;
                    transform.rotation = Quaternion.Euler(0f, transform.eulerAngles.y, aquatic ? 180f : 88f);
                    if (!aquatic) transform.position = new Vector3(transform.position.x, U.GroundHeight(transform.position + Vector3.up, transform.position.y) + 0.15f, transform.position.z);
                }
                return;
            }
            float dt = Time.deltaTime;
            wanderTimer -= dt;"""),
])
print("patched misc")

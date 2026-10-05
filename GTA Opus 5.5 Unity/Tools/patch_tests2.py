"""One-off patch (segment 5): pedestrian spawn rate + autotest robustness/diagnostics."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("AI/Population.cs", [
("""            timer = 0.35f;
            int max = GameTime.IsDark ? maxNight : maxDay;""",
 """            timer = 0.25f;
            int max = GameTime.IsDark ? maxNight : maxDay;"""),
("""            if (peds.Count >= max || sidewalk.Count == 0) return;
            for (int k = 0; k < 6; k++)
            {
                var p = sidewalk[Random.Range(0, sidewalk.Count)];
                float d = Vector3.Distance(p, pc.transform.position);
                if (d < 32f || d > 95f) continue;""",
 """            if (peds.Count >= max || sidewalk.Count == 0) return;
            // refill quickly after a teleport / long drive, then trickle
            int budget = peds.Count < max / 2 ? 3 : 1;
            for (int k = 0; k < 40 && budget > 0; k++)
            {
                var p = sidewalk[Random.Range(0, sidewalk.Count)];
                float d = Vector3.Distance(p, pc.transform.position);
                if (d < 24f || d > 90f) continue;"""),
("""                var a = NPCFactory.Spawn(type, p, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
                if (a != null) peds.Add(a);
                break;""",
 """                var a = NPCFactory.Spawn(type, p, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
                if (a != null) peds.Add(a);
                budget--;"""),
])

edit("Core/AutoTester.cs", [
# stop with the handbrake before exiting (F at speed is a deliberate bail-out)
("""            GameInput.SimMove = Vector2.zero;
            yield return new WaitForSeconds(1.5f);
            GameInput.SimPress(Key.F);
            yield return new WaitForSeconds(1.6f);""",
 """            GameInput.SimMove = Vector2.zero;
            GameInput.SimHold(Key.Space, true);
            for (float t = 0; t < 6f && v.SpeedKmh > 3f; t += Time.deltaTime) yield return null;
            GameInput.SimHold(Key.Space, false);
            yield return new WaitForSeconds(0.5f);
            GameInput.SimPress(Key.F);
            yield return new WaitForSeconds(1.6f);"""),
# pedestrians: give the population manager time to fill the area
("""            pc.Teleport(WorldMarkers.Downtown + new Vector3(4f, 1f, 4f), 0f);
            yield return new WaitForSeconds(3f);
            int near = 0, walking = 0;""",
 """            pc.Teleport(WorldMarkers.Downtown + new Vector3(4f, 1f, 4f), 0f);
            yield return new WaitForSeconds(9f);
            int near = 0, walking = 0;"""),
# rpg: make sure a rocket is chambered
("""            pc.weapons.Give("rpg", 4, true);
            yield return new WaitForSeconds(1.7f);""",
 """            pc.weapons.Give("rpg", 4, true);
            yield return new WaitForSeconds(1.7f);
            if (pc.weapons.Clip == 0) { pc.weapons.Reload(); yield return new WaitForSeconds(3.5f); }"""),
# melee: the player swings where the camera looks, so turn the camera toward the target
("""                pc.transform.rotation = Quaternion.LookRotation(U.Flat(npc.transform.position - pc.transform.position).normalized);
                GameInput.SimFirePress();
                yield return new WaitForSeconds(0.7f);""",
 """                var toN = U.Flat(npc.transform.position - pc.transform.position).normalized;
                if (PlayerCamera.I != null) PlayerCamera.I.yaw = Quaternion.LookRotation(toN).eulerAngles.y;
                pc.transform.rotation = Quaternion.LookRotation(toN);
                GameInput.SimFirePress();
                yield return new WaitForSeconds(0.8f);
                Log("melee swing " + i + ": npc dist=" + Vector3.Distance(npc.transform.position, pc.transform.position).ToString("F1") + " hp=" + npc.health.ToString("F0") + " weapon=" + pc.weapons.currentId + " state=" + pc.state);"""),
# wanted: a fresh victim in clear view, count witnesses
("""            Actor victim = null; float best = 40f;
            foreach (var a in Actor.All) if (a != null && !a.IsPlayer && !a.IsDead && a.faction == Faction.Civilian && a.vehicle == null) { float d = Vector3.Distance(a.transform.position, pc.transform.position); if (d < best) { best = d; victim = a; } }
            if (victim == null) victim = NPCFactory.Spawn(NPCFactory.Archetype.Civilian, pc.transform.position + pc.transform.forward * 6f, Quaternion.identity);""",
 """            int witnesses = 0;
            foreach (var a in Actor.All) if (a != null && !a.IsPlayer && !a.IsDead && a.faction != Faction.Animal && Vector3.Distance(a.transform.position, pc.transform.position) < 40f) witnesses++;
            var victim = NPCFactory.Spawn(NPCFactory.Archetype.Civilian, pc.transform.position + pc.transform.forward * 5f, Quaternion.LookRotation(-pc.transform.forward));
            if (PlayerCamera.I != null) PlayerCamera.I.yaw = pc.transform.eulerAngles.y;
            Log("wanted test: people within 40 m = " + witnesses);"""),
("""            for (int i = 0; i < 6 && victim != null && !victim.IsDead; i++) { pc.weapons.Fire(victim.Center, 0.2f, true); yield return new WaitForSeconds(0.3f); }""",
 """            for (int i = 0; i < 10 && victim != null && !victim.IsDead; i++) { pc.weapons.Fire(victim.Center, 0.05f, true); yield return new WaitForSeconds(0.35f); }"""),
# plane: diagnostics
("""            GameInput.SimMove = new Vector2(0f, -0.8f);           // pull up""",
 """            var pv = v as PlaneVehicle;
            Log("plane diag: destroyed=" + v.IsDestroyed + " hp=" + v.health.ToString("F0") + " engine=" + v.engineOn + " driver=" + (v.Driver != null) + " kinematic=" + v.Rb.isKinematic
                + " vel=" + v.Rb.linearVelocity.ToString("F1") + " lever=" + (pv != null ? pv.ThrottleLever.ToString("F2") : "-") + " lift=" + v.input.lift.ToString("F1") + " pos=" + v.transform.position.ToString("F1") + " state=" + pc.state);
            GameInput.SimMove = new Vector2(0f, -0.8f);           // pull up"""),
# burning vehicles explode after their burn timer
("""            for (float t = 0; t < 6f && v != null && !v.IsDestroyed; t += 0.5f) yield return new WaitForSeconds(0.5f);""",
 """            for (float t = 0; t < 14f && v != null && !v.IsDestroyed; t += 0.5f) yield return new WaitForSeconds(0.5f);"""),
])
print("patched tests2")

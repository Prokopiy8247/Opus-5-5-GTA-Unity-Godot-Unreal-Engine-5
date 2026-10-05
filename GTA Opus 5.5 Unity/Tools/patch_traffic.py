"""One-off source patch (segment 5): traffic turns at junctions and brakes for people in its lane."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("Traffic/VehicleAI.cs", [
("""                // pick the next lane, avoiding a U-turn if possible
                int pick = l.next[0];
                var cur = net.lanes[lane];
                for (int i = 0; i < l.next.Count; i++)
                {
                    var cand = net.lanes[l.next[i]];
                    if (Vector3.Dot(cur.Dir, cand.Dir) > 0.2f) { pick = l.next[i]; break; }
                }""",
 """                // pick the next lane: mostly straight on, sometimes a left/right turn, never a U-turn
                int pick = l.next[0];
                var cur = net.lanes[lane];
                int straight = -1; turnCands.Clear();
                for (int i = 0; i < l.next.Count; i++)
                {
                    float dot = Vector3.Dot(cur.Dir, net.lanes[l.next[i]].Dir);
                    if (dot > 0.7f) straight = l.next[i];
                    else if (dot > -0.5f) turnCands.Add(l.next[i]);
                }
                if (straight >= 0 && (turnCands.Count == 0 || Random.value < 0.6f)) pick = straight;
                else if (turnCands.Count > 0) pick = turnCands[Random.Range(0, turnCands.Count)];"""),
("""                var c = buf[i];
                var other = c.GetComponentInParent<Vehicle>();
                if (other == null || other == v || other.IsDestroyed) continue;""",
 """                var c = buf[i];
                var other = c.GetComponentInParent<Vehicle>();
                if (other == null)
                {
                    // people standing or walking in the lane ahead: slow down / stop and honk at the player
                    var who = c.GetComponentInParent<Actor>();
                    if (who == null || who.IsDead || who.vehicle != null || (police && pursuing && who.IsPlayer)) continue;
                    var tp = who.transform.position - transform.position;
                    if (Vector3.Dot(v.transform.forward, tp.normalized) < 0.6f || Mathf.Abs(Vector3.Dot(v.transform.right, tp)) > 1.9f) continue;
                    float dp = tp.magnitude;
                    wantSpeed = Mathf.Min(wantSpeed, Mathf.Max(0f, (dp - 4.5f) * 1.6f));
                    if (who.IsPlayer && hornCooldown <= 0f && dp < 10f) { hornCooldown = 3f; v.input.horn = true; Invoke(nameof(HornOff), 0.5f); }
                    continue;
                }
                if (other == v || other.IsDestroyed) continue;"""),
("""        float searchT; Vector3 searchOffset;""",
 """        float searchT; Vector3 searchOffset;
        static readonly System.Collections.Generic.List<int> turnCands = new System.Collections.Generic.List<int>();"""),
])
print("patched traffic")

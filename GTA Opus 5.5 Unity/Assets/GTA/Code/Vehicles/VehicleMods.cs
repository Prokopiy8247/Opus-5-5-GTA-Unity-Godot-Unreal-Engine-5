using System;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Data-driven vehicle modification state (docs: "use data-driven upgrade definitions").</summary>
    [Serializable]
    public class VehicleMods
    {
        // cosmetic
        public string paint = "#d64a3b", paint2 = "#f2efe6", wheelColor = "#b9c0c7";
        public int finish;      // 0 gloss, 1 matte, 2 metallic, 3 chrome
        public int wheelType;   // 0 stock, 1 sport, 2 offroad, 3 chrome
        public int tint;        // 0..3 window tint
        public int spoiler;     // 0 none, 1 lip, 2 wing
        public bool hood, skirts, bumper, exhaust, grille, roof, livery;
        public int plate;
        public int horn;        // 0 standard, 1 truck, 2 sports
        // performance (levels 0..3)
        public int engine, brakes, suspension, transmission, turbo, armor, tires;
        public bool bulletproofTires;
        public int lightsTint;  // 0 stock, 1 xenon, 2 amber

        public Color? LightsColor => lightsTint == 1 ? new Color(0.85f, 0.93f, 1f) : lightsTint == 2 ? new Color(1f, 0.82f, 0.5f) : (Color?)null;

        public float ArmorMul => 1f - armor * 0.14f;
        public float TorqueMul => 1f + engine * 0.16f + turbo * 0.14f;
        public float TopSpeedMul => 1f + engine * 0.05f + transmission * 0.04f + turbo * 0.05f;
        public float BrakeMul => 1f + brakes * 0.18f;
        public float GripMul => 1f + tires * 0.06f + suspension * 0.03f;
        public float SteerMul => 1f + suspension * 0.05f - transmission * 0.02f;
        public float DownforceMul => 1f + (spoiler == 2 ? 0.45f : spoiler == 1 ? 0.2f : 0f);

        public void ApplyFinish(Material m)
        {
            if (m == null) return;
            float smooth = finish == 1 ? 0.25f : finish == 0 ? 0.72f : 0.62f;
            float metal = finish == 2 ? 0.55f : finish == 3 ? 1f : 0.15f;
            if (finish == 1) { var c = m.GetColor("_BaseColor"); m.SetColor("_BaseColor", new Color(c.r, c.g, c.b, 1f)); }
            m.SetFloat("_Smoothness", smooth);
            m.SetFloat("_Metallic", metal);
        }

        public VehicleMods Clone() => (VehicleMods)MemberwiseClone();

        public string ToJson() => JsonUtility.ToJson(this);
        public static VehicleMods FromJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return new VehicleMods();
            try { return JsonUtility.FromJson<VehicleMods>(s) ?? new VehicleMods(); } catch { return new VehicleMods(); }
        }
    }

    /// <summary>Wheel/rim variants (material + geometry variants authored in Blender).</summary>
    public static class WheelKit
    {
        public static void Apply(Vehicle v, int type)
        {
            foreach (var w in v.WheelVisuals())
            {
                foreach (var r in w.GetComponentsInChildren<Renderer>(true))
                {
                    foreach (var m in r.materials)
                    {
                        if (m.name.StartsWith("M_Rim"))
                        {
                            if (type == 1) { m.SetColor("_BaseColor", new Color(0.35f, 0.36f, 0.38f)); m.SetFloat("_Metallic", 0.85f); m.SetFloat("_Smoothness", 0.45f); }
                            else if (type == 2) { m.SetColor("_BaseColor", new Color(0.62f, 0.58f, 0.5f)); m.SetFloat("_Metallic", 0.2f); m.SetFloat("_Smoothness", 0.25f); }
                            else if (type == 3) { m.SetColor("_BaseColor", new Color(0.95f, 0.96f, 0.98f)); m.SetFloat("_Metallic", 1f); m.SetFloat("_Smoothness", 0.85f); }
                            else { m.SetColor("_BaseColor", new Color(0.72f, 0.75f, 0.78f)); m.SetFloat("_Metallic", 0.85f); m.SetFloat("_Smoothness", 0.6f); }
                        }
                        if (m.name.StartsWith("M_Tire"))
                        {
                            if (type == 2) m.SetColor("_BaseColor", new Color(0.1f, 0.1f, 0.1f));
                        }
                    }
                }
                if (type == 2) w.localScale = Vector3.one * 1.08f;
                else if (Mathf.Approximately(w.localScale.x, 1.08f)) w.localScale = Vector3.one;
            }
        }
    }
}

using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    [Serializable]
    public class Outfit
    {
        public int hair;              // 0 short,1 long,2 bun,3 buzz,4 curly,-1 none
        public int hat = -1;          // 0 cap,1 beanie,2 police,3 tactical helmet
        public bool glasses, beard, longSleeves, shorts, vest, dutyBelt, badge, apron;
        public Color skin, hairColor, top, bottom, shoes, acc, acc2;

        public Outfit Clone() => (Outfit)MemberwiseClone();
    }

    /// <summary>Applies outfits (material colour variants + Blender-authored accessory meshes) to a character.</summary>
    public class CharacterAppearance : MonoBehaviour
    {
        public bool female;
        public Outfit current;
        readonly Dictionary<string, Material> inst = new Dictionary<string, Material>();
        readonly Dictionary<string, GameObject> acc = new Dictionary<string, GameObject>();
        bool init;
        [NonSerialized] public bool parachute, scuba;

        static readonly string[] HairRoles = { "HAIR_Short", "HAIR_Long", "HAIR_Bun", "HAIR_Buzz", "HAIR_Curly" };
        static readonly string[] HatRoles = { "HAT_Cap", "HAT_Beanie", "HAT_Police", "HELMET_Tactical" };

        public static readonly string[] SkinTones = { "#f1c9a5", "#e0ac84", "#c68863", "#a8704b", "#7d4f33", "#5b3a26" };
        public static readonly string[] HairTones = { "#1d1a17", "#3b2a20", "#6b4428", "#a8743d", "#d8b46a", "#8c8c8c", "#b5462f" };
        public static readonly string[] Tops = { "#2a9d8f", "#e76f51", "#f4a261", "#e9c46a", "#264653", "#f1faee", "#8ecae6", "#ff006e", "#6a4c93", "#ef476f", "#118ab2", "#3a5a40" };
        public static readonly string[] Bottoms = { "#2f3e56", "#3d3d3d", "#6b705c", "#b7b7a4", "#1d3557", "#5e503f", "#e5e5e5", "#7f5539" };
        public static readonly string[] Shoes = { "#e9e4da", "#222222", "#7f5539", "#e63946", "#f1faee", "#264653" };

        void Init()
        {
            if (init) return;
            init = true;
            foreach (var r in GetComponentsInChildren<Renderer>(true))
            {
                var role = U.Role(r.transform);
                if (role.StartsWith("HAIR_") || role.StartsWith("HAT_") || role.StartsWith("HELMET_") || role == "GLASSES_Sun" || role == "BEARD" ||
                    role.StartsWith("VEST_") || role.StartsWith("BELT_") || role == "BADGE" || role.StartsWith("PACK_") || role.StartsWith("SCUBA_") || role == "APRON")
                    acc[role] = r.gameObject;
                var mats = r.sharedMaterials;
                for (int i = 0; i < mats.Length; i++)
                {
                    if (mats[i] == null) continue;
                    var n = mats[i].name.Replace(" (Instance)", "");
                    if (!inst.TryGetValue(n, out var m)) { m = new Material(mats[i]) { name = n + "_inst" }; inst[n] = m; }
                    mats[i] = m;
                }
                r.sharedMaterials = mats;
            }
        }

        void SetColor(string mat, Color c)
        {
            if (inst.TryGetValue(mat, out var m)) m.SetColor("_BaseColor", c);
        }

        void Show(string role, bool on)
        {
            if (acc.TryGetValue(role, out var g)) g.SetActive(on);
        }

        public void Apply(Outfit o)
        {
            Init();
            current = o;
            for (int i = 0; i < HairRoles.Length; i++) Show(HairRoles[i], o.hair == i && (o.hat < 2 || i == 1 || i == 2));
            for (int i = 0; i < HatRoles.Length; i++) Show(HatRoles[i], o.hat == i);
            if (o.hat >= 2 && o.hair != 1) for (int i = 0; i < HairRoles.Length; i++) Show(HairRoles[i], false);
            Show("GLASSES_Sun", o.glasses && !scuba);
            Show("BEARD", o.beard && !female);
            Show("VEST_Tactical", o.vest);
            Show("BELT_Duty", o.dutyBelt);
            Show("BADGE", o.badge);
            Show("APRON", o.apron);
            Show("PACK_Parachute", parachute && !scuba);
            Show("SCUBA_Tank", scuba);
            Show("SCUBA_Mask", scuba);
            SetColor("M_Skin", o.skin);
            SetColor("M_Hair", o.hairColor);
            SetColor("M_Top", o.top);
            SetColor("M_Bottom", o.bottom);
            SetColor("M_Shoes", o.shoes);
            SetColor("M_Sleeve", o.longSleeves ? o.top : o.skin);
            SetColor("M_Legs", o.shorts ? o.skin : o.bottom);
            SetColor("M_Accessory", o.acc);
            SetColor("M_Accessory2", o.acc2);
            SetColor("M_Vest", o.hat == 3 || o.vest ? new Color(0.16f, 0.17f, 0.19f) : o.acc2);
        }

        public void SetGear(bool para, bool sc)
        {
            parachute = para; scuba = sc;
            if (current != null) Apply(current);
        }

        static Color P(System.Random r, string[] a) => U.Hex(a[r.Next(a.Length)]);

        public static Outfit Civilian(System.Random r, bool female)
        {
            var o = new Outfit
            {
                skin = P(r, SkinTones), hairColor = P(r, HairTones), top = P(r, Tops), bottom = P(r, Bottoms), shoes = P(r, Shoes),
                acc = P(r, Tops), acc2 = P(r, Bottoms),
                longSleeves = r.NextDouble() < 0.35, shorts = r.NextDouble() < 0.25,
                glasses = r.NextDouble() < 0.18, beard = !female && r.NextDouble() < 0.3,
            };
            o.hair = female ? new[] { 1, 1, 2, 4, 0 }[r.Next(5)] : new[] { 0, 0, 3, 4, 3, -1 }[r.Next(6)];
            double h = r.NextDouble();
            o.hat = h < 0.15 ? 0 : (h < 0.22 ? 1 : -1);
            return o;
        }

        public static Outfit Police(System.Random r, bool female)
        {
            var o = Civilian(r, female);
            o.top = U.Hex("#2b3a67"); o.bottom = U.Hex("#1f2a44"); o.shoes = U.Hex("#141414"); o.acc2 = U.Hex("#1f2a44");
            o.longSleeves = r.NextDouble() < 0.5; o.shorts = false; o.hat = 2; o.dutyBelt = true; o.badge = true; o.glasses = r.NextDouble() < 0.25;
            if (o.hair != 1) o.hair = 3;
            return o;
        }

        public static Outfit Tactical(System.Random r, bool female)
        {
            var o = Police(r, female);
            o.top = U.Hex("#2d3033"); o.bottom = U.Hex("#25282b"); o.longSleeves = true; o.hat = 3; o.vest = true; o.badge = false; o.glasses = false;
            return o;
        }

        public static Outfit Paramedic(System.Random r, bool female)
        {
            var o = Civilian(r, female);
            o.top = U.Hex("#f8f9fa"); o.bottom = U.Hex("#1d3557"); o.longSleeves = false; o.shorts = false; o.hat = -1; o.dutyBelt = true;
            return o;
        }

        public static Outfit Firefighter(System.Random r, bool female)
        {
            var o = Civilian(r, female);
            o.top = U.Hex("#c9a227"); o.bottom = U.Hex("#2b2b2b"); o.longSleeves = true; o.shorts = false; o.hat = 3; o.acc2 = U.Hex("#d00000"); o.vest = false;
            return o;
        }

        public static Outfit Shopkeeper(System.Random r, bool female)
        {
            var o = Civilian(r, female);
            o.apron = true; o.acc = U.Hex("#2a9d8f"); o.hat = -1;
            return o;
        }

        public static Outfit Gang(System.Random r, bool female)
        {
            var o = Civilian(r, female);
            o.top = U.Hex(r.NextDouble() < 0.5 ? "#7b2cbf" : "#9d0208"); o.longSleeves = true; o.hat = r.NextDouble() < 0.6 ? 1 : 0;
            o.acc = o.top; o.bottom = U.Hex("#1b1b1b");
            return o;
        }

        public static Outfit PlayerDefault()
        {
            return new Outfit
            {
                hair = 0, hat = -1, skin = U.Hex("#c68863"), hairColor = U.Hex("#1d1a17"), top = U.Hex("#e76f51"), bottom = U.Hex("#264653"),
                shoes = U.Hex("#f1faee"), acc = U.Hex("#2a9d8f"), acc2 = U.Hex("#1f2a44"), longSleeves = false, shorts = false, beard = true,
            };
        }
    }
}

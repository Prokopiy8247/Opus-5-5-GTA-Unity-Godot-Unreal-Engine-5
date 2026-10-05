using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    public enum Skill { Stamina, Shooting, Strength, Stealth, Driving, Flying, Lung }

    [Serializable]
    public class StoredVehicle
    {
        public string id;
        public string mods; // serialized VehicleMods
    }

    /// <summary>Economy, use-based skill progression and personal gear of the player.</summary>
    public class PlayerState : MonoBehaviour
    {
        public static PlayerState I;
        public int money = 6500;
        public bool hasParachute = true, hasScuba;
        public float[] skills = new float[7];
        public List<StoredVehicle> garage = new List<StoredVehicle>();
        public Outfit outfit;
        public float appearanceChangedAt = -999f;
        public static readonly string[] SkillNames = { "Stamina", "Shooting", "Strength", "Stealth", "Driving", "Flying", "Lung Capacity" };
        public event Action<string> SkillUp;

        void Awake() { I = this; }

        public float Get(Skill s) => skills[(int)s];

        public void Train(Skill s, float amount)
        {
            int i = (int)s;
            float before = skills[i];
            skills[i] = Mathf.Clamp01(skills[i] + amount);
            if (Mathf.FloorToInt(before * 10f) != Mathf.FloorToInt(skills[i] * 10f)) SkillUp?.Invoke(SkillNames[i] + " increased");
        }

        public bool Spend(int amount)
        {
            if (money < amount) { HUD.Notify("Not enough cash (" + U.Money(amount) + ")"); return false; }
            money -= amount;
            AudioFX.Play("cash", 0.5f);
            return true;
        }

        public void Earn(int amount, string why = null)
        {
            money += amount;
            if (why != null) HUD.Notify("+" + U.Money(amount) + "  " + why);
        }

        public float LungSeconds => hasScuba ? 600f : Mathf.Lerp(16f, 45f, Get(Skill.Lung));
    }
}

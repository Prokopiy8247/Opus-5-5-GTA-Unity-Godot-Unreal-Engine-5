using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    // ------------------------------------------------------------------ weapons
    public enum WeaponClass { Melee, Pistol, SMG, Shotgun, Rifle, Sniper, Heavy, Thrown }
    public enum HoldType { Unarmed, OneHand, TwoHand, Melee, Shoulder, Throw }

    public class WeaponDef
    {
        public string id, name, model;
        public WeaponClass cls;
        public HoldType hold;
        public float damage, fireRate, range = 80f, hipSpread, aimSpread, recoil, reload = 1.5f, aimFov = 50f;
        public int mag = 1, pellets = 1, maxAmmo = 0, price, ammoPrice;
        public bool auto, projectile, driveBy, scope, sniperScope;
        public float projSpeed, blast, noise = 70f, knock = 1f, meleeRange = 1.6f;
        public bool canSuppress, canScope, canGrip, canLight, canExtMag;
        public bool IsMelee => cls == WeaponClass.Melee;
        public bool IsGun => !IsMelee && cls != WeaponClass.Thrown;
    }

    public static class WeaponCatalog
    {
        public static readonly List<WeaponDef> All = new List<WeaponDef>
        {
            new WeaponDef{ id="fists", name="Fists", cls=WeaponClass.Melee, hold=HoldType.Unarmed, damage=11, fireRate=2.4f, meleeRange=1.25f, noise=6, knock=0.6f },
            new WeaponDef{ id="knife", name="Dock Knife", model="WPN_Knife", cls=WeaponClass.Melee, hold=HoldType.Melee, damage=38, fireRate=2.1f, meleeRange=1.4f, noise=4, price=150, knock=0.5f },
            new WeaponDef{ id="bat", name="Ash Bat", model="WPN_Bat", cls=WeaponClass.Melee, hold=HoldType.Melee, damage=30, fireRate=1.5f, meleeRange=1.8f, noise=8, price=100, knock=1.6f },
            new WeaponDef{ id="crowbar", name="Pry Bar", model="WPN_Crowbar", cls=WeaponClass.Melee, hold=HoldType.Melee, damage=33, fireRate=1.6f, meleeRange=1.65f, noise=8, price=120, knock=1.3f },
            new WeaponDef{ id="pistol", name="Harbor 9 Pistol", model="WPN_Pistol", cls=WeaponClass.Pistol, hold=HoldType.OneHand, damage=22, fireRate=5f, range=70, hipSpread=2.4f, aimSpread=0.55f, recoil=2.2f, reload=1.3f, mag=12, maxAmmo=180, price=600, ammoPrice=60, driveBy=true, aimFov=52, canSuppress=true, canLight=true, canExtMag=true, canScope=true },
            new WeaponDef{ id="revolver", name="Breaker .44", model="WPN_Revolver", cls=WeaponClass.Pistol, hold=HoldType.OneHand, damage=58, fireRate=1.5f, range=80, hipSpread=3f, aimSpread=0.4f, recoil=6f, reload=2.3f, mag=6, maxAmmo=90, price=1250, ammoPrice=90, driveBy=true, aimFov=50, knock=1.4f, canScope=true },
            new WeaponDef{ id="smg", name="Wasp SMG", model="WPN_SMG", cls=WeaponClass.SMG, hold=HoldType.OneHand, damage=15, fireRate=12f, range=55, hipSpread=4f, aimSpread=1.6f, recoil=1.1f, reload=1.7f, mag=30, maxAmmo=360, auto=true, price=1800, ammoPrice=80, driveBy=true, aimFov=52, canSuppress=true, canGrip=true, canLight=true, canExtMag=true, canScope=true },
            new WeaponDef{ id="shotgun", name="Pelican Pump", model="WPN_Shotgun", cls=WeaponClass.Shotgun, hold=HoldType.TwoHand, damage=13, pellets=8, fireRate=1.1f, range=32, hipSpread=6.5f, aimSpread=4.5f, recoil=7f, reload=2.6f, mag=6, maxAmmo=72, price=1500, ammoPrice=90, aimFov=55, knock=1.8f, canSuppress=true, canLight=true, canGrip=true },
            new WeaponDef{ id="autoshotgun", name="Squall Auto-12", model="WPN_AutoShotgun", cls=WeaponClass.Shotgun, hold=HoldType.TwoHand, damage=11, pellets=7, fireRate=3.6f, range=28, hipSpread=7f, aimSpread=5f, recoil=5f, reload=2.4f, mag=10, maxAmmo=80, auto=true, price=3200, ammoPrice=120, aimFov=55, knock=1.5f, canExtMag=true, canLight=true, canGrip=true },
            new WeaponDef{ id="rifle", name="Gale Assault Rifle", model="WPN_Rifle", cls=WeaponClass.Rifle, hold=HoldType.TwoHand, damage=26, fireRate=9f, range=120, hipSpread=3.2f, aimSpread=0.85f, recoil=1.6f, reload=2.0f, mag=30, maxAmmo=360, auto=true, price=3500, ammoPrice=110, aimFov=45, canSuppress=true, canScope=true, canGrip=true, canLight=true, canExtMag=true },
            new WeaponDef{ id="carbine", name="Tern Carbine", model="WPN_Carbine", cls=WeaponClass.Rifle, hold=HoldType.TwoHand, damage=24, fireRate=10.5f, range=110, hipSpread=2.8f, aimSpread=0.7f, recoil=1.35f, reload=1.9f, mag=30, maxAmmo=360, auto=true, price=3000, ammoPrice=110, aimFov=46, canSuppress=true, canScope=true, canGrip=true, canLight=true, canExtMag=true },
            new WeaponDef{ id="dmr", name="Osprey Marksman", model="WPN_DMR", cls=WeaponClass.Rifle, hold=HoldType.TwoHand, damage=58, fireRate=3f, range=200, hipSpread=2.5f, aimSpread=0.2f, recoil=3.6f, reload=2.3f, mag=10, maxAmmo=120, price=4500, ammoPrice=140, aimFov=28, scope=true, canSuppress=true, canGrip=true, canExtMag=true },
            new WeaponDef{ id="sniper", name="Albatross Sniper", model="WPN_Sniper", cls=WeaponClass.Sniper, hold=HoldType.TwoHand, damage=150, fireRate=0.85f, range=400, hipSpread=5f, aimSpread=0.03f, recoil=8f, reload=2.8f, mag=5, maxAmmo=60, price=6000, ammoPrice=150, aimFov=11, scope=true, sniperScope=true, canSuppress=true, knock=2f },
            new WeaponDef{ id="grenade", name="Frag Grenade", model="WPN_Grenade", cls=WeaponClass.Thrown, hold=HoldType.Throw, damage=160, fireRate=1f, mag=1, maxAmmo=15, projectile=true, projSpeed=17, blast=7.5f, price=250, ammoPrice=250, noise=120, driveBy=true },
            new WeaponDef{ id="rpg", name="Harpoon Rocket Launcher", model="WPN_RocketLauncher", cls=WeaponClass.Heavy, hold=HoldType.Shoulder, damage=260, fireRate=0.6f, range=300, hipSpread=2f, aimSpread=0.3f, recoil=6f, reload=2.6f, mag=1, maxAmmo=12, projectile=true, projSpeed=55, blast=8.5f, price=8000, ammoPrice=400, aimFov=45, noise=150 },
            new WeaponDef{ id="gl", name="Thunderhead Grenade Launcher", model="WPN_GrenadeLauncher", cls=WeaponClass.Heavy, hold=HoldType.TwoHand, damage=170, fireRate=1.2f, range=150, hipSpread=2f, aimSpread=0.6f, recoil=4f, reload=3f, mag=6, maxAmmo=36, projectile=true, projSpeed=30, blast=6.5f, price=6000, ammoPrice=300, aimFov=48, noise=120 },
        };

        static Dictionary<string, WeaponDef> map;
        public static WeaponDef Get(string id)
        {
            if (map == null) { map = new Dictionary<string, WeaponDef>(); foreach (var w in All) map[w.id] = w; }
            map.TryGetValue(id ?? "", out var d);
            return d;
        }
    }

    // ------------------------------------------------------------------ vehicles
    public enum VehicleKind { Car, Bike, Bicycle, Boat, Heli, Plane }

    public class VehicleDef
    {
        public string id, name, model, cls;
        public VehicleKind kind;
        public float mass = 1350, torque = 520, topSpeed = 52, brake = 3600, steer = 34, grip = 1.0f, comY = -0.25f, health = 1000, drift = 1f;
        public int drive = 1; // 0 FWD, 1 RWD, 2 AWD
        public int price = 20000;
        public bool police, emergency, taxi, siren, convertible, heavy, armored;
        public string[] paints = { "#d64a3b" };
        public string radioStyle = "any";
    }

    public static class VehicleCatalog
    {
        public static readonly List<VehicleDef> All = new List<VehicleDef>
        {
            new VehicleDef{ id="compact", name="Minnow Hatch", model="VEH_Compact", cls="Compact", kind=VehicleKind.Car, mass=1050, torque=380, topSpeed=44, steer=36, grip=1.05f, drive=0, price=12000, paints=new[]{"#e9c46a","#2a9d8f","#f4a261","#8ecae6","#e5e5e5","#e76f51"} },
            new VehicleDef{ id="sedan", name="Coastline Sedan", model="VEH_Sedan", cls="Sedan", kind=VehicleKind.Car, mass=1400, torque=500, topSpeed=50, steer=33, grip=1.0f, drive=1, price=18000, paints=new[]{"#d64a3b","#264653","#e5e5e5","#3d405b","#6d6875","#1d3557","#b5838d"} },
            new VehicleDef{ id="sports", name="Riptide GT", model="VEH_Sports", cls="Sports", kind=VehicleKind.Car, mass=1250, torque=820, topSpeed=68, steer=32, grip=1.25f, drive=2, comY=-0.32f, price=95000, paints=new[]{"#ffb703","#e63946","#06d6a0","#118ab2","#f1faee","#7209b7"} },
            new VehicleDef{ id="muscle", name="Bayou Thunder", model="VEH_Muscle", cls="Muscle", kind=VehicleKind.Car, mass=1550, torque=900, topSpeed=62, steer=31, grip=0.92f, drive=1, drift=1.35f, price=48000, paints=new[]{"#2b2d42","#ef233c","#ff9f1c","#3a86ff","#f8f9fa"} },
            new VehicleDef{ id="suv", name="Ridgeback SUV", model="VEH_SUV", cls="SUV", kind=VehicleKind.Car, mass=2100, torque=760, topSpeed=48, steer=33, grip=1.0f, drive=2, comY=-0.15f, price=42000, paints=new[]{"#2f3e46","#e5e5e5","#7f5539","#283618","#14213d"} },
            new VehicleDef{ id="pickup", name="Dustline Pickup", model="VEH_Pickup", cls="Pickup", kind=VehicleKind.Car, mass=1900, torque=700, topSpeed=46, steer=33, grip=0.98f, drive=2, comY=-0.12f, price=30000, paints=new[]{"#9c6644","#e5e5e5","#264653","#bc4749","#6a994e"} },
            new VehicleDef{ id="van", name="Packhorse Van", model="VEH_Van", cls="Van", kind=VehicleKind.Car, mass=2300, torque=620, topSpeed=40, steer=32, grip=0.95f, drive=1, comY=-0.1f, price=26000, paints=new[]{"#f1faee","#a8dadc","#457b9d","#e9c46a"} },
            new VehicleDef{ id="police", name="Halcyon PD Cruiser", model="VEH_Police", cls="Emergency", kind=VehicleKind.Car, mass=1600, torque=780, topSpeed=60, steer=33, grip=1.12f, drive=1, police=true, siren=true, price=0, paints=new[]{"#1f2a44"} },
            new VehicleDef{ id="taxi", name="Gull Cab", model="VEH_Taxi", cls="Sedan", kind=VehicleKind.Car, mass=1420, torque=500, topSpeed=48, steer=33, grip=1.0f, drive=1, taxi=true, price=16000, paints=new[]{"#ffd23f"} },
            new VehicleDef{ id="ambulance", name="Lifeline Ambulance", model="VEH_Ambulance", cls="Emergency", kind=VehicleKind.Car, mass=3000, torque=900, topSpeed=42, steer=31, grip=0.95f, drive=1, emergency=true, siren=true, heavy=true, price=0, paints=new[]{"#f8f9fa"} },
            new VehicleDef{ id="firetruck", name="Brigade Pumper", model="VEH_FireTruck", cls="Emergency", kind=VehicleKind.Car, mass=6500, torque=2200, topSpeed=36, steer=29, grip=0.95f, drive=1, emergency=true, siren=true, heavy=true, price=0, paints=new[]{"#c1121f"} },
            new VehicleDef{ id="truck", name="Longhaul Box Truck", model="VEH_Truck", cls="Industrial", kind=VehicleKind.Car, mass=5200, torque=1700, topSpeed=34, steer=30, grip=0.95f, drive=1, heavy=true, price=38000, paints=new[]{"#e9ecef","#f4a261","#2a9d8f"} },
            new VehicleDef{ id="swat", name="Bulwark Tactical", model="VEH_Swat", cls="Emergency", kind=VehicleKind.Car, mass=4200, torque=1500, topSpeed=40, steer=31, grip=1.0f, drive=2, police=true, siren=true, heavy=true, armored=true, health=2600, price=0, paints=new[]{"#22252a"} },
            new VehicleDef{ id="motorbike", name="Sparrow 600", model="VEH_Motorbike", cls="Motorcycle", kind=VehicleKind.Bike, mass=220, torque=200, topSpeed=58, steer=30, grip=1.1f, drive=1, health=600, price=14000, paints=new[]{"#e63946","#1d3557","#ffb703","#f1faee"} },
            new VehicleDef{ id="bicycle", name="Tidewind Bicycle", model="VEH_Bicycle", cls="Cycle", kind=VehicleKind.Bicycle, mass=60, torque=45, topSpeed=13, steer=34, grip=1.1f, drive=1, health=250, price=500, paints=new[]{"#2a9d8f","#e76f51","#264653"} },
            new VehicleDef{ id="speedboat", name="Marlin Speedboat", model="VEH_Speedboat", cls="Boat", kind=VehicleKind.Boat, mass=1300, torque=26000, topSpeed=30, steer=38, health=900, price=60000, paints=new[]{"#f1faee","#e63946","#118ab2"} },
            new VehicleDef{ id="heli", name="Kestrel Helicopter", model="VEH_Heli", cls="Helicopter", kind=VehicleKind.Heli, mass=1400, torque=0, topSpeed=55, health=900, price=250000, paints=new[]{"#f1faee","#e9c46a","#e76f51"} },
            new VehicleDef{ id="policeheli", name="HPD Skywatch", model="VEH_PoliceHeli", cls="Helicopter", kind=VehicleKind.Heli, mass=1900, topSpeed=60, police=true, health=1300, price=0, paints=new[]{"#1f2a44"} },
            new VehicleDef{ id="plane", name="Pelican Prop Plane", model="VEH_Plane", cls="Plane", kind=VehicleKind.Plane, mass=1100, topSpeed=72, health=800, price=180000, paints=new[]{"#f1faee","#e63946","#219ebc"} },
            new VehicleDef{ id="jet", name="Swiftwing Jet", model="VEH_Jet", cls="Plane", kind=VehicleKind.Plane, mass=4500, topSpeed=140, health=1200, price=900000, paints=new[]{"#adb5bd","#1d3557","#f1faee"} },
        };

        static Dictionary<string, VehicleDef> map;
        public static VehicleDef Get(string id)
        {
            if (map == null) { map = new Dictionary<string, VehicleDef>(); foreach (var v in All) map[v.id] = v; }
            map.TryGetValue(id ?? "", out var d);
            return d;
        }

        /// <summary>Vehicles whose prefab really exists in the generated database (no fake breadth).</summary>
        public static List<VehicleDef> Available()
        {
            var l = new List<VehicleDef>();
            foreach (var v in All) if (GameDatabase.I != null && GameDatabase.I.Has(v.model)) l.Add(v);
            return l;
        }
    }
}

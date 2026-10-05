#include "Core/GTATypes.h"
#include "Engine/StaticMesh.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/AnimSequence.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialParameterCollection.h"
#include "Sound/SoundBase.h"

DEFINE_LOG_CATEGORY(LogGTA);

namespace
{
	FGTAWeaponDef W(EGTAWeapon Id, const TCHAR* Name, EGTAWeaponCat Cat, float Dmg, float Interval, float Spread, int32 Clip, int32 MaxAmmo,
		float Range, bool bAuto, int32 Pellets, float Recoil, int32 Price, int32 AmmoPrice, bool bOneHanded, const TCHAR* Mesh, float MuzzleX,
		bool bModdable, float Reload = 1.6f, float Scope = 0.f, float Noise = 1.f)
	{
		FGTAWeaponDef D;
		D.Id = Id; D.Name = Name; D.Cat = Cat; D.Damage = Dmg; D.FireInterval = Interval; D.SpreadDeg = Spread; D.Clip = Clip; D.MaxAmmo = MaxAmmo;
		D.RangeM = Range; D.bAuto = bAuto; D.Pellets = Pellets; D.Recoil = Recoil; D.Price = Price; D.AmmoPrice = AmmoPrice; D.bOneHanded = bOneHanded;
		D.Mesh = Mesh; D.MuzzleX = MuzzleX; D.bModdable = bModdable; D.ReloadTime = Reload; D.ScopeFOV = Scope; D.Noise = Noise;
		return D;
	}

	TArray<FGTAWeaponDef> BuildWeapons()
	{
		TArray<FGTAWeaponDef> T;
		T.Add(W(EGTAWeapon::Fists, TEXT("Fists"), EGTAWeaponCat::Melee, 12, 0.45f, 0, 0, 0, 1.4f, false, 1, 0, 0, 0, true, TEXT(""), 0, false, 0, 0, 0.15f));
		T.Add(W(EGTAWeapon::Knife, TEXT("Tide Knife"), EGTAWeaponCat::Melee, 40, 0.5f, 0, 0, 0, 1.5f, false, 1, 0, 150, 0, true, TEXT("SM_Wpn_Knife"), 0.2f, false, 0, 0, 0.1f));
		T.Add(W(EGTAWeapon::Bat, TEXT("Slugger Bat"), EGTAWeaponCat::Melee, 30, 0.75f, 0, 0, 0, 1.9f, false, 1, 0, 120, 0, false, TEXT("SM_Wpn_Bat"), 0.8f, false, 0, 0, 0.15f));
		T.Add(W(EGTAWeapon::Pistol, TEXT("Vex P9 Pistol"), EGTAWeaponCat::Handgun, 24, 0.17f, 1.3f, 12, 240, 80, false, 1, 1.0f, 400, 30, true, TEXT("SM_Wpn_Pistol"), 0.18f, true, 1.2f));
		T.Add(W(EGTAWeapon::Revolver, TEXT("Hammer .44"), EGTAWeaponCat::Handgun, 58, 0.55f, 0.9f, 6, 120, 100, false, 1, 2.6f, 900, 40, true, TEXT("SM_Wpn_Revolver"), 0.24f, true, 2.0f));
		T.Add(W(EGTAWeapon::SMG, TEXT("Kite SMG"), EGTAWeaponCat::SMG, 17, 0.075f, 3.2f, 30, 360, 60, true, 1, 0.8f, 1500, 45, true, TEXT("SM_Wpn_SMG"), 0.28f, true, 1.5f));
		T.Add(W(EGTAWeapon::Shotgun, TEXT("Breaker 12 Pump"), EGTAWeaponCat::Shotgun, 13, 0.9f, 5.5f, 8, 80, 32, false, 8, 3.0f, 1800, 50, false, TEXT("SM_Wpn_Shotgun"), 0.62f, true, 2.2f));
		T.Add(W(EGTAWeapon::AutoShotgun, TEXT("Thunder Auto-12"), EGTAWeaponCat::Shotgun, 10, 0.28f, 6.5f, 10, 100, 28, true, 8, 2.2f, 3200, 60, false, TEXT("SM_Wpn_AutoShotgun"), 0.55f, true, 2.4f));
		T.Add(W(EGTAWeapon::AssaultRifle, TEXT("Tern AR"), EGTAWeaponCat::Rifle, 29, 0.105f, 1.9f, 30, 360, 160, true, 1, 1.2f, 3500, 60, false, TEXT("SM_Wpn_Rifle"), 0.58f, true, 1.9f));
		T.Add(W(EGTAWeapon::Carbine, TEXT("Skiff Carbine"), EGTAWeaponCat::Rifle, 26, 0.095f, 1.6f, 30, 360, 150, true, 1, 1.0f, 3000, 60, false, TEXT("SM_Wpn_Carbine"), 0.5f, true, 1.8f));
		T.Add(W(EGTAWeapon::MarksmanRifle, TEXT("Heron DMR"), EGTAWeaponCat::Rifle, 62, 0.42f, 0.45f, 10, 100, 320, false, 1, 2.0f, 5000, 70, false, TEXT("SM_Wpn_DMR"), 0.75f, true, 2.2f, 35.f));
		T.Add(W(EGTAWeapon::SniperRifle, TEXT("Albatross Sniper"), EGTAWeaponCat::Sniper, 150, 1.35f, 0.05f, 5, 50, 650, false, 1, 4.0f, 8000, 100, false, TEXT("SM_Wpn_Sniper"), 0.95f, true, 2.6f, 12.f));
		T.Add(W(EGTAWeapon::Grenade, TEXT("Frag Grenade"), EGTAWeaponCat::Throwable, 170, 0.9f, 0, 1, 10, 30, false, 1, 0, 250, 250, true, TEXT("SM_Wpn_Grenade"), 0.0f, false, 0.6f));
		T.Add(W(EGTAWeapon::RocketLauncher, TEXT("Gale Rocket Launcher"), EGTAWeaponCat::Heavy, 320, 1.4f, 0.4f, 1, 10, 400, false, 1, 4.0f, 12000, 800, false, TEXT("SM_Wpn_RPG"), 0.7f, false, 2.6f));
		T.Add(W(EGTAWeapon::GrenadeLauncher, TEXT("Mortar GL"), EGTAWeaponCat::Heavy, 150, 0.7f, 0.8f, 6, 30, 200, false, 1, 2.5f, 9000, 300, false, TEXT("SM_Wpn_GL"), 0.45f, false, 2.8f));
		for (FGTAWeaponDef& D : T)
		{
			if (D.Id == EGTAWeapon::Grenade || D.Id == EGTAWeapon::RocketLauncher || D.Id == EGTAWeapon::GrenadeLauncher)
			{
				D.bProjectile = true;
				D.ExplosionRadiusM = D.Id == EGTAWeapon::RocketLauncher ? 8.f : (D.Id == EGTAWeapon::Grenade ? 7.f : 6.f);
				D.Noise = 2.0f;
			}
		}
		return T;
	}

	FGTAVehicleDef V(EGTAVehicle Id, const TCHAR* Name, EGTAVehicleKind Kind, const TCHAR* Key, const TCHAR* Wheel,
		float L, float Wd, float H, float WB, float Tr, float WR, float Mass, float Force, float Kmh, float Grip, float Steer,
		int32 Seats, int32 Price, FLinearColor Paint)
	{
		FGTAVehicleDef D;
		D.Id = Id; D.Name = Name; D.Kind = Kind; D.Key = Key; D.Wheel = Wheel; D.Length = L; D.Width = Wd; D.Height = H;
		D.Wheelbase = WB; D.Track = Tr; D.WheelRadius = WR; D.MassKg = Mass; D.EngineForce = Force; D.MaxSpeedKmh = Kmh; D.Grip = Grip;
		D.SteerDeg = Steer; D.Seats = Seats; D.Price = Price; D.DefaultPaint = Paint; D.Health = 1000.f;
		return D;
	}

	TArray<FGTAVehicleDef> BuildVehicles()
	{
		TArray<FGTAVehicleDef> T;
		T.Add(V(EGTAVehicle::Compact, TEXT("Pico Hatch"), EGTAVehicleKind::Car, TEXT("Compact"), TEXT("Std"), 3.8f, 1.70f, 1.45f, 2.40f, 1.46f, 0.30f, 1050, 7600, 165, 0.98f, 37, 4, 9000, FLinearColor(0.85f, 0.55f, 0.05f)));
		T.Add(V(EGTAVehicle::Sedan, TEXT("Meridian Sedan"), EGTAVehicleKind::Car, TEXT("Sedan"), TEXT("Std"), 4.7f, 1.85f, 1.45f, 2.80f, 1.58f, 0.33f, 1400, 10500, 190, 1.0f, 34, 4, 16000, FLinearColor(0.08f, 0.18f, 0.45f)));
		T.Add(V(EGTAVehicle::Sports, TEXT("Vortex GT"), EGTAVehicleKind::Car, TEXT("Sports"), TEXT("Sport"), 4.5f, 1.95f, 1.18f, 2.65f, 1.68f, 0.35f, 1300, 16500, 275, 1.28f, 32, 2, 95000, FLinearColor(0.75f, 0.02f, 0.03f)));
		T.Add(V(EGTAVehicle::Muscle, TEXT("Brute 69"), EGTAVehicleKind::Car, TEXT("Muscle"), TEXT("Sport"), 4.9f, 1.92f, 1.30f, 2.85f, 1.62f, 0.36f, 1550, 15500, 240, 0.92f, 32, 2, 45000, FLinearColor(0.02f, 0.25f, 0.12f)));
		T.Add(V(EGTAVehicle::SUV, TEXT("Ridgeback SUV"), EGTAVehicleKind::Car, TEXT("SUV"), TEXT("Offroad"), 4.8f, 2.00f, 1.85f, 2.85f, 1.70f, 0.40f, 2100, 13500, 185, 1.02f, 33, 4, 38000, FLinearColor(0.05f, 0.05f, 0.055f)));
		T.Add(V(EGTAVehicle::Pickup, TEXT("Haul 1500 Pickup"), EGTAVehicleKind::Car, TEXT("Pickup"), TEXT("Offroad"), 5.4f, 2.00f, 1.85f, 3.30f, 1.72f, 0.40f, 2200, 13500, 178, 0.96f, 32, 2, 30000, FLinearColor(0.55f, 0.55f, 0.58f)));
		T.Add(V(EGTAVehicle::Van, TEXT("Courier Van"), EGTAVehicleKind::Car, TEXT("Van"), TEXT("Std"), 5.2f, 2.00f, 2.20f, 3.20f, 1.70f, 0.36f, 2300, 12000, 152, 0.9f, 32, 2, 22000, FLinearColor(0.85f, 0.85f, 0.85f)));
		T.Add(V(EGTAVehicle::Police, TEXT("Halcyon PD Cruiser"), EGTAVehicleKind::Car, TEXT("Police"), TEXT("Std"), 4.7f, 1.85f, 1.45f, 2.80f, 1.58f, 0.34f, 1500, 13500, 215, 1.12f, 34, 4, 0, FLinearColor(0.02f, 0.02f, 0.03f)));
		T.Add(V(EGTAVehicle::Taxi, TEXT("Halcyon Cab"), EGTAVehicleKind::Car, TEXT("Taxi"), TEXT("Std"), 4.7f, 1.85f, 1.45f, 2.80f, 1.58f, 0.33f, 1400, 10000, 185, 1.0f, 34, 4, 14000, FLinearColor(0.9f, 0.6f, 0.02f)));
		T.Add(V(EGTAVehicle::Ambulance, TEXT("Rescue Ambulance"), EGTAVehicleKind::Car, TEXT("Ambulance"), TEXT("Std"), 5.6f, 2.10f, 2.60f, 3.40f, 1.76f, 0.38f, 2800, 13500, 165, 0.92f, 32, 2, 0, FLinearColor(0.9f, 0.9f, 0.9f)));
		T.Add(V(EGTAVehicle::FireTruck, TEXT("Engine 7 Fire Truck"), EGTAVehicleKind::Car, TEXT("FireTruck"), TEXT("Truck"), 7.6f, 2.40f, 3.00f, 4.50f, 1.95f, 0.50f, 7000, 32000, 135, 0.85f, 30, 2, 0, FLinearColor(0.6f, 0.02f, 0.02f)));
		T.Add(V(EGTAVehicle::BoxTruck, TEXT("Lugger Box Truck"), EGTAVehicleKind::Car, TEXT("BoxTruck"), TEXT("Truck"), 6.8f, 2.30f, 3.00f, 4.20f, 1.90f, 0.48f, 5000, 25000, 140, 0.85f, 30, 2, 28000, FLinearColor(0.15f, 0.3f, 0.55f)));
		T.Add(V(EGTAVehicle::Tactical, TEXT("Bastion Tactical"), EGTAVehicleKind::Car, TEXT("Tactical"), TEXT("Offroad"), 5.6f, 2.30f, 2.40f, 3.40f, 1.92f, 0.46f, 4500, 27000, 165, 1.0f, 30, 4, 0, FLinearColor(0.04f, 0.045f, 0.05f)));
		T.Add(V(EGTAVehicle::Motorcycle, TEXT("Razor 600"), EGTAVehicleKind::Motorcycle, TEXT("Motorcycle"), TEXT("Bike"), 2.1f, 0.75f, 1.15f, 1.42f, 0.0f, 0.31f, 230, 4200, 215, 1.2f, 30, 2, 11000, FLinearColor(0.05f, 0.4f, 0.75f)));
		T.Add(V(EGTAVehicle::Bicycle, TEXT("Pedal BMX"), EGTAVehicleKind::Bicycle, TEXT("Bicycle"), TEXT("Bicycle"), 1.75f, 0.6f, 1.0f, 1.05f, 0.0f, 0.34f, 35, 900, 42, 1.1f, 35, 1, 400, FLinearColor(0.9f, 0.2f, 0.5f)));
		T.Add(V(EGTAVehicle::Speedboat, TEXT("Wavecutter Speedboat"), EGTAVehicleKind::Boat, TEXT("Speedboat"), TEXT(""), 7.0f, 2.4f, 1.6f, 0, 0, 0, 1800, 21000, 105, 1.0f, 30, 4, 32000, FLinearColor(0.9f, 0.9f, 0.92f)));
		T.Add(V(EGTAVehicle::Helicopter, TEXT("Kestrel Helicopter"), EGTAVehicleKind::Helicopter, TEXT("Heli"), TEXT(""), 11.0f, 2.4f, 3.2f, 0, 0, 0, 2200, 0, 230, 1.0f, 0, 4, 180000, FLinearColor(0.1f, 0.35f, 0.6f)));
		T.Add(V(EGTAVehicle::PoliceHeli, TEXT("Kestrel PD Air"), EGTAVehicleKind::Helicopter, TEXT("PoliceHeli"), TEXT(""), 11.0f, 2.4f, 3.2f, 0, 0, 0, 2300, 0, 240, 1.0f, 0, 4, 0, FLinearColor(0.02f, 0.02f, 0.03f)));
		T.Add(V(EGTAVehicle::PropPlane, TEXT("Gull Prop Plane"), EGTAVehicleKind::Plane, TEXT("PropPlane"), TEXT(""), 8.5f, 11.0f, 2.8f, 0, 0, 0, 1100, 7500, 290, 1.0f, 0, 2, 120000, FLinearColor(0.85f, 0.85f, 0.85f)));
		T.Add(V(EGTAVehicle::Jet, TEXT("Swift Jet"), EGTAVehicleKind::Plane, TEXT("Jet"), TEXT(""), 14.0f, 10.0f, 4.0f, 0, 0, 0, 7000, 85000, 720, 1.0f, 0, 1, 900000, FLinearColor(0.3f, 0.32f, 0.35f)));
		for (FGTAVehicleDef& D : T)
		{
			D.bPolice = (D.Id == EGTAVehicle::Police || D.Id == EGTAVehicle::PoliceHeli || D.Id == EGTAVehicle::Tactical);
			D.bEmergency = D.bPolice || D.Id == EGTAVehicle::Ambulance || D.Id == EGTAVehicle::FireTruck;
			D.bTaxi = D.Id == EGTAVehicle::Taxi;
			D.bArmored = D.Id == EGTAVehicle::Tactical;
			D.bConvertible = D.Id == EGTAVehicle::Sports || D.Id == EGTAVehicle::Muscle;
			if (D.Id == EGTAVehicle::Tactical) { D.Health = 3000.f; }
			if (D.Kind == EGTAVehicleKind::Car)
			{
				D.SeatX = -D.Wheelbase * 0.08f;
				D.SeatZ = FMath::Max(0.45f, D.WheelRadius + 0.18f);
				if (D.Id == EGTAVehicle::Van || D.Id == EGTAVehicle::BoxTruck || D.Id == EGTAVehicle::FireTruck || D.Id == EGTAVehicle::Ambulance)
				{
					D.SeatX = D.Wheelbase * 0.42f; D.SeatZ = 0.95f;
				}
				if (D.Id == EGTAVehicle::Tactical) { D.SeatX = D.Wheelbase * 0.2f; D.SeatZ = 0.95f; }
				if (D.Id == EGTAVehicle::Sports) { D.SeatZ = 0.38f; }
			}
			else if (D.Kind == EGTAVehicleKind::Motorcycle || D.Kind == EGTAVehicleKind::Bicycle)
			{
				D.SeatX = -0.15f; D.SeatZ = D.Kind == EGTAVehicleKind::Motorcycle ? 0.78f : 0.82f;
			}
			else if (D.Kind == EGTAVehicleKind::Boat) { D.SeatX = -0.6f; D.SeatZ = 0.6f; D.Health = 900.f; }
			else if (D.Kind == EGTAVehicleKind::Helicopter) { D.SeatX = 1.6f; D.SeatZ = 0.75f; D.Health = 900.f; }
			else if (D.Kind == EGTAVehicleKind::Plane) { D.SeatX = D.Id == EGTAVehicle::Jet ? 3.0f : 0.6f; D.SeatZ = D.Id == EGTAVehicle::Jet ? 1.6f : 1.05f; D.Health = 800.f; }
		}
		return T;
	}

	struct FNamedColor { const TCHAR* Name; FLinearColor C; };
	const FNamedColor GPaints[] = {
		{TEXT("Signal Red"), FLinearColor(0.75f, 0.02f, 0.03f)}, {TEXT("Sunset Orange"), FLinearColor(0.9f, 0.25f, 0.02f)},
		{TEXT("Taxi Yellow"), FLinearColor(0.9f, 0.6f, 0.02f)}, {TEXT("Lime"), FLinearColor(0.3f, 0.75f, 0.05f)},
		{TEXT("Racing Green"), FLinearColor(0.02f, 0.25f, 0.12f)}, {TEXT("Tide Teal"), FLinearColor(0.02f, 0.45f, 0.45f)},
		{TEXT("Ocean Blue"), FLinearColor(0.05f, 0.35f, 0.75f)}, {TEXT("Midnight Blue"), FLinearColor(0.02f, 0.05f, 0.2f)},
		{TEXT("Neon Magenta"), FLinearColor(0.75f, 0.03f, 0.45f)}, {TEXT("Royal Purple"), FLinearColor(0.25f, 0.05f, 0.5f)},
		{TEXT("Pearl White"), FLinearColor(0.88f, 0.88f, 0.88f)}, {TEXT("Silver"), FLinearColor(0.55f, 0.56f, 0.6f)},
		{TEXT("Gunmetal"), FLinearColor(0.12f, 0.13f, 0.15f)}, {TEXT("Jet Black"), FLinearColor(0.015f, 0.015f, 0.018f)},
		{TEXT("Bronze"), FLinearColor(0.4f, 0.2f, 0.06f)}, {TEXT("Sand"), FLinearColor(0.7f, 0.55f, 0.35f)}
	};
	const FLinearColor GCloth[] = {
		FLinearColor(0.06f, 0.40f, 0.55f), FLinearColor(0.55f, 0.06f, 0.08f), FLinearColor(0.85f, 0.85f, 0.85f), FLinearColor(0.03f, 0.03f, 0.035f),
		FLinearColor(0.85f, 0.55f, 0.05f), FLinearColor(0.15f, 0.45f, 0.12f), FLinearColor(0.5f, 0.1f, 0.45f), FLinearColor(0.05f, 0.06f, 0.15f),
		FLinearColor(0.45f, 0.30f, 0.18f), FLinearColor(0.75f, 0.35f, 0.4f), FLinearColor(0.1f, 0.6f, 0.6f), FLinearColor(0.35f, 0.35f, 0.38f),
		FLinearColor(0.9f, 0.7f, 0.45f), FLinearColor(0.2f, 0.12f, 0.06f), FLinearColor(0.95f, 0.25f, 0.05f), FLinearColor(0.25f, 0.25f, 0.6f)
	};
}

const FGTAWeaponDef& FGTAData::Weapon(EGTAWeapon Id)
{
	static TArray<FGTAWeaponDef> Table = BuildWeapons();
	const int32 I = FMath::Clamp((int32)Id, 0, Table.Num() - 1);
	return Table[I];
}

const TArray<FGTAVehicleDef>& FGTAData::Vehicles()
{
	static TArray<FGTAVehicleDef> Table = BuildVehicles();
	return Table;
}

const FGTAVehicleDef& FGTAData::Vehicle(EGTAVehicle Id)
{
	const TArray<FGTAVehicleDef>& T = Vehicles();
	return T[FMath::Clamp((int32)Id, 0, T.Num() - 1)];
}

FString FGTAData::WeaponModName(EGTAWeaponMod M)
{
	switch (M)
	{
	case EGTAWeaponMod::Suppressor: return TEXT("Suppressor");
	case EGTAWeaponMod::Scope: return TEXT("Optic / Scope");
	case EGTAWeaponMod::Grip: return TEXT("Stability Grip");
	case EGTAWeaponMod::ExtMag: return TEXT("Extended Magazine");
	case EGTAWeaponMod::Flashlight: return TEXT("Flashlight");
	default: return TEXT("?");
	}
}

int32 FGTAData::WeaponModPrice(EGTAWeaponMod M)
{
	switch (M)
	{
	case EGTAWeaponMod::Suppressor: return 900;
	case EGTAWeaponMod::Scope: return 700;
	case EGTAWeaponMod::Grip: return 500;
	case EGTAWeaponMod::ExtMag: return 650;
	case EGTAWeaponMod::Flashlight: return 300;
	default: return 0;
	}
}

bool FGTAData::WeaponModAllowed(EGTAWeapon Wp, EGTAWeaponMod M)
{
	const FGTAWeaponDef& D = Weapon(Wp);
	if (!D.bModdable) return false;
	if (M == EGTAWeaponMod::Scope && D.Cat == EGTAWeaponCat::Shotgun) return false;
	if (M == EGTAWeaponMod::Grip && D.Cat == EGTAWeaponCat::Handgun) return false;
	if (M == EGTAWeaponMod::Suppressor && Wp == EGTAWeapon::Revolver) return false;
	if (M == EGTAWeaponMod::Scope && D.Cat == EGTAWeaponCat::Sniper) return false; // built-in scope
	return true;
}

FString FGTAData::SkillName(EGTASkill S)
{
	static const TCHAR* N[] = { TEXT("Stamina"), TEXT("Shooting"), TEXT("Strength"), TEXT("Stealth"), TEXT("Driving"), TEXT("Flying"), TEXT("Lung Capacity") };
	return N[FMath::Clamp((int32)S, 0, 6)];
}

FString FGTAData::WeatherName(EGTAWeather Wx)
{
	static const TCHAR* N[] = { TEXT("Clear"), TEXT("Cloudy"), TEXT("Rain"), TEXT("Fog"), TEXT("Storm") };
	return N[FMath::Clamp((int32)Wx, 0, 4)];
}

FLinearColor FGTAData::PaintColor(int32 Index) { return GPaints[FMath::Abs(Index) % UE_ARRAY_COUNT(GPaints)].C; }
int32 FGTAData::NumPaintColors() { return UE_ARRAY_COUNT(GPaints); }
FString FGTAData::PaintName(int32 Index) { return GPaints[FMath::Abs(Index) % UE_ARRAY_COUNT(GPaints)].Name; }
FLinearColor FGTAData::ClothColor(int32 Index) { return GCloth[FMath::Abs(Index) % UE_ARRAY_COUNT(GCloth)]; }
int32 FGTAData::NumClothColors() { return UE_ARRAY_COUNT(GCloth); }

// ---------------------------------------------------------------- assets
namespace
{
	TMap<FString, TWeakObjectPtr<UObject>>& Cache()
	{
		static TMap<FString, TWeakObjectPtr<UObject>> C;
		return C;
	}

	template <typename T>
	T* LoadCached(const FString& Path, bool bWarn = true)
	{
		if (Path.IsEmpty()) return nullptr;
		if (TWeakObjectPtr<UObject>* Found = Cache().Find(Path))
		{
			if (Found->IsValid()) return Cast<T>(Found->Get());
		}
		FString Full = Path;
		if (!Full.Contains(TEXT(".")))
		{
			Full += TEXT(".") + FPaths::GetBaseFilename(Path);
		}
		T* Obj = LoadObject<T>(nullptr, *Full, nullptr, LOAD_NoWarn | LOAD_Quiet);
		if (!Obj && bWarn)
		{
			static TSet<FString> Warned;
			if (!Warned.Contains(Path))
			{
				Warned.Add(Path);
				UE_LOG(LogGTA, Warning, TEXT("Missing asset: %s"), *Path);
			}
		}
		Cache().Add(Path, Obj);
		return Obj;
	}
}

UStaticMesh* FGTAAssets::Mesh(const FString& Path) { return LoadCached<UStaticMesh>(Path); }
UStaticMesh* FGTAAssets::GenMesh(const FString& Folder, const FString& Name) { return LoadCached<UStaticMesh>(FString::Printf(TEXT("/Game/GTA/Generated/%s/%s"), *Folder, *Name)); }
USkeletalMesh* FGTAAssets::SkelMesh(const FString& Path) { return LoadCached<USkeletalMesh>(Path); }
UAnimSequence* FGTAAssets::Anim(const FString& Name) { return LoadCached<UAnimSequence>(TEXT("/Game/GTA/Generated/Characters/Centimetres/Anims/") + Name, false); }
UMaterialInterface* FGTAAssets::Material(const FString& Name)
{
	if (UMaterialInterface* M = LoadCached<UMaterialInterface>(TEXT("/Game/GTA/Materials/Instances/MI_") + Name, false)) return M;
	if (UMaterialInterface* M = LoadCached<UMaterialInterface>(TEXT("/Game/GTA/Materials/M_GTA_") + Name, false)) return M;
	return LoadCached<UMaterialInterface>(TEXT("/Game/GTA/Materials/Instances/MI_") + Name, true);
}
USoundBase* FGTAAssets::Sound(const FString& Name) { return LoadCached<USoundBase>(TEXT("/Game/GTA/Audio/") + Name); }
UStaticMesh* FGTAAssets::Cube() { return LoadCached<UStaticMesh>(TEXT("/Engine/BasicShapes/Cube.Cube")); }
UStaticMesh* FGTAAssets::Sphere() { return LoadCached<UStaticMesh>(TEXT("/Engine/BasicShapes/Sphere.Sphere")); }
UStaticMesh* FGTAAssets::Cylinder() { return LoadCached<UStaticMesh>(TEXT("/Engine/BasicShapes/Cylinder.Cylinder")); }
UStaticMesh* FGTAAssets::Plane() { return LoadCached<UStaticMesh>(TEXT("/Engine/BasicShapes/Plane.Plane")); }
UMaterialParameterCollection* FGTAAssets::WorldMPC() { return LoadCached<UMaterialParameterCollection>(TEXT("/Game/GTA/Materials/MPC_GTA_World")); }

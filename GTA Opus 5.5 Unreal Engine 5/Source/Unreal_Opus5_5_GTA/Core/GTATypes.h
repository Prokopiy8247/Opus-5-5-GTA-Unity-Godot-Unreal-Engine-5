// Core data types for the Port Halcyon sandbox (original GTA-style free-roam game).
#pragma once

#include "CoreMinimal.h"
#include "GTATypes.generated.h"

DECLARE_LOG_CATEGORY_EXTERN(LogGTA, Log, All);

UENUM(BlueprintType)
enum class EGTAWeapon : uint8
{
	Fists, Knife, Bat, Pistol, Revolver, SMG, Shotgun, AutoShotgun,
	AssaultRifle, Carbine, MarksmanRifle, SniperRifle, Grenade, RocketLauncher, GrenadeLauncher,
	MAX UMETA(Hidden)
};

UENUM(BlueprintType)
enum class EGTAWeaponCat : uint8 { Melee, Handgun, SMG, Shotgun, Rifle, Sniper, Throwable, Heavy };

UENUM(BlueprintType)
enum class EGTAVehicleKind : uint8 { Car, Motorcycle, Bicycle, Boat, Helicopter, Plane };

UENUM(BlueprintType)
enum class EGTAVehicle : uint8
{
	Compact, Sedan, Sports, Muscle, SUV, Pickup, Van, Police, Taxi, Ambulance, FireTruck, BoxTruck, Tactical,
	Motorcycle, Bicycle, Speedboat, Helicopter, PoliceHeli, PropPlane, Jet,
	MAX UMETA(Hidden)
};

UENUM(BlueprintType)
enum class EGTAPedRole : uint8 { Civilian, Police, Swat, Gang, Shopkeeper, Medic, Firefighter, Player };

UENUM(BlueprintType)
enum class EGTACrime : uint8 { Assault, Murder, Gunfire, AttackCop, KillCop, CarJack, StealCopCar, Explosion, VehicleHit, DestroyCopCar, Robbery };

UENUM(BlueprintType)
enum class EGTAWeather : uint8 { Clear, Cloudy, Rain, Fog, Storm, MAX UMETA(Hidden) };

UENUM(BlueprintType)
enum class EGTASkill : uint8 { Stamina, Shooting, Strength, Stealth, Driving, Flying, Lung, MAX UMETA(Hidden) };

/** Movement / pose state consumed by the animation instance. */
UENUM(BlueprintType)
enum class EGTAPoseMode : uint8 { Ground, Air, Swim, SeatCar, SeatBike, SeatPassenger, Climb, Parachute, Freefall, Cover, Ragdoll, HandsUp, Cower };

USTRUCT(BlueprintType)
struct FGTAWeaponDef
{
	GENERATED_BODY()
	EGTAWeapon Id = EGTAWeapon::Fists;
	FString Name;
	EGTAWeaponCat Cat = EGTAWeaponCat::Melee;
	float Damage = 10.f;
	float FireInterval = 0.5f;
	float SpreadDeg = 1.f;
	int32 Clip = 0;
	int32 MaxAmmo = 0;
	float RangeM = 1.5f;
	bool bAuto = false;
	int32 Pellets = 1;
	float Recoil = 1.f;
	int32 Price = 0;
	int32 AmmoPrice = 0;
	bool bOneHanded = true;
	bool bProjectile = false;
	float ExplosionRadiusM = 0.f;
	float ScopeFOV = 0.f;
	float ReloadTime = 1.5f;
	float Noise = 1.f;           // detection radius multiplier (1 = gunshot ~ 120 m)
	FString Mesh;                // /Game path of static mesh (grip at origin, barrel +X)
	float MuzzleX = 0.3f;        // muzzle offset along +X in meters
	float RailZ = 0.06f;         // top rail height for optics
	bool bModdable = false;
};

/** Gameplay-relevant weapon modifications (data-driven). */
UENUM(BlueprintType)
enum class EGTAWeaponMod : uint8 { Suppressor, Scope, Grip, ExtMag, Flashlight, MAX UMETA(Hidden) };

USTRUCT(BlueprintType)
struct FGTAWeaponSlot
{
	GENERATED_BODY()
	UPROPERTY() EGTAWeapon Id = EGTAWeapon::Fists;
	UPROPERTY() int32 InClip = 0;
	UPROPERTY() int32 Reserve = 0;
	UPROPERTY() uint8 Mods = 0;      // bitmask of EGTAWeaponMod
	UPROPERTY() uint8 Tint = 0;
	bool HasMod(EGTAWeaponMod M) const { return (Mods & (1 << (uint8)M)) != 0; }
};

USTRUCT(BlueprintType)
struct FGTAVehicleDef
{
	GENERATED_BODY()
	EGTAVehicle Id = EGTAVehicle::Sedan;
	FString Name;
	EGTAVehicleKind Kind = EGTAVehicleKind::Car;
	FString Key;                 // asset key: SM_Veh_<Key>
	FString Wheel = TEXT("Std"); // SM_Wheel_<Wheel>
	// geometry (meters) - identical to the Blender generator parameters
	float Length = 4.6f, Width = 1.85f, Height = 1.45f;
	float Wheelbase = 2.7f, Track = 1.58f, WheelRadius = 0.34f, RideHeight = 0.0f;
	float SeatX = -0.1f, SeatZ = 0.55f;  // driver pelvis offset
	// handling
	float MassKg = 1350.f;
	float EngineForce = 9000.f;  // N at wheels (1st gear equivalent)
	float MaxSpeedKmh = 190.f;
	float Grip = 1.f;
	float SteerDeg = 34.f;
	float SuspStiffness = 1.f;
	float Health = 1000.f;
	int32 Seats = 4;
	int32 Price = 15000;
	bool bPolice = false, bEmergency = false, bTaxi = false, bArmored = false, bConvertible = false;
	FLinearColor DefaultPaint = FLinearColor(0.6f, 0.05f, 0.05f);
};

/** Vehicle performance / cosmetic upgrade state (stored per vehicle, persisted for garage vehicles). */
USTRUCT(BlueprintType)
struct FGTAVehicleMods
{
	GENERATED_BODY()
	UPROPERTY() int32 Engine = 0;       // 0..3
	UPROPERTY() int32 Brakes = 0;       // 0..3
	UPROPERTY() int32 Suspension = 0;   // 0..3 (lower + stiffer)
	UPROPERTY() int32 Transmission = 0; // 0..3
	UPROPERTY() bool bTurbo = false;
	UPROPERTY() int32 Armor = 0;        // 0..4
	UPROPERTY() bool bBulletproofTires = false;
	UPROPERTY() int32 Spoiler = 0;      // 0 none, 1..3 styles (adds downforce)
	UPROPERTY() int32 Bumper = 0;       // 0..2 styles
	UPROPERTY() int32 Hood = 0;         // 0..2 (scoop)
	UPROPERTY() int32 Exhaust = 0;      // 0..2
	UPROPERTY() int32 Skirts = 0;       // 0..1
	UPROPERTY() int32 Roof = 0;         // 0 none, 1 rack, 2 open-top (convertible)
	UPROPERTY() int32 Rims = 0;         // 0..4 styles
	UPROPERTY() FLinearColor Primary = FLinearColor(0.6f, 0.05f, 0.05f);
	UPROPERTY() FLinearColor Secondary = FLinearColor(0.9f, 0.9f, 0.9f);
	UPROPERTY() FLinearColor RimColor = FLinearColor(0.7f, 0.7f, 0.72f);
	UPROPERTY() int32 Finish = 0;       // 0 gloss, 1 metallic, 2 matte, 3 chrome
	UPROPERTY() int32 WindowTint = 0;   // 0..3
	UPROPERTY() int32 Livery = 0;       // 0 none, 1 stripes, 2 two-tone
	UPROPERTY() int32 Horn = 0;         // 0..3
	UPROPERTY() int32 Plate = 0;        // 0..2
	UPROPERTY() int32 LightColor = 0;   // 0 white, 1 xenon blue, 2 amber
};

USTRUCT(BlueprintType)
struct FGTAAppearance
{
	GENERATED_BODY()
	UPROPERTY() int32 Body = 0;            // 0 male casual, 1 male jacket, 2 female, 3 female skirt
	UPROPERTY() FLinearColor Skin = FLinearColor(0.62f, 0.40f, 0.28f);
	UPROPERTY() FLinearColor Shirt = FLinearColor(0.06f, 0.40f, 0.55f);
	UPROPERTY() FLinearColor Pants = FLinearColor(0.05f, 0.06f, 0.10f);
	UPROPERTY() FLinearColor Shoes = FLinearColor(0.8f, 0.8f, 0.8f);
	UPROPERTY() FLinearColor Jacket = FLinearColor(0.35f, 0.05f, 0.10f);
	UPROPERTY() FLinearColor Hair = FLinearColor(0.06f, 0.035f, 0.02f);
	UPROPERTY() int32 HairStyle = 1;       // 0 bald, 1 short, 2 long, 3 ponytail, 4 mohawk, 5 bun
	UPROPERTY() int32 Beard = 0;           // 0 none, 1 beard
	UPROPERTY() int32 Hat = 0;             // 0 none, 1 cap, 2 beanie, 3 police cap, 4 helmet
	UPROPERTY() int32 Glasses = 0;         // 0 none, 1 sunglasses, 2 glasses
	UPROPERTY() float Scale = 1.f;
	UPROPERTY() int32 Vest = 0;            // 0 none, 1 police vest, 2 tactical vest
};

/** Static tables (weapons, vehicles) - see GTAData.cpp. */
struct UNREAL_OPUS5_5_GTA_API FGTAData
{
	static const FGTAWeaponDef& Weapon(EGTAWeapon Id);
	static const FGTAVehicleDef& Vehicle(EGTAVehicle Id);
	static const TArray<FGTAVehicleDef>& Vehicles();
	static FString WeaponModName(EGTAWeaponMod M);
	static int32 WeaponModPrice(EGTAWeaponMod M);
	static bool WeaponModAllowed(EGTAWeapon W, EGTAWeaponMod M);
	static FString SkillName(EGTASkill S);
	static FString WeatherName(EGTAWeather W);
	static FLinearColor PaintColor(int32 Index);
	static int32 NumPaintColors();
	static FString PaintName(int32 Index);
	static FLinearColor ClothColor(int32 Index);
	static int32 NumClothColors();
};

/** Asset loading helpers with caching and graceful fallback. */
struct UNREAL_OPUS5_5_GTA_API FGTAAssets
{
	static class UStaticMesh* Mesh(const FString& Path);
	static class UStaticMesh* GenMesh(const FString& Folder, const FString& Name); // /Game/GTA/Generated/<Folder>/<Name>
	static class USkeletalMesh* SkelMesh(const FString& Path);
	static class UAnimSequence* Anim(const FString& Name);
	static class UMaterialInterface* Material(const FString& Name);   // MI_<Name> or M_<Name>
	static class USoundBase* Sound(const FString& Name);
	static class UStaticMesh* Cube();
	static class UStaticMesh* Sphere();
	static class UStaticMesh* Cylinder();
	static class UStaticMesh* Plane();
	static class UMaterialParameterCollection* WorldMPC();
};

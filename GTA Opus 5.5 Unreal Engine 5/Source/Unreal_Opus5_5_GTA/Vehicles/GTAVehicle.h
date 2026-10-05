// Project-owned vehicle framework: raycast-suspension cars/bikes, buoyant boats, arcade helicopters and planes.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "Core/GTATypes.h"
#include "GTAVehicle.generated.h"

class UBoxComponent;
class UStaticMeshComponent;
class USpringArmComponent;
class UCameraComponent;
class USpotLightComponent;
class UPointLightComponent;
class UAudioComponent;
class AGTACharacter;
class UMaterialInstanceDynamic;

USTRUCT()
struct FGTAWheel
{
	GENERATED_BODY()
	FVector Local = FVector::ZeroVector;   // wheel center at rest (actor space, cm)
	float Radius = 34.f;
	float Compression = 0.f;              // 0..1
	float PrevCompression = 0.f;
	bool bContact = false;
	FVector ContactPoint = FVector::ZeroVector;
	FVector ContactNormal = FVector::UpVector;
	float Spin = 0.f;
	float SteerDeg = 0.f;
	bool bSteer = false;
	bool bDrive = false;
	bool bPopped = false;
	bool bRight = false;
	float SlipLat = 0.f;
	UPROPERTY() TObjectPtr<UStaticMeshComponent> Mesh = nullptr;
	UPROPERTY() TObjectPtr<UStaticMeshComponent> Rim = nullptr;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAVehicle : public APawn
{
	GENERATED_BODY()

public:
	AGTAVehicle();

	static AGTAVehicle* SpawnVehicle(UWorld* World, EGTAVehicle Id, const FTransform& T, const FGTAVehicleMods* Mods = nullptr);
	void InitVehicle(EGTAVehicle Id);

	virtual void Tick(float DeltaSeconds) override;
	virtual float TakeDamage(float Damage, struct FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser) override;

	const FGTAVehicleDef& GetDef() const { return FGTAData::Vehicle(VehicleId); }
	EGTAVehicleKind Kind() const { return GetDef().Kind; }
	bool IsAircraft() const { return Kind() == EGTAVehicleKind::Helicopter || Kind() == EGTAVehicleKind::Plane; }
	bool IsTwoWheeler() const { return Kind() == EGTAVehicleKind::Motorcycle || Kind() == EGTAVehicleKind::Bicycle; }
	bool IsBoat() const { return Kind() == EGTAVehicleKind::Boat; }

	// ---------------------------------------------------------------- occupants
	UPROPERTY() TArray<TObjectPtr<AGTACharacter>> Occupants;   // index = seat
	AGTACharacter* GetDriver() const { return Occupants.Num() > 0 ? Occupants[0].Get() : nullptr; }
	int32 NumSeats() const { return FMath::Max(1, GetDef().Seats); }
	int32 FreeSeat(bool bDriverFirst) const;
	bool AddOccupant(AGTACharacter* C, int32 Seat);
	void RemoveOccupant(AGTACharacter* C);
	FTransform GetSeatTransform(int32 Seat) const;  // relative to root
	FVector GetDoorLocation(int32 Seat) const;      // world
	FVector GetExitLocation(int32 Seat) const;      // world, collision-checked
	bool bPlayerOwned = false;
	bool bParked = false;
	bool bWasStolen = false;

	// ---------------------------------------------------------------- inputs (player or AI)
	float Throttle = 0.f;      // -1..1 (cars: + forward, - brake/reverse), aircraft: throttle/collective
	float Steer = 0.f;         // -1..1 (aircraft: roll)
	float PitchInput = 0.f;    // aircraft pitch, bike lean
	float YawInput = 0.f;      // aircraft yaw
	float LiftInput = 0.f;     // helicopter collective (-1..1)
	bool bHandbrake = false;
	bool bBoost = false;
	void ClearInputs();

	// ---------------------------------------------------------------- toggles
	bool bEngineOn = true;
	bool bLightsOn = false;
	bool bHighBeams = false;
	bool bSirenOn = false;
	bool bHornHeld = false;
	bool bRoofOpen = false;
	void ToggleLights();
	void ToggleSiren();
	void SetHorn(bool b);
	void ToggleRoof();
	void CycleRadio(int32 Dir);
	int32 RadioStation = 0;    // 0 = off
	static FString StationName(int32 Station);

	// ---------------------------------------------------------------- state
	UPROPERTY(BlueprintReadOnly) float Health = 1000.f;
	bool bDestroyed = false;
	bool bOnFire = false;
	float FireTime = 0.f;
	float SpeedKmh() const;
	float ForwardSpeed() const;       // cm/s along forward
	float EngineRPM = 900.f;
	int32 Gear = 1;
	bool IsGrounded() const;
	int32 WheelsInContact() const;
	float AirTime = 0.f;
	float AltitudeAGL() const;        // meters above ground (aircraft HUD)
	void Repair();
	void Explode(AController* Killer);
	bool IsUpsideDown() const;
	void FlipUpright();
	float LastCollisionTime = 0.f;
	float StuckTime = 0.f;

	// ---------------------------------------------------------------- customization
	UPROPERTY() FGTAVehicleMods Mods;
	void ApplyMods();
	float GetPowerMult() const;
	float GetArmorMult() const;

	// ---------------------------------------------------------------- camera
	UPROPERTY(VisibleAnywhere) TObjectPtr<USpringArmComponent> CamBoom;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UCameraComponent> Camera;
	bool bFirstPerson = false;
	void SetFirstPerson(bool b);
	float LastLookInputTime = -10.f;

	// ---------------------------------------------------------------- components
	UPROPERTY(VisibleAnywhere) TObjectPtr<UBoxComponent> Body;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> BodyMesh;
	UPROPERTY() TObjectPtr<UStaticMeshComponent> RotorMesh;
	UPROPERTY() TObjectPtr<UStaticMeshComponent> TailRotorMesh;
	UPROPERTY() TArray<TObjectPtr<UStaticMeshComponent>> PartMeshes;
	UPROPERTY() TObjectPtr<USpotLightComponent> HeadL;
	UPROPERTY() TObjectPtr<USpotLightComponent> HeadR;
	UPROPERTY() TObjectPtr<UPointLightComponent> TailGlow;
	UPROPERTY() TObjectPtr<UPointLightComponent> SirenRed;
	UPROPERTY() TObjectPtr<UPointLightComponent> SirenBlue;
	UPROPERTY() TObjectPtr<USpotLightComponent> Searchlight;
	UPROPERTY() TObjectPtr<UAudioComponent> EngineAudio;
	UPROPERTY() TObjectPtr<UAudioComponent> SirenAudio;
	UPROPERTY() TObjectPtr<UAudioComponent> HornAudio;
	UPROPERTY() TObjectPtr<UAudioComponent> RadioAudio;
	UPROPERTY() TObjectPtr<UAudioComponent> SkidAudio;
	UPROPERTY() TArray<FGTAWheel> Wheels;
	UPROPERTY() TArray<TObjectPtr<UMaterialInstanceDynamic>> BodyMIDs;

	EGTAVehicle VehicleId = EGTAVehicle::Sedan;
	float BodyCenterZ = 70.f;        // actor origin above ground (cm)
	FVector MeshOffset = FVector::ZeroVector;  // Blender-space origin relative to the actor
	FVector ToActorLocal(float X, float Y, float Z) const { return FVector(X * 100.f, -Y * 100.f, Z * 100.f) + MeshOffset; }
	float PlaneThrottle = 0.f;       // 0..1 persistent throttle lever for aircraft
	bool bKinematicAI = false;       // scripted flight (police helicopter AI)
	FVector AIFlyTarget = FVector::ZeroVector;
	float AIFlySpeed = 2500.f;
	bool bAIDriven = false;
	float ExplodeAt = 0.f;
	bool bSearchlightOn = false;
	FVector SearchlightTarget = FVector::ZeroVector;

	UFUNCTION()
	void OnBodyHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit);

protected:
	virtual void BeginPlay() override;
	void TickGround(float Dt);
	void TickBoat(float Dt);
	void TickHeli(float Dt);
	void TickPlane(float Dt);
	void TickWheels(float Dt, float DriveForce, float BrakeForce, float GripMult);
	void TickPedestrianImpacts(float Dt);
	void TickEffects(float Dt);
	void TickAudio(float Dt);
	void TickCamera(float Dt);
	void SetupLights();
	void SetPaintParam(FName Slot, FName Param, const FLinearColor& C);
	void SetScalarOnSlot(FName Slot, FName Param, float V);
	UStaticMeshComponent* AddPart(const FString& MeshName, const FVector& Loc, const FRotator& Rot, const FVector& Scale);
	float SirenPhase = 0.f;
	float SmokeTimer = 0.f;
	float BrakeLightLevel = 0.f;
	float RotorSpeed = 0.f;
	float StallWarn = 0.f;
	float LastSkidFX = 0.f;
	float SteerSmoothed = 0.f;
	float HeliAltitudeHold = 0.f;
};

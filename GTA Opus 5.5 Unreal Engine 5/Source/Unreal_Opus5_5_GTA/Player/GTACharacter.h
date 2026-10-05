// Humanoid used by the player and every NPC (pedestrians, police, gangs, shop staff).
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "GameFramework/DamageType.h"
#include "Core/GTATypes.h"
#include "Player/GTAAnimInstance.h"
#include "GTACharacter.generated.h"

class AGTAVehicle;
class UStaticMeshComponent;
class USpotLightComponent;
class UAudioComponent;

UCLASS() class UGTADamage_Bullet : public UDamageType { GENERATED_BODY() };
UCLASS() class UGTADamage_Melee : public UDamageType { GENERATED_BODY() };
UCLASS() class UGTADamage_Explosion : public UDamageType { GENERATED_BODY() };
UCLASS() class UGTADamage_Vehicle : public UDamageType { GENERATED_BODY() };
UCLASS() class UGTADamage_Fall : public UDamageType { GENERATED_BODY() };
UCLASS() class UGTADamage_Drown : public UDamageType { GENERATED_BODY() };

#define GTA_ECC_WEAPON ECC_GameTraceChannel1

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTACharacter : public ACharacter
{
	GENERATED_BODY()

public:
	AGTACharacter(const FObjectInitializer& OI);

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual float TakeDamage(float Damage, struct FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser) override;
	virtual void Landed(const FHitResult& Hit) override;
	virtual void FellOutOfWorld(const UDamageType& DmgType) override;

	// ---------------------------------------------------------------- identity / look
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GTA") EGTAPedRole PedRole = EGTAPedRole::Civilian;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "GTA") FGTAAppearance Appearance;
	void ApplyAppearance();
	void RandomizeAppearance(int32 Seed, EGTAPedRole ForRole);
	bool IsPlayerCharacter() const;
	bool IsPolice() const { return PedRole == EGTAPedRole::Police || PedRole == EGTAPedRole::Swat; }

	// ---------------------------------------------------------------- vitals
	UPROPERTY(BlueprintReadOnly, Category = "GTA") float Health = 100.f;
	UPROPERTY(BlueprintReadOnly, Category = "GTA") float MaxHealth = 100.f;
	UPROPERTY(BlueprintReadOnly, Category = "GTA") float Armor = 0.f;
	UPROPERTY(BlueprintReadOnly, Category = "GTA") bool bDead = false;
	bool bInvulnerable = false;
	float LastDamageTime = -100.f;
	TWeakObjectPtr<AActor> LastAttacker;
	void Heal(float Amount) { Health = FMath::Min(MaxHealth, Health + Amount); }
	virtual void Die(AController* Killer, const FVector& Impulse, FName Bone);
	void Revive();

	// ---------------------------------------------------------------- ragdoll / knockdown
	void StartRagdoll(const FVector& Impulse, FName Bone);
	void Knockdown(const FVector& Impulse, float Duration);
	bool IsRagdoll() const { return bRagdoll; }
	bool IsKnockedDown() const { return bRagdoll && !bDead; }

	// ---------------------------------------------------------------- weapons
	UPROPERTY() TArray<FGTAWeaponSlot> Weapons;
	int32 CurrentSlot = 0;
	void GiveWeapon(EGTAWeapon Id, int32 Ammo, bool bEquip = false);
	bool HasWeapon(EGTAWeapon Id) const;
	FGTAWeaponSlot* FindSlot(EGTAWeapon Id);
	void EquipWeapon(EGTAWeapon Id);
	void CycleWeapon(int32 Dir);
	EGTAWeapon CurrentWeapon() const { return Weapons.IsValidIndex(CurrentSlot) ? Weapons[CurrentSlot].Id : EGTAWeapon::Fists; }
	const FGTAWeaponDef& CurrentDef() const { return FGTAData::Weapon(CurrentWeapon()); }
	FGTAWeaponSlot* CurrentSlotPtr() { return Weapons.IsValidIndex(CurrentSlot) ? &Weapons[CurrentSlot] : nullptr; }
	int32 EffectiveClip(const FGTAWeaponSlot& S) const;
	bool IsTwoHanded() const;
	void SetTriggerHeld(bool bHeld);
	bool IsTriggerHeld() const { return bTriggerHeld; }
	void Reload();
	bool IsReloading() const { return bReloading; }
	void Melee(bool bHeavy);
	void RefillAllAmmo();
	virtual FVector GetAimOrigin() const;
	virtual FVector GetAimTarget() const;      // world point the character wants to hit
	FVector GetMuzzleLocation() const;
	float AccuracyMult = 1.f;                  // > 1 = less accurate (NPC difficulty, blind fire, driving)
	bool bUseAimPoint = false;                 // AI: explicit world aim point
	FVector AimPoint = FVector::ZeroVector;
	float DamageMult = 1.f;
	void UpdateWeaponVisual();

	// ---------------------------------------------------------------- stance
	bool bAiming = false;
	bool bSprinting = false;
	bool bStealth = false;
	bool bInCover = false;
	bool bCoverLow = false;
	FVector CoverNormal = FVector::ZeroVector;
	EGTAPoseMode ForcedPose = EGTAPoseMode::Ground;
	bool bForcePose = false;
	void SetAiming(bool b);
	void SetSprinting(bool b) { bSprinting = b; }
	float MoveSpeedScale = 1.f;                // AI walking pace (0.35 stroll .. 1 run)
	void SetStealth(bool b);
	void SetHandsUp(bool b);
	void SetCower(bool b);
	float GetNoiseRadius() const;              // cm, footstep/action noise for detection
	float AimPitch = 0.f;

	// ---------------------------------------------------------------- water / breath
	bool IsSwimming() const;
	bool IsUnderwater() const;
	float Breath = 1.f;                        // 0..1
	float BreathCapacity = 30.f;               // seconds (lung skill raises)
	bool bScuba = false;

	// ---------------------------------------------------------------- vehicles
	UPROPERTY() TObjectPtr<AGTAVehicle> Vehicle = nullptr;
	int32 SeatIndex = -1;
	bool IsInVehicle() const { return Vehicle != nullptr; }
	void SitInVehicle(AGTAVehicle* V, int32 Seat);
	void LeaveVehicleTo(const FVector& Location, float Yaw);

	// ---------------------------------------------------------------- animation
	UGTAAnimInstance* GetGTAAnim() const;
	void PlayAction(EGTAClip Clip, bool bUpper = true, float Rate = 1.f);

	// ---------------------------------------------------------------- components
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> WeaponMesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> ModSuppressor;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> ModScope;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> ModLight;
	UPROPERTY(VisibleAnywhere) TObjectPtr<USpotLightComponent> Flashlight;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> HairMesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> HatMesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> GlassesMesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> BeardMesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> VestMesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> BackMesh;   // parachute pack / scuba tank
	UPROPERTY(VisibleAnywhere) TObjectPtr<UAudioComponent> VoiceAudio;

	/** Cash carried (NPC drop on death). */
	int32 Cash = 0;
	bool bHasParachute = false;
	float SpawnTime = 0.f;
	/** Simulation tier for distant NPCs (0 = full, 1 = reduced, 2 = minimal). */
	int32 SimTier = 0;
	void SetSimTier(int32 Tier);

protected:
	virtual void FireShot();
	void FireProjectile(const FGTAWeaponDef& D);
	void FinishReload();
	void TickWeapon(float Dt);
	void TickWater(float Dt);
	void TickAnimState(float Dt);
	void EndKnockdown();
	void AttachToBoneRest(UStaticMeshComponent* C, FName Bone);
	FTransform RefBoneCS(FName Bone) const;
	void ApplyMeleeHit(bool bHeavy);

	bool bTriggerHeld = false;
	bool bReloading = false;
	float NextFireTime = 0.f;
	float ReloadEnd = 0.f;
	float RecoilKick = 0.f;
	float ConsecutiveShots = 0.f;
	bool bRagdoll = false;
	float KnockdownEnd = 0.f;
	float FallStartZ = 0.f;
	bool bWasFalling = false;
	float DrownTick = 0.f;
	float MeleeCooldown = 0.f;
	FTimerHandle MeleeTimer;
	bool bPendingHeavy = false;
};

// Player character: third-person camera, shoulder aiming, cover, vault/climb, parachute, diving, interaction.
#pragma once

#include "CoreMinimal.h"
#include "Player/GTACharacter.h"
#include "GTAPlayerCharacter.generated.h"

class USpringArmComponent;
class UCameraComponent;
class UNavigationInvokerComponent;
class UStaticMeshComponent;

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAPlayerCharacter : public AGTACharacter
{
	GENERATED_BODY()
public:
	AGTAPlayerCharacter(const FObjectInitializer& OI);
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual float TakeDamage(float Damage, struct FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser) override;
	virtual FVector GetAimOrigin() const override;
	virtual FVector GetAimTarget() const override;
	virtual void Landed(const FHitResult& Hit) override;

	UPROPERTY(VisibleAnywhere) TObjectPtr<USpringArmComponent> CamBoom;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UCameraComponent> Camera;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UNavigationInvokerComponent> NavInvoker;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> ParachuteCanopy;

	// ---------------------------------------------------------------- input entry points (called by the controller)
	void InputMove(const FVector2D& Axis);
	void InputLook(const FVector2D& Axis);
	void InputJump();
	void InputCrouch();
	void InputCover();
	void InputDodge();
	bool InputParachute();       // deploy / cut; returns true if consumed
	void InputBlock(bool b) { bBlocking = b; }

	// ---------------------------------------------------------------- camera
	bool bFirstPersonView = false;
	void ToggleFirstPerson();
	float ShoulderSide = 1.f;    // +1 right shoulder, -1 left
	void SwapShoulder() { ShoulderSide = -ShoulderSide; }
	float CameraShake = 0.f;
	float ScopeZoom = 0.f;        // 0 = no scope, else FOV
	bool IsScoped() const { return bAiming && ScopeZoom > 0.f; }

	// ---------------------------------------------------------------- cover
	void EnterCover();
	void LeaveCover();
	FVector CoverPoint = FVector::ZeroVector;
	bool bBlindFire = false;

	// ---------------------------------------------------------------- parachute / freefall
	bool bParachuteOpen = false;
	bool IsFreefalling() const;
	void SetHasParachute(bool b);
	void SetScuba(bool b);

	// ---------------------------------------------------------------- interaction
	FString InteractPrompt;      // shown by the HUD
	AGTAVehicle* FindVehicleToEnter(int32& OutSeat) const;
	bool bBlocking = false;
	float LastAttackedTime = -100.f;
	float StaminaUsed = 0.f;

	// ---------------------------------------------------------------- profile
	void LoadFromProfile();
	void SaveToProfile();

	FVector CachedAimPoint = FVector::ZeroVector;
	AActor* CachedAimActor = nullptr;

protected:
	void UpdateCamera(float Dt);
	void UpdateAimTrace();
	void UpdateCover(float Dt);
	void UpdateParachute(float Dt);
	bool TryVault();
	void TickRegen(float Dt);
	FVector2D MoveInput = FVector2D::ZeroVector;
	float AimNotifyTimer = 0.f;
	float VaultUntil = 0.f;
	FVector VaultTarget = FVector::ZeroVector;
	FVector VaultStart = FVector::ZeroVector;
	float VaultDuration = 0.5f;
	float VaultT = 0.f;
	float BaseArm = 330.f;
	float FreefallStartZ = 0.f;
};

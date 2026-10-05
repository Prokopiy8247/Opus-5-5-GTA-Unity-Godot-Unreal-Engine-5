// Collectible items: dropped cash/weapons and world pickups (health, armor, parachute, ammo).
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/GTATypes.h"
#include "GTAPickup.generated.h"

class USphereComponent;
class UStaticMeshComponent;
class UPointLightComponent;

UENUM()
enum class EGTAPickupKind : uint8 { Cash, Weapon, Health, Armor, Parachute, Ammo, Scuba };

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAPickup : public AActor
{
	GENERATED_BODY()
public:
	AGTAPickup();
	virtual void Tick(float DeltaSeconds) override;

	static AGTAPickup* SpawnPickup(UWorld* World, const FVector& Loc, EGTAPickupKind Kind, int32 Amount, EGTAWeapon Weapon = EGTAWeapon::Fists, bool bTemporary = true);
	static void SpawnCash(UWorld* World, const FVector& Loc, int32 Amount);
	static void SpawnWeapon(UWorld* World, const FVector& Loc, EGTAWeapon Weapon, int32 Ammo);

	void Setup(EGTAPickupKind InKind, int32 InAmount, EGTAWeapon InWeapon, bool bTemporary);

	UPROPERTY(VisibleAnywhere) TObjectPtr<USphereComponent> Trigger;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> Mesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UPointLightComponent> Glow;

	EGTAPickupKind Kind = EGTAPickupKind::Cash;
	int32 Amount = 0;
	EGTAWeapon Weapon = EGTAWeapon::Fists;
	/** World pickups respawn after being collected. */
	float RespawnDelay = 0.f;

	UFUNCTION()
	void OnOverlap(UPrimitiveComponent* OverlappedComp, AActor* Other, UPrimitiveComponent* OtherComp, int32 BodyIndex, bool bFromSweep, const FHitResult& Sweep);

private:
	float Spin = 0.f;
	float BaseZ = 0.f;
	float HiddenUntil = 0.f;
	bool bCollected = false;
};

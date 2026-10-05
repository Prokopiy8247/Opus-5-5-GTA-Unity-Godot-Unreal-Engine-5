// Rockets, grenades and launcher shells.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/GTATypes.h"
#include "GTAProjectile.generated.h"

class USphereComponent;
class UStaticMeshComponent;
class UProjectileMovementComponent;
class UPointLightComponent;

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAProjectile : public AActor
{
	GENERATED_BODY()
public:
	AGTAProjectile();
	void Init(EGTAWeapon InWeapon, const FVector& Dir, AActor* InShooter);
	virtual void Tick(float DeltaSeconds) override;

	UPROPERTY(VisibleAnywhere) TObjectPtr<USphereComponent> Sphere;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UStaticMeshComponent> Mesh;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UProjectileMovementComponent> Move;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UPointLightComponent> Glow;

	UFUNCTION()
	void OnHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit);

private:
	void Detonate();
	EGTAWeapon Weapon = EGTAWeapon::Grenade;
	float Fuse = 0.f;
	float TrailTimer = 0.f;
	bool bDone = false;
	TWeakObjectPtr<AActor> Shooter;
};

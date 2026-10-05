// Lightweight CPU particle system rendered with instanced camera-facing quads (no external FX assets).
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "GTAFX.generated.h"

class UInstancedStaticMeshComponent;
class UPointLightComponent;

struct FGTAParticle
{
	FVector Pos = FVector::ZeroVector;
	FVector Vel = FVector::ZeroVector;
	float Age = 0.f;
	float Life = 1.f;
	float Size0 = 10.f;
	float Size1 = 20.f;
	FLinearColor Color = FLinearColor::White;
	float Alpha = 1.f;
	float Drag = 0.f;
	float Gravity = 0.f;
	float Stretch = 0.f;     // > 0: velocity-aligned streak (length multiplier)
	bool bLit = true;        // translucent particles are dimmed at night
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAFX : public AActor
{
	GENERATED_BODY()
public:
	AGTAFX();
	virtual void Tick(float DeltaSeconds) override;

	/** Kinds: 0 dust, 1 sparks, 2 blood, 3 water, 4 hit puff, 5 smoke, 6 fire, 7 tire smoke, 8 rocket trail, 9 splash big */
	void Impact(const FVector& Loc, const FVector& Normal, int32 Kind);
	void Muzzle(const FVector& Loc, const FVector& Dir, bool bSuppressed);
	void Tracer(const FVector& A, const FVector& B);
	void Explosion(const FVector& Loc, float Radius);
	void BulletHole(const FVector& Loc, const FVector& Normal, float Size, const FLinearColor& Color);
	void Flash(const FVector& Loc, const FLinearColor& Color, float Intensity, float Radius, float Life);
	void Emit(bool bAdditive, const FGTAParticle& P);

	UPROPERTY(VisibleAnywhere) TObjectPtr<UInstancedStaticMeshComponent> TransPool;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UInstancedStaticMeshComponent> AddPool;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UInstancedStaticMeshComponent> HolePool;
	UPROPERTY() TArray<TObjectPtr<UPointLightComponent>> Lights;

	int32 ActiveParticles() const { return Parts[0].Num() + Parts[1].Num(); }

protected:
	virtual void BeginPlay() override;

private:
	static constexpr int32 Capacity = 512;
	static constexpr int32 HoleCapacity = 192;
	TArray<FGTAParticle> Parts[2];
	TArray<float> LightLife;
	TArray<float> LightMax;
	TArray<float> LightPeak;
	int32 NextLight = 0;
	int32 NextHole = 0;
	void UpdatePool(int32 Index, UInstancedStaticMeshComponent* Pool, const FVector& Cam, float Ambient);
};

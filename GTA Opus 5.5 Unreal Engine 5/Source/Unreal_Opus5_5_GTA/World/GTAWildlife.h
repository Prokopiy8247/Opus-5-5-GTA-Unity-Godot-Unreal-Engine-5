#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "GTAWildlife.generated.h"

class UInstancedStaticMeshComponent;
UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAWildlife : public AActor
{
	GENERATED_BODY()
public:
	AGTAWildlife();
	virtual void BeginPlay() override;
	virtual void Tick(float Dt) override;
private:
	UPROPERTY() TObjectPtr<UInstancedStaticMeshComponent> Gulls;
	UPROPERTY() TObjectPtr<UInstancedStaticMeshComponent> Wings;
	UPROPERTY() TObjectPtr<UInstancedStaticMeshComponent> Fish;
	UPROPERTY() TObjectPtr<UInstancedStaticMeshComponent> Deer;
	TArray<FVector> DeerPositions;
};

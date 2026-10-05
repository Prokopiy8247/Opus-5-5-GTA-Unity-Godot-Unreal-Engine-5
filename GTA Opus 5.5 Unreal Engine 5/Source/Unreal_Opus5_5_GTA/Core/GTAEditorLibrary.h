// Editor automation callable from Python: builds and saves the Port Halcyon start map.
#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "GTAEditorLibrary.generated.h"

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTAEditorLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()
public:
	/** Creates (or overwrites) the start map with the city, environment, player start, navigation bounds and water volumes. */
	UFUNCTION(BlueprintCallable, Category = "GTA|Editor")
	static bool BuildPortHalcyonLevel(const FString& MapPath);

	/** Rebuilds collision from current mesh bounds after an FBX scale correction. */
	UFUNCTION(BlueprintCallable, Category = "GTA|Editor")
	static bool RebuildMeshCollision(class UStaticMesh* Mesh);
	UFUNCTION(BlueprintCallable, Category = "GTA|Editor")
	static bool CreateCharacterPhysics(class USkeletalMesh* Mesh);
	UFUNCTION(BlueprintCallable, Category = "GTA|Editor")
	static class USkeleton* EnsureCharacterSkeleton(class USkeletalMesh* Mesh);
};

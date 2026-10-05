#include "Core/GTAEditorLibrary.h"
#include "Core/GTATypes.h"
#include "Core/GTAGameMode.h"
#include "World/GTACity.h"
#include "World/GTAEnvironment.h"
#include "GameFramework/PlayerStart.h"
#include "GameFramework/WorldSettings.h"
#include "Engine/StaticMesh.h"
#include "PhysicsEngine/BodySetup.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/Skeleton.h"
#include "PhysicsEngine/PhysicsAsset.h"

#if WITH_EDITOR
#include "Editor.h"
#include "PhysicsAssetUtils.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "FileHelpers.h"
#include "ActorFactories/ActorFactory.h"
#include "Builders/CubeBuilder.h"
#include "NavMesh/NavMeshBoundsVolume.h"
#include "GameFramework/PhysicsVolume.h"
#include "Engine/BlockingVolume.h"
#include "Components/BrushComponent.h"

namespace
{
	template <typename T>
	T* SpawnBoxVolume(UWorld* World, const FVector& Center, const FVector& SizeCm, const TCHAR* Label)
	{
		FActorSpawnParameters P;
		P.Name = MakeUniqueObjectName(World->PersistentLevel, T::StaticClass(), FName(Label));
		T* V = World->SpawnActor<T>(T::StaticClass(), FTransform(Center), P);
		if (!V) return nullptr;
		UCubeBuilder* B = NewObject<UCubeBuilder>();
		B->X = SizeCm.X;
		B->Y = SizeCm.Y;
		B->Z = SizeCm.Z;
		UActorFactory::CreateBrushForVolumeActor(V, B);
		V->SetActorLabel(Label);
		return V;
	}
}
#endif

USkeleton* UGTAEditorLibrary::EnsureCharacterSkeleton(USkeletalMesh* Mesh)
{
#if WITH_EDITOR
	if (!Mesh) return nullptr;
	const FString Path = TEXT("/Game/GTA/Generated/Characters/Centimetres/SKEL_Human_Cm");
	USkeleton* Skeleton = LoadObject<USkeleton>(nullptr, *(Path+TEXT(".SKEL_Human_Cm")), nullptr, LOAD_NoWarn | LOAD_Quiet);
	if (!Skeleton)
	{
		Skeleton = NewObject<USkeleton>(CreatePackage(*Path), TEXT("SKEL_Human_Cm"), RF_Public | RF_Standalone);
		FAssetRegistryModule::AssetCreated(Skeleton);
	}
	Skeleton->MergeAllBonesToBoneTree(Mesh);
	Mesh->SetSkeleton(Skeleton);
	Skeleton->SetPreviewMesh(Mesh);
	Skeleton->MarkPackageDirty();
	Mesh->MarkPackageDirty();
	return Skeleton;
#else
	return nullptr;
#endif
}

bool UGTAEditorLibrary::CreateCharacterPhysics(USkeletalMesh* Mesh)
{
#if WITH_EDITOR
	if (!Mesh) return false;
	const FString Path = TEXT("/Game/GTA/Generated/Characters/Centimetres/PA_Human");
	UPhysicsAsset* Physics = LoadObject<UPhysicsAsset>(nullptr, *(Path + TEXT(".PA_Human")), nullptr, LOAD_NoWarn | LOAD_Quiet);
	if (!Physics)
	{
		UPackage* Package = CreatePackage(*Path);
		Physics = NewObject<UPhysicsAsset>(Package, TEXT("PA_Human"), RF_Public | RF_Standalone);
		FPhysAssetCreateParams Params;
		Params.MinBoneSize = 5.f;
		FText Error;
		if (!FPhysicsAssetUtils::CreateFromSkeletalMesh(Physics, Mesh, Params, Error, true))
		{
			UE_LOG(LogGTA, Error, TEXT("Physics generation failed: %s"), *Error.ToString());
			return false;
		}
		FAssetRegistryModule::AssetCreated(Physics);
		Physics->MarkPackageDirty();
	}
	Mesh->SetPhysicsAsset(Physics);
	Mesh->MarkPackageDirty();
	UE_LOG(LogGTA, Display, TEXT("PHYSICS %s bodies=%d constraints=%d"), *Mesh->GetName(), Physics->SkeletalBodySetups.Num(), Physics->ConstraintSetup.Num());
	return Physics->SkeletalBodySetups.Num() > 5;
#else
	return false;
#endif
}

bool UGTAEditorLibrary::RebuildMeshCollision(UStaticMesh* Mesh)
{
#if WITH_EDITOR
	if (!Mesh || !Mesh->GetBodySetup()) return false;
	UBodySetup* Body = Mesh->GetBodySetup();
	const FBox Box = Mesh->GetBoundingBox();
	Body->RemoveSimpleCollision();
	FKBoxElem Shape;
	Shape.Center = Box.GetCenter();
	const FVector Size = Box.GetSize();
	Shape.X = FMath::Max(1.f, Size.X);
	Shape.Y = FMath::Max(1.f, Size.Y);
	Shape.Z = FMath::Max(1.f, Size.Z);
	Body->AggGeom.BoxElems.Add(Shape);
	Body->CollisionTraceFlag = CTF_UseSimpleAndComplex;
	Body->InvalidatePhysicsData();
	Body->CreatePhysicsMeshes();
	Mesh->MarkPackageDirty();
	UE_LOG(LogGTA, Display, TEXT("COLLISION %s cm=%s"), *Mesh->GetName(), *Size.ToString());
	return true;
#else
	return false;
#endif
}

bool UGTAEditorLibrary::BuildPortHalcyonLevel(const FString& MapPath)
{
#if WITH_EDITOR
	UWorld* World = UEditorLoadingAndSavingUtils::NewBlankMap(false);
	if (!World) { UE_LOG(LogGTA, Error, TEXT("BuildPortHalcyonLevel: NewBlankMap failed")); return false; }

	FActorSpawnParameters SP;
	AGTACity* City = World->SpawnActor<AGTACity>(AGTACity::StaticClass(), FTransform::Identity, SP);
	City->SetActorLabel(TEXT("PortHalcyon_City"));
	City->bBuildInEditor = true;
	City->BuildLayout();

	AGTAEnvironment* Env = World->SpawnActor<AGTAEnvironment>(AGTAEnvironment::StaticClass(), FTransform::Identity, SP);
	Env->SetActorLabel(TEXT("PortHalcyon_Environment"));

	// The authored spawn transform is a fixed point in the procedurally generated layout, so it
	// can land inside a building. Collision traces cannot rescue it here: this builds the level in
	// a commandlet, where the instanced city meshes have no physics scene yet, so every trace comes
	// back empty and the player starts inside a bungalow with the camera pressed into a wall.
	// Instead snap to the street the safehouse fronts: road surfaces are open by construction.
	FTransform SpawnT = City->PlayerSpawn;
	{
		const int32 SpawnEdge = City->NearestEdge(SpawnT.GetLocation());
		bool bPlaced = false;
		if (SpawnEdge != INDEX_NONE)
		{
			const FVector P = City->LanePoint(SpawnEdge, true, 0.5f);
			const FVector S = City->SidewalkPoint(SpawnEdge, false, 0.5f);
			// Prefer the sidewalk; it is where a pedestrian would stand and it keeps the
			// third-person camera boom clear of parked cars.
			const FVector C = FVector::Dist2D(S, SpawnT.GetLocation()) < FVector::Dist2D(P, SpawnT.GetLocation()) ? S : P;
			SpawnT.SetLocation(FVector(C.X, C.Y, AGTACity::TerrainHeightAt(C.X, C.Y) + 110.f));
			bPlaced = true;
			UE_LOG(LogGTA, Display, TEXT("BuildPortHalcyonLevel: spawn snapped to street edge %d at %s"),
				SpawnEdge, *SpawnT.GetLocation().ToString());
		}
		if (!bPlaced)
		{
			const FVector L = SpawnT.GetLocation();
			SpawnT.SetLocation(FVector(L.X, L.Y, AGTACity::TerrainHeightAt(L.X, L.Y) + 110.f));
			UE_LOG(LogGTA, Warning, TEXT("BuildPortHalcyonLevel: no street near spawn, placed on terrain at %s"),
				*SpawnT.GetLocation().ToString());
		}
	}

	APlayerStart* Start = World->SpawnActor<APlayerStart>(APlayerStart::StaticClass(), SpawnT, SP);
	Start->SetActorLabel(TEXT("PlayerStart_CoralBungalow"));

	// navigation bounds over the playable land (tiles are generated at runtime around navigation invokers)
	SpawnBoxVolume<ANavMeshBoundsVolume>(World, FVector(5000.f, 0.f, 1000.f), FVector(52000.f, 61000.f, 6000.f), TEXT("Nav_PortHalcyon"));

	// sea water volumes (swimming): beach section and the deeper harbor quay section
	if (APhysicsVolume* Sea = SpawnBoxVolume<APhysicsVolume>(World, FVector(-59920.f, 6000.f, AGTACity::SeaLevelZ - 2500.f), FVector(80160.f, 100000.f, 5000.f), TEXT("Water_Bay")))
	{
		Sea->bWaterVolume = true;
		Sea->FluidFriction = 0.6f;
	}
	if (APhysicsVolume* Harbor = SpawnBoxVolume<APhysicsVolume>(World, FVector((AGTACity::CoastX - 19840.f) * 0.5f, -39500.f, AGTACity::SeaLevelZ - 2500.f), FVector(1540.f, 41000.f, 5000.f), TEXT("Water_Harbor")))
	{
		Harbor->bWaterVolume = true;
		Harbor->FluidFriction = 0.6f;
	}
	if (APhysicsVolume* Pond = SpawnBoxVolume<APhysicsVolume>(World, FVector(22500.f, 7000.f, -60.f), FVector(3000.f, 3000.f, 100.f), TEXT("Water_ParkPond")))
	{
		Pond->bWaterVolume = true;
	}

	// invisible walls at the land edges (cliff meshes are the visible boundary)
	SpawnBoxVolume<ABlockingVolume>(World, FVector(30800.f, 0.f, 5000.f), FVector(800.f, 64000.f, 20000.f), TEXT("Bound_North"));
	SpawnBoxVolume<ABlockingVolume>(World, FVector(6000.f, 30800.f, 5000.f), FVector(50000.f, 800.f, 20000.f), TEXT("Bound_East"));
	SpawnBoxVolume<ABlockingVolume>(World, FVector(6000.f, -30800.f, 5000.f), FVector(50000.f, 800.f, 20000.f), TEXT("Bound_West"));

	if (AWorldSettings* WS = World->GetWorldSettings())
	{
		WS->DefaultGameMode = AGTAGameMode::StaticClass();
		WS->KillZ = -9000.f;
		WS->bEnableWorldBoundsChecks = true;
	}
	City->RerunConstructionScripts();
	const bool bOk = UEditorLoadingAndSavingUtils::SaveMap(World, MapPath);
	UE_LOG(LogGTA, Display, TEXT("BuildPortHalcyonLevel: saved %s -> %d (city instances %d, missing meshes %d)"), *MapPath, bOk ? 1 : 0, City->InstanceCount, City->MissingMeshCount);
	return bOk;
#else
	return false;
#endif
}

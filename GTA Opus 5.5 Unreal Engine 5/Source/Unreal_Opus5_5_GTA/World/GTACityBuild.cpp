// Instanced visual construction of Port Halcyon: roads, blocks and generic building rows.
#include "World/GTACity.h"
#include "Core/GTAGame.h"
#include "Components/HierarchicalInstancedStaticMeshComponent.h"
#include "Engine/StaticMesh.h"

namespace
{
	struct FGTABldDef
	{
		const TCHAR* Name;
		float D, W, H;          // meters: depth (local X, front faces +X), width (local Y), height
		uint32 Districts;
		const TCHAR* Mat;
		float Setback;
	};
	constexpr uint32 DM(EGTADistrict D) { return 1u << (uint32)D; }

	const FGTABldDef GBuildings[] = {
		{ TEXT("SM_Bld_Tower_A"), 24, 24, 72, DM(EGTADistrict::Downtown), TEXT("E_Window"), 2 },
		{ TEXT("SM_Bld_Tower_B"), 30, 22, 54, DM(EGTADistrict::Downtown), TEXT("E_Teal"), 2 },
		{ TEXT("SM_Bld_Office_A"), 30, 20, 30, DM(EGTADistrict::Downtown), TEXT("E_Concrete"), 2 },
		{ TEXT("SM_Bld_Office_B"), 20, 28, 24, DM(EGTADistrict::Downtown), TEXT("E_Concrete"), 2 },
		{ TEXT("SM_Bld_Apartment_A"), 16, 20, 18, DM(EGTADistrict::Downtown) | DM(EGTADistrict::NeonRow), TEXT("E_Plaster1"), 2 },
		{ TEXT("SM_Bld_Apartment_B"), 24, 16, 22, DM(EGTADistrict::Downtown) | DM(EGTADistrict::NeonRow), TEXT("E_Plaster2"), 2 },
		{ TEXT("SM_Bld_Shop_A"), 12, 14, 8, DM(EGTADistrict::NeonRow), TEXT("E_Plaster3"), 1 },
		{ TEXT("SM_Bld_Shop_B"), 12, 18, 11, DM(EGTADistrict::NeonRow), TEXT("E_Plaster1"), 1 },
		{ TEXT("SM_Bld_Shop_C"), 12, 12, 7, DM(EGTADistrict::NeonRow) | DM(EGTADistrict::Industrial), TEXT("E_Plaster2"), 1 },
		{ TEXT("SM_Bld_Motel"), 14, 30, 7, DM(EGTADistrict::NeonRow), TEXT("E_Plaster3"), 3 },
		{ TEXT("SM_Bld_Club"), 16, 20, 9, DM(EGTADistrict::NeonRow), TEXT("E_ConcreteDark"), 1 },
		{ TEXT("SM_Bld_House_A"), 10, 12, 7, DM(EGTADistrict::Hills), TEXT("E_Plaster3"), 5 },
		{ TEXT("SM_Bld_House_B"), 11, 14, 8, DM(EGTADistrict::Hills), TEXT("E_Plaster2"), 5 },
		{ TEXT("SM_Bld_House_C"), 10, 10, 6, DM(EGTADistrict::Hills), TEXT("E_Plaster1"), 5 },
		{ TEXT("SM_Bld_Warehouse_A"), 24, 40, 12, DM(EGTADistrict::Industrial) | DM(EGTADistrict::Harbor), TEXT("E_Metal"), 3 },
		{ TEXT("SM_Bld_Warehouse_B"), 20, 30, 10, DM(EGTADistrict::Industrial) | DM(EGTADistrict::Harbor), TEXT("E_Metal"), 3 },
		{ TEXT("SM_Bld_Factory"), 26, 36, 14, DM(EGTADistrict::Industrial), TEXT("E_Brick"), 3 },
	};

	FString GroundMeshFor(EGTADistrict D)
	{
		switch (D)
		{
		case EGTADistrict::Hills:
		case EGTADistrict::Park: return TEXT("SM_Ground_Grass");
		case EGTADistrict::Beach: return TEXT("SM_Ground_Sand");
		default: return TEXT("SM_Ground_Concrete");
		}
	}
}

UHierarchicalInstancedStaticMeshComponent* AGTACity::GetInstancer(UStaticMesh* M, bool bCollision, const FString& FallbackMat)
{
	const FString Key = FString::Printf(TEXT("%s|%d|%s"), *M->GetPathName(), bCollision ? 1 : 0, *FallbackMat);
	if (TObjectPtr<UHierarchicalInstancedStaticMeshComponent>* Found = Instancers.Find(Key)) return Found->Get();
	UHierarchicalInstancedStaticMeshComponent* H = NewObject<UHierarchicalInstancedStaticMeshComponent>(this, NAME_None, RF_Transient);
	H->SetStaticMesh(M);
	H->SetMobility(EComponentMobility::Static);
	H->SetupAttachment(RootComponent);
	if (bCollision)
	{
		H->SetCollisionProfileName(TEXT("BlockAll"));
		H->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	}
	else
	{
		H->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}
	const float Radius = M->GetBounds().SphereRadius;
	if (Radius < 150.f) { H->InstanceStartCullDistance = 9000.f; H->InstanceEndCullDistance = 11000.f; }
	else if (Radius < 600.f) { H->InstanceStartCullDistance = 18000.f; H->InstanceEndCullDistance = 22000.f; }
	if (!FallbackMat.IsEmpty())
	{
		if (UMaterialInterface* Mat = FGTAAssets::Material(FallbackMat)) H->SetMaterial(0, Mat);
	}
	H->ComponentTags.Add(TEXT("GTACity"));
	H->RegisterComponent();
	AddInstanceComponent(H);
	Instancers.Add(Key, H);
	return H;
}

void AGTACity::Place(const FString& Folder, const FString& Name, const FTransform& T, bool bCollision, const FVector& FallbackSizeM, const FString& FallbackMat)
{
	UStaticMesh* M = FGTAAssets::GenMesh(Folder, Name);
	FTransform X = T;
	FString Mat;
	if (!M)
	{
		MissingMeshCount++;
		if (FallbackSizeM.IsNearlyZero()) return;
		M = FGTAAssets::Cube();
		if (!M) return;
		X.SetScale3D(T.GetScale3D() * FallbackSizeM);
		X.AddToTranslation(T.GetRotation().RotateVector(FVector(0.f, 0.f, FallbackSizeM.Z * 50.f * T.GetScale3D().Z)));
		Mat = FallbackMat.IsEmpty() ? TEXT("E_Concrete") : FallbackMat;
	}
	UHierarchicalInstancedStaticMeshComponent* H = GetInstancer(M, bCollision, Mat);
	H->AddInstance(X, true);
	InstanceCount++;
}

void AGTACity::ClearVisuals()
{
	for (auto& KV : Instancers)
	{
		if (KV.Value) KV.Value->DestroyComponent();
	}
	Instancers.Reset();
	TArray<UHierarchicalInstancedStaticMeshComponent*> Old;
	GetComponents(Old);
	for (UHierarchicalInstancedStaticMeshComponent* C : Old) if (C && C->ComponentHasTag(TEXT("GTACity"))) C->DestroyComponent();
	InstanceCount = 0;
	MissingMeshCount = 0;
	StreetLamps.Reset();
	ParkingSpots.Reset();
	BoatSpots.Reset();
	AircraftSpots.Reset();
	Reserved.Reset();
}

bool AGTACity::IsReserved(const FBox2D& B) const
{
	for (const FBox2D& R : Reserved) if (R.Intersect(B)) return true;
	return false;
}

void AGTACity::BuildVisuals()
{
	ClearVisuals();
	BuildLayout();
	BuildBounds();
	BuildRoads();
	BuildCoastAndHarbor();
	BuildAirfield();
	BuildSpecials();
	BuildPark();
	BuildBlocks();
	BuildStreetProps();
	for (auto& KV : Instancers) if (KV.Value) KV.Value->BuildTreeIfOutdated(false, true);
}

// ------------------------------------------------------------------------------------------------ roads

void AGTACity::BuildRoads()
{
	for (int32 n = 0; n < Nodes.Num(); ++n)
	{
		const FGTARoadNode& N = Nodes[n];
		bool Arm[4] = { false, false, false, false };   // +X, -X, +Y, -Y
		for (int32 E : N.Edges)
		{
			const int32 O = Edges[E].A == n ? Edges[E].B : Edges[E].A;
			const FVector D = (Nodes[O].Pos - N.Pos).GetSafeNormal2D();
			if (D.X > 0.7f) Arm[0] = true; else if (D.X < -0.7f) Arm[1] = true; else if (D.Y > 0.7f) Arm[2] = true; else Arm[3] = true;
		}
		const int32 Count = Arm[0] + Arm[1] + Arm[2] + Arm[3];
		FString Mesh = TEXT("SM_Road_Cross");
		float Yaw = 0.f;
		if (Count == 3)
		{
			Mesh = TEXT("SM_Road_T");
			Yaw = !Arm[3] ? 0.f : (!Arm[0] ? 90.f : (!Arm[2] ? 180.f : -90.f));
		}
		else if (Count == 2)
		{
			if ((Arm[0] && Arm[1]) || (Arm[2] && Arm[3]))
			{
				Mesh = TEXT("SM_Road_Straight");
				Yaw = Arm[0] ? 0.f : 90.f;
			}
			else
			{
				Mesh = TEXT("SM_Road_Corner");
				Yaw = (Arm[0] && Arm[2]) ? 0.f : ((Arm[2] && Arm[1]) ? 90.f : ((Arm[1] && Arm[3]) ? 180.f : -90.f));
			}
		}
		else if (Count == 1)
		{
			Mesh = TEXT("SM_Road_End");
			Yaw = Arm[0] ? 0.f : (Arm[2] ? 90.f : (Arm[1] ? 180.f : -90.f));
		}
		FVector Scale(1.f);
		if (Mesh == TEXT("SM_Road_Straight")) Scale = FVector(1.6f, 1.f, 1.f);
		Place(TEXT("Environment"), Mesh, FTransform(FRotator(0.f, Yaw, 0.f), N.Pos, Scale), true, FVector(16.f, 16.f, 0.1f), TEXT("E_Asphalt"));
	}
	for (int32 e = 0; e < Edges.Num(); ++e)
	{
		const FGTARoadEdge& E = Edges[e];
		const FVector A = Nodes[E.A].Pos + E.Dir * CorridorHalf;
		const float L = E.Length - 2.f * CorridorHalf;
		if (L <= 10.f) continue;
		const int32 Count = FMath::Max(1, FMath::RoundToInt(L / 1000.f));
		const float PieceLen = L / Count;
		const float Yaw = E.Dir.Rotation().Yaw;
		for (int32 i = 0; i < Count; ++i)
		{
			const FVector C = A + E.Dir * (PieceLen * (i + 0.5f));
			Place(TEXT("Environment"), TEXT("SM_Road_Straight"), FTransform(FRotator(0.f, Yaw, 0.f), C, FVector(PieceLen / 1000.f, 1.f, 1.f)), true, FVector(10.f, 16.f, 0.1f), TEXT("E_Asphalt"));
		}
		// crosswalks at signalised ends
		if (Nodes[E.A].bSignal) Place(TEXT("Environment"), TEXT("SM_Road_Crosswalk"), FTransform(FRotator(0.f, Yaw, 0.f), A + E.Dir * 250.f + FVector(0, 0, 1.f)), false);
		if (Nodes[E.B].bSignal) Place(TEXT("Environment"), TEXT("SM_Road_Crosswalk"), FTransform(FRotator(0.f, Yaw, 0.f), A + E.Dir * (L - 250.f) + FVector(0, 0, 1.f)), false);
	}
}

// ------------------------------------------------------------------------------------------------ blocks

bool AGTACity::SideHasRoad(const FGTABlock& B, int32 Side) const
{
	const FVector2D C = B.Rect.GetCenter();
	FVector P;
	switch (Side)
	{
	case 0: P = FVector(B.Rect.Min.X - CorridorHalf, C.Y, 0.f); break;   // south (-X)
	case 1: P = FVector(B.Rect.Max.X + CorridorHalf, C.Y, 0.f); break;   // north (+X)
	case 2: P = FVector(C.X, B.Rect.Min.Y - CorridorHalf, 0.f); break;   // west (-Y)
	default: P = FVector(C.X, B.Rect.Max.Y + CorridorHalf, 0.f); break;  // east (+Y)
	}
	const int32 E = NearestEdge(P);
	if (E == INDEX_NONE) return false;
	const FVector Q = FMath::ClosestPointOnSegment(P, Nodes[Edges[E].A].Pos, Nodes[Edges[E].B].Pos);
	return FVector::Dist2D(P, Q) < 300.f;
}

bool AGTACity::PlaceRow(const FGTABlock& B, int32 Side, float MaxDepth, TArray<FBox2D>& Used, FRandomStream& R)
{
	const bool bAlongY = Side <= 1;              // south/north sides run along Y
	const float Start = bAlongY ? B.Rect.Min.Y : B.Rect.Min.X;
	const float End = bAlongY ? B.Rect.Max.Y : B.Rect.Max.X;
	const float Yaw = Side == 0 ? 180.f : (Side == 1 ? 0.f : (Side == 2 ? -90.f : 90.f));
	TArray<int32> Cands;
	for (int32 i = 0; i < UE_ARRAY_COUNT(GBuildings); ++i)
	{
		if ((GBuildings[i].Districts & DM(B.District)) && GBuildings[i].D * 100.f + GBuildings[i].Setback * 100.f <= MaxDepth) Cands.Add(i);
	}
	if (Cands.Num() == 0) return false;
	bool bAny = false;
	float Pos = Start + 100.f;
	int32 Guard = 0;
	while (Pos < End - 600.f && Guard++ < 40)
	{
		// shuffle candidates
		for (int32 i = Cands.Num() - 1; i > 0; --i) Cands.Swap(i, R.RandRange(0, i));
		bool bPlaced = false;
		for (int32 Ci : Cands)
		{
			const FGTABldDef& D = GBuildings[Ci];
			const float W = D.W * 100.f, Dp = D.D * 100.f, Sb = D.Setback * 100.f;
			if (Pos + W > End - 100.f) continue;
			const float Along = Pos + W * 0.5f;
			float Across;
			switch (Side)
			{
			case 0: Across = B.Rect.Min.X + Sb + Dp * 0.5f; break;
			case 1: Across = B.Rect.Max.X - Sb - Dp * 0.5f; break;
			case 2: Across = B.Rect.Min.Y + Sb + Dp * 0.5f; break;
			default: Across = B.Rect.Max.Y - Sb - Dp * 0.5f; break;
			}
			const FVector2D C = bAlongY ? FVector2D(Across, Along) : FVector2D(Along, Across);
			const FVector2D Ext = bAlongY ? FVector2D(Dp * 0.5f, W * 0.5f) : FVector2D(W * 0.5f, Dp * 0.5f);
			const FBox2D Box(C - Ext - FVector2D(60.f), C + Ext + FVector2D(60.f));
			bool bHit = IsReserved(Box);
			for (const FBox2D& U : Used) if (U.Intersect(Box)) { bHit = true; break; }
			if (bHit) continue;
			Used.Add(Box);
			Place(TEXT("Buildings"), D.Name, FTransform(FRotator(0.f, Yaw, 0.f), FVector(C.X, C.Y, 15.f)), true, FVector(D.D, D.W, D.H), D.Mat);
			Pos += W + R.FRandRange(150.f, 450.f);
			bPlaced = bAny = true;
			break;
		}
		if (!bPlaced) Pos += 300.f;
	}
	return bAny;
}

void AGTACity::BuildBlock(const FGTABlock& B, int32 Seed)
{
	FRandomStream R(Seed * 7919 + 17);
	// ground slab, tiled in ~10 m pieces (top at +15 cm, same height as sidewalks)
	const FVector2D Size = B.Rect.GetSize();
	const int32 NX = FMath::Max(1, FMath::RoundToInt(Size.X / 1000.f));
	const int32 NY = FMath::Max(1, FMath::RoundToInt(Size.Y / 1000.f));
	const FString Ground = GroundMeshFor(B.District);
	for (int32 i = 0; i < NX; ++i)
	{
		for (int32 j = 0; j < NY; ++j)
		{
			const FVector C(B.Rect.Min.X + Size.X * (i + 0.5f) / NX, B.Rect.Min.Y + Size.Y * (j + 0.5f) / NY, 0.f);
			Place(TEXT("Environment"), Ground, FTransform(FRotator::ZeroRotator, C, FVector(Size.X / NX / 1000.f, Size.Y / NY / 1000.f, 1.f)), true,
				FVector(10.f, 10.f, 0.15f), B.District == EGTADistrict::Hills ? TEXT("E_Grass") : TEXT("E_Concrete"));
		}
	}
	if (B.District == EGTADistrict::Park || B.District == EGTADistrict::Airfield || B.District == EGTADistrict::Beach || B.District == EGTADistrict::Sea) return;
	TArray<FBox2D> Used;
	bool bRoad[4];
	for (int32 s = 0; s < 4; ++s) bRoad[s] = SideHasRoad(B, s);
	const float HalfX = Size.X * 0.5f - 100.f, HalfY = Size.Y * 0.5f - 100.f;
	// rows along roads; long sides first
	const int32 Order[4] = { 0, 1, 2, 3 };
	for (int32 k = 0; k < 4; ++k)
	{
		const int32 s = Order[k];
		if (!bRoad[s]) continue;
		const bool bOppositeRoad = bRoad[s ^ 1];
		const float Max = (s <= 1 ? (bOppositeRoad ? HalfX : Size.X - 200.f) : (bOppositeRoad ? HalfY : Size.Y - 200.f));
		PlaceRow(B, s, Max, Used, R);
	}
	BuildCourtyard(B, Used, R);
}

void AGTACity::BuildBlocks()
{
	for (int32 i = 0; i < Blocks.Num(); ++i) BuildBlock(Blocks[i], i);
}

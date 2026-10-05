// Port Halcyon layout (meters in the tables, centimeters in the data) and road-graph queries.
#include "World/GTACity.h"
#include "Core/GTAGame.h"
#include "Components/HierarchicalInstancedStaticMeshComponent.h"
#include "Components/PointLightComponent.h"

static const float GTAGridX[] = { -175.f, -105.f, -35.f, 35.f, 105.f, 175.f, 245.f };
static const float GTAGridY[] = { -265.f, -190.f, -115.f, -40.f, 35.f, 110.f, 165.f };

AGTACity::AGTACity()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickInterval = 0.1f;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent->SetMobility(EComponentMobility::Static);
}

// ------------------------------------------------------------------------------------------------ static geography

bool AGTACity::IsWaterAt(float X, float Y)
{
	if (FMath::Abs(Y) > 36000.f || X < -36000.f) return true;
	if (Y < -19000.f) return X < CoastX;            // harbor quay: vertical wall at the coast line
	return X < -19840.f;                             // beach: shoreline where the slope crosses sea level
}

float AGTACity::TerrainHeightAt(float X, float Y)
{
	if (X >= CoastX) return 0.f;
	if (Y < -19000.f) return X > -30000.f ? -900.f : -1600.f;
	if (X > -21500.f) return FMath::Lerp(0.f, -250.f, (CoastX - X) / (CoastX + 21500.f));
	if (X > -30000.f) return FMath::Lerp(-250.f, -1600.f, (-21500.f - X) / 8500.f);
	return -1600.f;
}

EGTADistrict AGTACity::DistrictAt(float X, float Y)
{
	const float Xm = X / 100.f, Ym = Y / 100.f;
	if (Xm < -183.f) return (IsWaterAt(X, Y) ? EGTADistrict::Sea : EGTADistrict::Beach);
	if (Ym > 172.f) return EGTADistrict::Airfield;
	if (Xm >= 175.f && Ym >= -40.f) return EGTADistrict::Park;
	if (Xm >= 105.f && Ym < -40.f) return EGTADistrict::Hills;
	if (Xm < -40.f && Ym < -198.f) return EGTADistrict::Harbor;
	if (Ym < -115.f && Xm >= -40.f) return EGTADistrict::Industrial;
	if (Xm >= -35.f && Ym >= -40.f) return EGTADistrict::Downtown;
	return EGTADistrict::NeonRow;
}

FString AGTACity::DistrictName(EGTADistrict D)
{
	switch (D)
	{
	case EGTADistrict::Downtown: return TEXT("Lumen Heights");
	case EGTADistrict::NeonRow: return TEXT("Neon Row");
	case EGTADistrict::Beach: return TEXT("Coral Strip");
	case EGTADistrict::Harbor: return TEXT("Saltworks Docks");
	case EGTADistrict::Industrial: return TEXT("Rustline");
	case EGTADistrict::Hills: return TEXT("Palmetto Hills");
	case EGTADistrict::Park: return TEXT("Tidewater Park");
	case EGTADistrict::Airfield: return TEXT("Gullwing Field");
	case EGTADistrict::Sea: return TEXT("Halcyon Bay");
	}
	return TEXT("Port Halcyon");
}

FString AGTACity::SectorName(const FVector& L) const
{
	const int32 Col = FMath::Clamp(FMath::FloorToInt((L.Y + HalfSize) / 10000.f), 0, 5);
	const int32 Row = FMath::Clamp(FMath::FloorToInt((L.X + HalfSize) / 10000.f), 0, 5);
	return FString::Printf(TEXT("%s  [%c%d]"), *DistrictName(DistrictAt(L.X, L.Y)), TCHAR('A' + Col), Row + 1);
}

// ------------------------------------------------------------------------------------------------ lifecycle

void AGTACity::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	BuildLayout();
#if WITH_EDITOR
	if (bBuildInEditor && GetWorld() && !GetWorld()->IsGameWorld()) BuildVisuals();
#endif
}

void AGTACity::BeginPlay()
{
	Super::BeginPlay();
	BuildLayout();
	if (Instancers.Num() == 0) BuildVisuals();
	UE_LOG(LogGTA, Log, TEXT("City: %d nodes, %d edges, %d blocks, %d POIs, %d instances, %d missing meshes"),
		Nodes.Num(), Edges.Num(), Blocks.Num(), POIs.Num(), InstanceCount, MissingMeshCount);
}

void AGTACity::Tick(float Dt)
{
	Super::Tick(Dt);
	SignalTime += Dt;
	LampTimer -= Dt;
	if (LampTimer <= 0.f) { LampTimer = 0.5f; TickLamps(); }
}

// ------------------------------------------------------------------------------------------------ layout

void AGTACity::AddNode(float Xm, float Ym)
{
	FGTARoadNode N;
	N.Pos = FVector(Xm * 100.f, Ym * 100.f, 0.f);
	Nodes.Add(N);
}

int32 AGTACity::FindNodeM(float Xm, float Ym) const
{
	for (int32 i = 0; i < Nodes.Num(); ++i)
	{
		if (FVector::Dist2D(Nodes[i].Pos, FVector(Xm * 100.f, Ym * 100.f, 0.f)) < 50.f) return i;
	}
	return INDEX_NONE;
}

void AGTACity::AddEdgeM(float AXm, float AYm, float BXm, float BYm)
{
	const int32 A = FindNodeM(AXm, AYm), B = FindNodeM(BXm, BYm);
	if (A == INDEX_NONE || B == INDEX_NONE) return;
	FGTARoadEdge E;
	E.A = A;
	E.B = B;
	E.Length = FVector::Dist2D(Nodes[A].Pos, Nodes[B].Pos);
	E.Dir = (Nodes[B].Pos - Nodes[A].Pos).GetSafeNormal2D();
	const int32 Idx = Edges.Add(E);
	Nodes[A].Edges.Add(Idx);
	Nodes[B].Edges.Add(Idx);
}

void AGTACity::AddPOI(EGTAPOI Type, const FString& Name, float Xm, float Ym, float Yaw, int32 Index)
{
	FGTAPOIData P;
	P.Type = Type;
	P.Name = Name;
	P.T = FTransform(FRotator(0.f, Yaw, 0.f), FVector(Xm * 100.f, Ym * 100.f, 0.f));
	P.Index = Index;
	POIs.Add(P);
}

void AGTACity::BuildLayout()
{
	if (bLayoutBuilt) return;
	bLayoutBuilt = true;
	Nodes.Reset(); Edges.Reset(); POIs.Reset(); Blocks.Reset(); ParkingSpots.Reset(); BoatSpots.Reset(); AircraftSpots.Reset(); Teleports.Reset();

	auto Excluded = [](float X, float Y)
	{
		return (X == -175.f && Y == -265.f) || (X == 245.f && Y >= 35.f);
	};
	for (float X : GTAGridX) for (float Y : GTAGridY) if (!Excluded(X, Y)) AddNode(X, Y);
	AddNode(35.f, 200.f);   // airfield gate spur
	for (int32 i = 0; i < UE_ARRAY_COUNT(GTAGridX); ++i)
	{
		for (int32 j = 0; j < UE_ARRAY_COUNT(GTAGridY); ++j)
		{
			if (i + 1 < UE_ARRAY_COUNT(GTAGridX)) AddEdgeM(GTAGridX[i], GTAGridY[j], GTAGridX[i + 1], GTAGridY[j]);
			if (j + 1 < UE_ARRAY_COUNT(GTAGridY)) AddEdgeM(GTAGridX[i], GTAGridY[j], GTAGridX[i], GTAGridY[j + 1]);
		}
	}
	AddEdgeM(35.f, 165.f, 35.f, 200.f);
	for (FGTARoadNode& N : Nodes) N.bSignal = N.Edges.Num() >= 4;

	// city blocks (interior of the road grid + border strips)
	for (int32 i = 0; i + 1 < UE_ARRAY_COUNT(GTAGridX); ++i)
	{
		for (int32 j = 0; j + 1 < UE_ARRAY_COUNT(GTAGridY); ++j)
		{
			FGTABlock B;
			B.Rect = FBox2D(FVector2D(GTAGridX[i] * 100.f + CorridorHalf, GTAGridY[j] * 100.f + CorridorHalf),
				FVector2D(GTAGridX[i + 1] * 100.f - CorridorHalf, GTAGridY[j + 1] * 100.f - CorridorHalf));
			const FVector2D C = B.Rect.GetCenter();
			B.District = DistrictAt(C.X, C.Y);
			Blocks.Add(B);
		}
	}
	// west border strip (beyond road Y=-265) and north strip (beyond road X=245)
	for (int32 i = 1; i + 1 < UE_ARRAY_COUNT(GTAGridX); ++i)
	{
		FGTABlock B;
		B.Rect = FBox2D(FVector2D(GTAGridX[i] * 100.f + CorridorHalf, -29400.f), FVector2D(GTAGridX[i + 1] * 100.f - CorridorHalf, -26500.f - CorridorHalf));
		B.District = DistrictAt(B.Rect.GetCenter().X, B.Rect.GetCenter().Y);
		Blocks.Add(B);
	}
	for (int32 j = 0; j + 1 < UE_ARRAY_COUNT(GTAGridY) && GTAGridY[j + 1] <= -40.f; ++j)
	{
		FGTABlock B;
		B.Rect = FBox2D(FVector2D(24500.f + CorridorHalf, GTAGridY[j] * 100.f + CorridorHalf), FVector2D(29400.f, GTAGridY[j + 1] * 100.f - CorridorHalf));
		B.District = EGTADistrict::Hills;
		Blocks.Add(B);
	}
	// strip between the beach road and the airfield fence (north side of road Y=165)
	for (int32 i = 0; i + 1 < UE_ARRAY_COUNT(GTAGridX) && GTAGridX[i + 1] <= 175.f; ++i)
	{
		FGTABlock B;
		B.Rect = FBox2D(FVector2D(GTAGridX[i] * 100.f + CorridorHalf, 16500.f + CorridorHalf), FVector2D(GTAGridX[i + 1] * 100.f - CorridorHalf, 17200.f));
		B.District = EGTADistrict::NeonRow;
		if (GTAGridX[i] == 35.f) continue; // gate spur
		Blocks.Add(B);
	}

	// points of interest (interaction point on the sidewalk, yaw = facing the entrance)
	AddPOI(EGTAPOI::Safehouse, TEXT("Coral Bungalow"), -166.f, 137.f, 0.f, 0);
	AddPOI(EGTAPOI::Safehouse, TEXT("Lumen Loft"), 44.f, 72.f, 0.f, 1);
	AddPOI(EGTAPOI::Safehouse, TEXT("Palmetto House"), 184.f, -152.f, 0.f, 2);
	AddPOI(EGTAPOI::PoliceStation, TEXT("Halcyon PD"), -96.f, -77.f, 0.f);
	AddPOI(EGTAPOI::Hospital, TEXT("St. Brine Hospital"), -96.f, 72.f, 0.f);
	AddPOI(EGTAPOI::GasStation, TEXT("Tidewater Fuel"), -166.f, -77.f, 0.f);
	AddPOI(EGTAPOI::ModShop, TEXT("Riptide Customs"), -26.f, -152.f, 0.f);
	AddPOI(EGTAPOI::GunShop, TEXT("Halcyon Arms"), -166.f, 60.f, 0.f);
	AddPOI(EGTAPOI::ClothesShop, TEXT("Driftwear"), -166.f, -12.f, 0.f);
	AddPOI(EGTAPOI::Barber, TEXT("Salt & Fade Barbers"), -166.f, 10.f, 0.f);
	AddPOI(EGTAPOI::Diner, TEXT("Neon Gull Diner"), -166.f, 88.f, 0.f);
	AddPOI(EGTAPOI::Garage, TEXT("Coral Garage"), -166.f, 152.f, 0.f, 0);
	AddPOI(EGTAPOI::Garage, TEXT("Lumen Parking"), 44.f, 92.f, 0.f, 1);
	AddPOI(EGTAPOI::Garage, TEXT("Palmetto Garage"), 184.f, -170.f, 0.f, 2);
	AddPOI(EGTAPOI::Marina, TEXT("Saltworks Marina"), -180.f, -232.f, 180.f);
	AddPOI(EGTAPOI::Helipad, TEXT("Gullwing Helipad"), 120.f, 285.f, 0.f);
	AddPOI(EGTAPOI::Hangar, TEXT("Gullwing Hangar"), -60.f, 268.f, 90.f);
	AddPOI(EGTAPOI::ShootingRange, TEXT("Rustline Range"), 44.f, -152.f, 0.f);
	AddPOI(EGTAPOI::TaxiStand, TEXT("Neon Row Taxi"), -113.f, 0.f, 0.f);
	AddPOI(EGTAPOI::StuntJump, TEXT("Gullwing Gate Jump"), 35.f, 190.f, 90.f, 0);
	AddPOI(EGTAPOI::StuntJump, TEXT("Docks Leap"), -176.f, -190.f, 180.f, 1);
	AddPOI(EGTAPOI::StuntJump, TEXT("Park Hop"), 183.f, 70.f, 0.f, 2);
	AddPOI(EGTAPOI::Landmark, TEXT("Halcyon Spire"), 70.f, -3.f, 0.f);
	AddPOI(EGTAPOI::Landmark, TEXT("Lighthouse Point"), -222.f, -280.f, 0.f);
	AddPOI(EGTAPOI::Landmark, TEXT("Coral Pier"), -215.f, 40.f, 180.f);

	PlayerSpawn = FTransform(FRotator(0.f, 180.f, 0.f), FVector(-16950.f, 13700.f, 120.f));
	HospitalRespawn = FTransform(FRotator(0.f, 180.f, 0.f), FVector(-9900.f, 7200.f, 120.f));
	PoliceRespawn = FTransform(FRotator(0.f, 180.f, 0.f), FVector(-9900.f, -7700.f, 120.f));

	Teleports = {
		{ TEXT("Coral Bungalow (spawn)"), FVector(-16950.f, 13700.f, 150.f) },
		{ TEXT("Lumen Heights downtown"), FVector(7000.f, 7200.f, 150.f) },
		{ TEXT("Neon Row strip"), FVector(-14000.f, 0.f, 150.f) },
		{ TEXT("Coral Strip beach"), FVector(-19000.f, 4000.f, 150.f) },
		{ TEXT("Saltworks Docks"), FVector(-9000.f, -23000.f, 150.f) },
		{ TEXT("Rustline industrial"), FVector(3500.f, -19000.f, 150.f) },
		{ TEXT("Palmetto Hills"), FVector(20000.f, -15000.f, 150.f) },
		{ TEXT("Tidewater Park"), FVector(23000.f, 6000.f, 150.f) },
		{ TEXT("Gullwing Field (airfield)"), FVector(-2000.f, 26500.f, 150.f) },
		{ TEXT("Riptide Customs (mod shop)"), FVector(-2400.f, -15200.f, 150.f) },
		{ TEXT("Halcyon Arms (gun shop)"), FVector(-16400.f, 6000.f, 150.f) },
		{ TEXT("Saltworks Marina"), FVector(-17500.f, -23000.f, 150.f) },
		{ TEXT("Halcyon Spire rooftop"), FVector(7000.f, -500.f, 9300.f) },
	};
}

const FGTAPOIData* AGTACity::FindPOI(EGTAPOI Type, int32 Index) const
{
	for (const FGTAPOIData& P : POIs) if (P.Type == Type && (Index < 0 || P.Index == Index)) return &P;
	return nullptr;
}

const FGTAPOIData* AGTACity::NearestPOI(EGTAPOI Type, const FVector& L, float MaxDist) const
{
	const FGTAPOIData* Best = nullptr;
	float BestD = MaxDist;
	for (const FGTAPOIData& P : POIs)
	{
		if (P.Type != Type) continue;
		const float D = FVector::Dist2D(P.T.GetLocation(), L);
		if (D < BestD) { BestD = D; Best = &P; }
	}
	return Best;
}

// ------------------------------------------------------------------------------------------------ road queries

int32 AGTACity::NearestNode(const FVector& L) const
{
	int32 Best = INDEX_NONE;
	float BestD = 1e12f;
	for (int32 i = 0; i < Nodes.Num(); ++i)
	{
		const float D = FVector::DistSquared2D(Nodes[i].Pos, L);
		if (D < BestD) { BestD = D; Best = i; }
	}
	return Best;
}

int32 AGTACity::NearestEdge(const FVector& L, float* OutT) const
{
	int32 Best = INDEX_NONE;
	float BestD = 1e12f, BestT = 0.f;
	for (int32 i = 0; i < Edges.Num(); ++i)
	{
		const FVector A = Nodes[Edges[i].A].Pos, B = Nodes[Edges[i].B].Pos;
		const FVector P = FMath::ClosestPointOnSegment(FVector(L.X, L.Y, 0.f), A, B);
		const float D = FVector::DistSquared2D(P, L);
		if (D < BestD) { BestD = D; Best = i; BestT = FVector::Dist2D(A, P) / FMath::Max(Edges[i].Length, 1.f); }
	}
	if (OutT) *OutT = BestT;
	return Best;
}

FVector AGTACity::LaneDir(int32 Edge, bool bForward) const
{
	return bForward ? Edges[Edge].Dir : -Edges[Edge].Dir;
}

FVector AGTACity::LanePoint(int32 Edge, bool bForward, float Alpha) const
{
	const FGTARoadEdge& E = Edges[Edge];
	const FVector Start = Nodes[bForward ? E.A : E.B].Pos;
	const FVector End = Nodes[bForward ? E.B : E.A].Pos;
	const FVector Dir = (End - Start).GetSafeNormal2D();
	const FVector Right(-Dir.Y, Dir.X, 0.f);   // UE: X fwd, Y right -> right of travel
	return FMath::Lerp(Start, End, Alpha) + Right * LaneOffset;
}

FVector AGTACity::SidewalkPoint(int32 Edge, bool bLeftSide, float Alpha) const
{
	const FGTARoadEdge& E = Edges[Edge];
	const FVector A = Nodes[E.A].Pos, B = Nodes[E.B].Pos;
	const FVector Right(-E.Dir.Y, E.Dir.X, 0.f);
	return FMath::Lerp(A, B, Alpha) + Right * (bLeftSide ? -1.f : 1.f) * (RoadHalfWidth + 150.f) + FVector(0, 0, 15.f);
}

int32 AGTACity::PickNextEdge(int32 Node, int32 FromEdge, FRandomStream& R) const
{
	const FGTARoadNode& N = Nodes[Node];
	TArray<int32, TInlineAllocator<4>> Options;
	for (int32 E : N.Edges) if (E != FromEdge) Options.Add(E);
	if (Options.Num() == 0) return FromEdge;
	// prefer going straight a little more often
	if (FromEdge != INDEX_NONE && Options.Num() > 1 && R.FRand() < 0.4f)
	{
		const FVector InDir = (N.Pos - Nodes[Edges[FromEdge].A == Node ? Edges[FromEdge].B : Edges[FromEdge].A].Pos).GetSafeNormal2D();
		for (int32 E : Options)
		{
			const int32 Other = Edges[E].A == Node ? Edges[E].B : Edges[E].A;
			if (FVector::DotProduct((Nodes[Other].Pos - N.Pos).GetSafeNormal2D(), InDir) > 0.9f) return E;
		}
	}
	return Options[R.RandRange(0, Options.Num() - 1)];
}

bool AGTACity::SignalGreenFor(int32 Node, const FVector& TravelDir) const
{
	if (!Nodes.IsValidIndex(Node) || !Nodes[Node].bSignal) return true;
	// 22 s cycle: 9 s green X-axis, 2 s all red, 9 s green Y-axis, 2 s all red. Offset per node.
	const float Cycle = FMath::Fmod(SignalTime + Node * 3.7f, 22.f);
	const bool bAlongX = FMath::Abs(TravelDir.X) > FMath::Abs(TravelDir.Y);
	if (bAlongX) return Cycle < 9.f;
	return Cycle >= 11.f && Cycle < 20.f;
}

bool AGTACity::RandomLaneSpawn(const FVector& Near, float MinDist, float MaxDist, FRandomStream& R, int32& OutEdge, bool& bOutForward, float& OutAlpha) const
{
	for (int32 Try = 0; Try < 24; ++Try)
	{
		const int32 E = R.RandRange(0, Edges.Num() - 1);
		const float A = R.FRandRange(0.2f, 0.8f);
		const bool bF = R.FRand() < 0.5f;
		const FVector P = LanePoint(E, bF, A);
		const float D = FVector::Dist2D(P, Near);
		if (D >= MinDist && D <= MaxDist)
		{
			OutEdge = E;
			bOutForward = bF;
			OutAlpha = A;
			return true;
		}
	}
	return false;
}

bool AGTACity::RandomSidewalkPoint(const FVector& Near, float MinDist, float MaxDist, FRandomStream& R, FVector& Out) const
{
	for (int32 Try = 0; Try < 24; ++Try)
	{
		const int32 E = R.RandRange(0, Edges.Num() - 1);
		const FVector P = SidewalkPoint(E, R.FRand() < 0.5f, R.FRandRange(0.15f, 0.85f));
		const float D = FVector::Dist2D(P, Near);
		if (D >= MinDist && D <= MaxDist) { Out = P; return true; }
	}
	return false;
}

int32 AGTACity::EdgeBetween(int32 A, int32 B) const
{
	if (!Nodes.IsValidIndex(A)) return INDEX_NONE;
	for (int32 E : Nodes[A].Edges) if (Edges[E].A == B || Edges[E].B == B) return E;
	return INDEX_NONE;
}

bool AGTACity::FindRoute(int32 FromNode, int32 ToNode, TArray<int32>& OutNodes) const
{
	OutNodes.Reset();
	if (!Nodes.IsValidIndex(FromNode) || !Nodes.IsValidIndex(ToNode)) return false;
	TArray<float> G;
	G.Init(1e12f, Nodes.Num());
	TArray<int32> Prev;
	Prev.Init(INDEX_NONE, Nodes.Num());
	TArray<bool> Closed;
	Closed.Init(false, Nodes.Num());
	G[FromNode] = 0.f;
	for (int32 Iter = 0; Iter < Nodes.Num(); ++Iter)
	{
		int32 Cur = INDEX_NONE;
		float BestF = 1e12f;
		for (int32 i = 0; i < Nodes.Num(); ++i)
		{
			if (Closed[i] || G[i] >= 1e12f) continue;
			const float F = G[i] + FVector::Dist2D(Nodes[i].Pos, Nodes[ToNode].Pos);
			if (F < BestF) { BestF = F; Cur = i; }
		}
		if (Cur == INDEX_NONE) break;
		if (Cur == ToNode) break;
		Closed[Cur] = true;
		for (int32 E : Nodes[Cur].Edges)
		{
			const int32 O = Edges[E].A == Cur ? Edges[E].B : Edges[E].A;
			const float NG = G[Cur] + Edges[E].Length;
			if (NG < G[O]) { G[O] = NG; Prev[O] = Cur; }
		}
	}
	if (G[ToNode] >= 1e12f) return false;
	for (int32 N = ToNode; N != INDEX_NONE; N = Prev[N]) OutNodes.Insert(N, 0);
	return OutNodes.Num() > 0 && OutNodes[0] == FromNode;
}

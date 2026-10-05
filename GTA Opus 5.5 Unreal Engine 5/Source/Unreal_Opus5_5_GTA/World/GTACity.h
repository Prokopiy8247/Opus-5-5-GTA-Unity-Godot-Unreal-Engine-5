// Port Halcyon: deterministic 600 x 600 m city layout, road graph, points of interest and instanced visuals.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/GTATypes.h"
#include "GTACity.generated.h"

class UHierarchicalInstancedStaticMeshComponent;
class UStaticMesh;
class UPointLightComponent;

UENUM()
enum class EGTADistrict : uint8 { Downtown, NeonRow, Beach, Harbor, Industrial, Hills, Park, Airfield, Sea };

UENUM()
enum class EGTAPOI : uint8
{
	Safehouse, PoliceStation, Hospital, GasStation, ModShop, GunShop, ClothesShop, Barber, Garage, Marina, Helipad, Hangar,
	ShootingRange, StuntJump, TaxiStand, BusStop, ATM, Vending, Diner, Landmark, TrainStation
};

struct FGTARoadNode
{
	FVector Pos = FVector::ZeroVector;
	TArray<int32> Edges;
	bool bSignal = false;      // traffic light controlled
};

struct FGTARoadEdge
{
	int32 A = -1;
	int32 B = -1;
	float Length = 0.f;
	FVector Dir = FVector::ForwardVector;   // A -> B
};

struct FGTAPOIData
{
	EGTAPOI Type = EGTAPOI::Landmark;
	FString Name;
	FTransform T;              // interaction point, facing into the building
	int32 Index = 0;           // e.g. safehouse id
};

struct FGTASignalPole
{
	int32 Node = 0;
	FVector Dir = FVector::ForwardVector;
	FTransform Red;
	FTransform Green;
};

struct FGTABlock
{
	FBox2D Rect;               // cm, inside sidewalks
	EGTADistrict District = EGTADistrict::Downtown;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTACity : public AActor
{
	GENERATED_BODY()
public:
	AGTACity();
	virtual void OnConstruction(const FTransform& Transform) override;
	virtual void Tick(float DeltaSeconds) override;

	// ---------------------------------------------------------------- constants (cm)
	static constexpr float HalfSize = 30000.f;
	static constexpr float SeaLevelZ = -120.f;
	static constexpr float CoastX = -18300.f;          // land ends (beach starts sloping down)
	static constexpr float WaterX = -21500.f;          // open water begins
	static constexpr float RoadHalfWidth = 500.f;      // asphalt
	static constexpr float CorridorHalf = 800.f;       // asphalt + sidewalk
	static constexpr float LaneOffset = 250.f;         // lane center from road center
	static bool IsWaterAt(float X, float Y);
	static float TerrainHeightAt(float X, float Y);   // analytic ground height (beach slope / sea floor)
	static EGTADistrict DistrictAt(float X, float Y);
	static FString DistrictName(EGTADistrict D);
	FString SectorName(const FVector& L) const;

	// ---------------------------------------------------------------- layout data
	TArray<FGTARoadNode> Nodes;
	TArray<FGTARoadEdge> Edges;
	TArray<FGTAPOIData> POIs;
	TArray<FGTABlock> Blocks;
	TArray<FTransform> ParkingSpots;
	TArray<FTransform> BoatSpots;
	TArray<FTransform> AircraftSpots;    // helipad / apron
	TArray<FTransform> StreetLamps;
	FTransform PlayerSpawn;
	FTransform HospitalRespawn;
	FTransform PoliceRespawn;
	TArray<TPair<FString, FVector>> Teleports;

	const FGTAPOIData* FindPOI(EGTAPOI Type, int32 Index = -1) const;
	const FGTAPOIData* NearestPOI(EGTAPOI Type, const FVector& L, float MaxDist = 1e9f) const;

	// ---------------------------------------------------------------- road queries (traffic / AI)
	int32 NearestNode(const FVector& L) const;
	int32 NearestEdge(const FVector& L, float* OutT = nullptr) const;
	FVector LanePoint(int32 Edge, bool bForward, float Alpha) const;   // alpha 0..1 along travel direction
	FVector LaneDir(int32 Edge, bool bForward) const;
	int32 EdgeEndNode(int32 Edge, bool bForward) const { return bForward ? Edges[Edge].B : Edges[Edge].A; }
	int32 EdgeStartNode(int32 Edge, bool bForward) const { return bForward ? Edges[Edge].A : Edges[Edge].B; }
	int32 PickNextEdge(int32 Node, int32 FromEdge, FRandomStream& R) const;
	bool NextEdgeForward(int32 Edge, int32 FromNode) const { return Edges.IsValidIndex(Edge) && Edges[Edge].A == FromNode; }
	bool SignalGreenFor(int32 Node, const FVector& TravelDir) const;
	bool RandomLaneSpawn(const FVector& Near, float MinDist, float MaxDist, FRandomStream& R, int32& OutEdge, bool& bOutForward, float& OutAlpha) const;
	bool RandomSidewalkPoint(const FVector& Near, float MinDist, float MaxDist, FRandomStream& R, FVector& Out) const;
	FVector SidewalkPoint(int32 Edge, bool bLeftSide, float Alpha) const;
	/** A* over the node graph; returns node sequence. */
	bool FindRoute(int32 FromNode, int32 ToNode, TArray<int32>& OutNodes) const;
	int32 EdgeBetween(int32 A, int32 B) const;
	float SignalTime = 0.f;

	// ---------------------------------------------------------------- visuals
	UPROPERTY(Transient) TMap<FString, TObjectPtr<UHierarchicalInstancedStaticMeshComponent>> Instancers;
	UPROPERTY(Transient) TArray<TObjectPtr<UPointLightComponent>> LampLights;
	UPROPERTY(Transient) TObjectPtr<class UInstancedStaticMeshComponent> SignalRed;
	UPROPERTY(Transient) TObjectPtr<class UInstancedStaticMeshComponent> SignalGreen;
	TArray<FGTASignalPole> SignalPoles;
	UPROPERTY(EditAnywhere, Category = "GTA") bool bBuildInEditor = true;
	int32 InstanceCount = 0;
	int32 MissingMeshCount = 0;

	void BuildLayout();
	void BuildVisuals();
	void ClearVisuals();
	/** Places a Blender-generated mesh. If missing, a scaled engine cube with the given fallback size (m) is used. */
	void Place(const FString& Folder, const FString& Name, const FTransform& T, bool bCollision = true, const FVector& FallbackSizeM = FVector::ZeroVector, const FString& FallbackMat = TEXT(""));

protected:
	virtual void BeginPlay() override;

private:
	bool bLayoutBuilt = false;
	void AddNode(float Xm, float Ym);
	void AddEdgeM(float AXm, float AYm, float BXm, float BYm);
	int32 FindNodeM(float Xm, float Ym) const;
	void AddPOI(EGTAPOI Type, const FString& Name, float Xm, float Ym, float Yaw, int32 Index = 0);
	void BuildRoads();
	void BuildBlocks();
	void BuildBlock(const FGTABlock& B, int32 Seed);
	void BuildCoastAndHarbor();
	void BuildAirfield();
	void BuildPark();
	void BuildSpecials();
	void BuildStreetProps();
	void BuildBounds();
	void BuildCourtyard(const FGTABlock& B, const TArray<FBox2D>& Used, FRandomStream& R);
	bool PlaceRow(const FGTABlock& B, int32 Side, float MaxDepth, TArray<FBox2D>& Used, FRandomStream& R);
	bool SideHasRoad(const FGTABlock& B, int32 Side) const;
	void TickLamps();
	void TickSignals();
	void PlaceSpecial(EGTAPOI Type, int32 Index, const TCHAR* Mesh, float D, float W, float H, const TCHAR* Mat);
	void PlaceBox(const FVector& Center, const FVector& SizeCm, const FString& Mat, bool bCollision = true);
	UHierarchicalInstancedStaticMeshComponent* GetInstancer(UStaticMesh* M, bool bCollision, const FString& FallbackMat);
	TArray<FBox2D> Reserved;   // footprints already used by specials (cm)
	bool IsReserved(const FBox2D& B) const;
	float LampTimer = 0.f;
};

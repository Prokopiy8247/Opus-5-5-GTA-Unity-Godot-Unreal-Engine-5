// Port Halcyon special areas: bounds, coast/harbor, airfield, park, landmark buildings and street furniture.
#include "World/GTACity.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "World/GTAEnvironment.h"
#include "Components/HierarchicalInstancedStaticMeshComponent.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/PointLightComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Camera/PlayerCameraManager.h"

void AGTACity::PlaceBox(const FVector& Center, const FVector& SizeCm, const FString& Mat, bool bCollision)
{
	UStaticMesh* Cube = FGTAAssets::Cube();
	if (!Cube) return;
	GetInstancer(Cube, bCollision, Mat)->AddInstance(FTransform(FRotator::ZeroRotator, Center, SizeCm / 100.f), true);
	InstanceCount++;
}

// ------------------------------------------------------------------------------------------------ bounds

void AGTACity::BuildBounds()
{
	// base slab under the whole land area (catches any gap), outer land and deep sea floor
	PlaceBox(FVector(6100.f, 0.f, -53.f), FVector(48800.f, 61000.f, 100.f), TEXT("E_ConcreteDark"));
	PlaceBox(FVector(130000.f, 0.f, -53.f), FVector(199000.f, 400000.f, 100.f), TEXT("E_Grass"), false);
	PlaceBox(FVector(6100.f, 130000.f, -53.f), FVector(48800.f, 199000.f, 100.f), TEXT("E_Grass"), false);
	PlaceBox(FVector(6100.f, -130000.f, -53.f), FVector(48800.f, 199000.f, 100.f), TEXT("E_Grass"), false);
	PlaceBox(FVector(-130000.f, 0.f, -1650.f), FVector(200000.f, 400000.f, 100.f), TEXT("E_Sand"));
	PlaceBox(FVector(-24150.f, 66000.f, -1650.f), FVector(11700.f, 72000.f, 100.f), TEXT("E_Sand"));
	PlaceBox(FVector(-24150.f, -66000.f, -1650.f), FVector(11700.f, 72000.f, 100.f), TEXT("E_Sand"));

	// rocky cliffs on the three land edges (natural world boundary)
	for (float Y = -29000.f; Y <= 29000.f; Y += 2000.f)
		Place(TEXT("Nature"), TEXT("SM_Cliff"), FTransform(FRotator(0.f, 180.f, 0.f), FVector(30400.f, Y, 0.f)), true, FVector(8.f, 20.f, 16.f), TEXT("E_Rock"));
	for (float X = -18000.f; X <= 29000.f; X += 2000.f)
	{
		Place(TEXT("Nature"), TEXT("SM_Cliff"), FTransform(FRotator(0.f, 90.f, 0.f), FVector(X, -30400.f, 0.f)), true, FVector(8.f, 20.f, 16.f), TEXT("E_Rock"));
		Place(TEXT("Nature"), TEXT("SM_Cliff"), FTransform(FRotator(0.f, -90.f, 0.f), FVector(X, 30400.f, 0.f)), true, FVector(8.f, 20.f, 16.f), TEXT("E_Rock"));
	}
}

// ------------------------------------------------------------------------------------------------ coast / harbor

void AGTACity::BuildCoastAndHarbor()
{
	for (float Y = -19000.f; Y < 30000.f; Y += 2000.f)
		Place(TEXT("Environment"), TEXT("SM_Coast_Beach"), FTransform(FRotator::ZeroRotator, FVector(CoastX, Y + 1000.f, 0.f)), true);
	for (float Y = -30000.f; Y < -19000.f; Y += 2000.f)
		Place(TEXT("Environment"), TEXT("SM_Coast_Quay"), FTransform(FRotator::ZeroRotator, FVector(CoastX, Y + 1000.f, 0.f)), true);
	// sea surface (visual; buoyancy and swimming use SeaLevelZ)
	for (int32 i = 0; i < 8; ++i)
		for (int32 j = -10; j < 10; ++j)
			Place(TEXT("Environment"), TEXT("SM_Water_Tile"), FTransform(FRotator::ZeroRotator, FVector(CoastX - 5000.f - i * 10000.f, j * 10000.f + 5000.f, SeaLevelZ)), false,
				FVector(100.f, 100.f, 0.02f), TEXT("E_Water"));

	// harbor: piers, cranes, marina office, moored boat spots
	for (float Y : { -21000.f, -24000.f, -27000.f })
		Place(TEXT("Environment"), TEXT("SM_Pier"), FTransform(FRotator(0.f, 180.f, 0.f), FVector(CoastX, Y, 0.f)), true, FVector(40.f, 6.f, 0.4f), TEXT("E_Wood"));
	for (float Y : { -22500.f, -25500.f, -28500.f })
	{
		BoatSpots.Add(FTransform(FRotator(0.f, 180.f, 0.f), FVector(CoastX - 2000.f, Y, SeaLevelZ)));
	}
	BoatSpots.Add(FTransform(FRotator(0.f, 180.f, 0.f), FVector(-23000.f, 2500.f, SeaLevelZ)));
	for (float Y : { -21500.f, -26000.f })
		Place(TEXT("Environment"), TEXT("SM_Crane"), FTransform(FRotator(0.f, 90.f, 0.f), FVector(-17600.f, Y, 0.f)), true, FVector(12.f, 10.f, 35.f), TEXT("E_Yellow"));
	Place(TEXT("Buildings"), TEXT("SM_Bld_MarinaOffice"), FTransform(FRotator(0.f, 180.f, 0.f), FVector(-15600.f, -23200.f, 0.f)), true, FVector(10.f, 12.f, 5.f), TEXT("E_Plaster4"));
	Reserved.Add(FBox2D(FVector2D(-16300.f, -23900.f), FVector2D(-14900.f, -22500.f)));
	// lighthouse on its islet
	Place(TEXT("Nature"), TEXT("SM_Islet"), FTransform(FRotator::ZeroRotator, FVector(-22200.f, -28000.f, -400.f)), true, FVector(20.f, 20.f, 4.f), TEXT("E_Rock"));
	Place(TEXT("Buildings"), TEXT("SM_Lighthouse"), FTransform(FRotator::ZeroRotator, FVector(-22200.f, -28000.f, 0.f)), true, FVector(6.f, 6.f, 24.f), TEXT("E_White"));

	// beach: palms, lifeguard towers, umbrellas, huts, Coral Pier with the ferris wheel
	FRandomStream R(4242);
	for (float Y = -18000.f; Y < 29500.f; Y += 1800.f)
	{
		if (FMath::Abs(Y - 4000.f) < 1200.f) continue;
		const float X = -18700.f - R.FRandRange(0.f, 500.f);
		Place(TEXT("Nature"), R.FRand() < 0.5f ? TEXT("SM_Palm_A") : TEXT("SM_Palm_B"), FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), FVector(X, Y + R.FRandRange(-300.f, 300.f), TerrainHeightAt(X, Y))), true);
	}
	for (float Y : { -12000.f, 0.f, 12000.f, 23000.f })
		Place(TEXT("Props"), TEXT("SM_LifeguardTower"), FTransform(FRotator(0.f, 180.f, 0.f), FVector(-19300.f, Y, TerrainHeightAt(-19300.f, Y))), true, FVector(3.f, 3.f, 4.f), TEXT("E_Wood"));
	for (int32 i = 0; i < 26; ++i)
	{
		const float Y = R.FRandRange(-17000.f, 28000.f);
		if (FMath::Abs(Y - 4000.f) < 1500.f) continue;
		const float X = R.FRandRange(-19500.f, -18700.f);
		const float Z = TerrainHeightAt(X, Y);
		Place(TEXT("Props"), TEXT("SM_BeachUmbrella"), FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), FVector(X, Y, Z)), false);
		Place(TEXT("Props"), TEXT("SM_Lounger"), FTransform(FRotator(0.f, R.FRandRange(150.f, 210.f), 0.f), FVector(X + 150.f, Y + 120.f, TerrainHeightAt(X + 150.f, Y))), true);
	}
	for (float Y : { -6000.f, 8000.f, 18000.f })
		Place(TEXT("Buildings"), TEXT("SM_Bld_BeachHut"), FTransform(FRotator(0.f, 180.f, 0.f), FVector(-18800.f, Y, TerrainHeightAt(-18800.f, Y))), true, FVector(6.f, 8.f, 4.f), TEXT("E_Teal"));
	Place(TEXT("Environment"), TEXT("SM_Pier_Big"), FTransform(FRotator(0.f, 180.f, 0.f), FVector(CoastX, 4000.f, 0.f)), true, FVector(60.f, 14.f, 0.5f), TEXT("E_Wood"));
	Place(TEXT("Props"), TEXT("SM_FerrisWheel"), FTransform(FRotator(0.f, 90.f, 0.f), FVector(-23200.f, 4000.f, 0.f)), true, FVector(4.f, 24.f, 26.f), TEXT("E_White"));
}

// ------------------------------------------------------------------------------------------------ airfield

void AGTACity::BuildAirfield()
{
	for (float X = -18000.f; X < 30000.f; X += 2000.f)
		for (float Y = 17300.f; Y < 30000.f; Y += 2000.f)
			Place(TEXT("Environment"), TEXT("SM_Ground_Grass"), FTransform(FRotator::ZeroRotator, FVector(X + 1000.f, Y + 1000.f, 0.f), FVector(2.f, 2.f, 1.f)), true, FVector(10.f, 10.f, 0.15f), TEXT("E_Grass"));
	for (float X = -15000.f; X < 27000.f; X += 2000.f)
		Place(TEXT("Environment"), TEXT("SM_Runway"), FTransform(FRotator::ZeroRotator, FVector(X + 1000.f, 24000.f, 2.f)), true, FVector(20.f, 30.f, 0.17f), TEXT("E_Runway"));
	for (float X = -15000.f; X < 14000.f; X += 2000.f)
		Place(TEXT("Environment"), TEXT("SM_Apron"), FTransform(FRotator::ZeroRotator, FVector(X + 1000.f, 27000.f, 2.f)), true, FVector(20.f, 20.f, 0.17f), TEXT("E_Concrete"));
	Place(TEXT("Environment"), TEXT("SM_Apron"), FTransform(FRotator::ZeroRotator, FVector(3500.f, 18500.f, 2.f), FVector(0.5f, 1.4f, 1.f)), true, FVector(20.f, 20.f, 0.17f), TEXT("E_Concrete"));
	Place(TEXT("Buildings"), TEXT("SM_Bld_Hangar"), FTransform(FRotator(0.f, -90.f, 0.f), FVector(-6000.f, 28400.f, 2.f)), true, FVector(28.f, 30.f, 12.f), TEXT("E_Metal"));
	Place(TEXT("Buildings"), TEXT("SM_Bld_Hangar"), FTransform(FRotator(0.f, -90.f, 0.f), FVector(-10000.f, 28400.f, 2.f)), true, FVector(28.f, 30.f, 12.f), TEXT("E_Metal"));
	Place(TEXT("Buildings"), TEXT("SM_Bld_ControlTower"), FTransform(FRotator(0.f, -90.f, 0.f), FVector(2500.f, 29000.f, 2.f)), true, FVector(8.f, 8.f, 22.f), TEXT("E_Concrete"));
	Place(TEXT("Environment"), TEXT("SM_Helipad"), FTransform(FRotator::ZeroRotator, FVector(12000.f, 28500.f, 4.f)), true, FVector(20.f, 20.f, 0.2f), TEXT("E_ConcreteDark"));
	Place(TEXT("Props"), TEXT("SM_Windsock"), FTransform(FRotator::ZeroRotator, FVector(20000.f, 26500.f, 0.f)), true);
	AircraftSpots.Add(FTransform(FRotator(0.f, 0.f, 0.f), FVector(-6000.f, 26200.f, 20.f)));     // prop plane in front of hangar
	AircraftSpots.Add(FTransform(FRotator(0.f, 0.f, 0.f), FVector(-10000.f, 26200.f, 20.f)));    // jet
	AircraftSpots.Add(FTransform(FRotator(0.f, 0.f, 0.f), FVector(12000.f, 28500.f, 30.f)));     // helipad
	for (float X = -15000.f; X <= 27000.f; X += 3000.f)
	{
		Place(TEXT("Props"), TEXT("SM_RunwayLight"), FTransform(FRotator::ZeroRotator, FVector(X, 22400.f, 2.f)), false);
		Place(TEXT("Props"), TEXT("SM_RunwayLight"), FTransform(FRotator::ZeroRotator, FVector(X, 25600.f, 2.f)), false);
	}
	// perimeter fence along the access road with the gate gap at X=35 m
	for (float X = -18000.f; X < 30000.f; X += 400.f)
	{
		if (FMath::Abs(X + 200.f - 3500.f) < 900.f) continue;
		Place(TEXT("Props"), TEXT("SM_Fence"), FTransform(FRotator::ZeroRotator, FVector(X + 200.f, 17250.f, 15.f)), true, FVector(4.f, 0.1f, 2.f), TEXT("E_MetalDark"));
	}
}

// ------------------------------------------------------------------------------------------------ park

void AGTACity::BuildPark()
{
	const FBox2D P(FVector2D(18300.f, -3200.f), FVector2D(30000.f, 17200.f));
	for (float X = P.Min.X; X < P.Max.X - 10.f; X += 2000.f)
		for (float Y = P.Min.Y; Y < P.Max.Y - 10.f; Y += 2000.f)
		{
			const float SX = FMath::Min(2000.f, P.Max.X - X) / 1000.f, SY = FMath::Min(2000.f, P.Max.Y - Y) / 1000.f;
			Place(TEXT("Environment"), TEXT("SM_Ground_Grass"), FTransform(FRotator::ZeroRotator, FVector(X + SX * 500.f, Y + SY * 500.f, 0.f), FVector(SX, SY, 1.f)), true, FVector(10.f, 10.f, 0.15f), TEXT("E_Grass"));
		}
	Reserved.Add(P);   // keep generic buildings out
	// footpaths
	for (float X = P.Min.X; X < P.Max.X; X += 1000.f)
		Place(TEXT("Environment"), TEXT("SM_Path"), FTransform(FRotator::ZeroRotator, FVector(X + 500.f, 7000.f, 16.f)), false, FVector(10.f, 4.f, 0.03f), TEXT("E_Sidewalk"));
	for (float Y = P.Min.Y; Y < P.Max.Y; Y += 1000.f)
		Place(TEXT("Environment"), TEXT("SM_Path"), FTransform(FRotator(0.f, 90.f, 0.f), FVector(26000.f, Y + 500.f, 16.f)), false, FVector(10.f, 4.f, 0.03f), TEXT("E_Sidewalk"));
	Place(TEXT("Environment"), TEXT("SM_Pond"), FTransform(FRotator::ZeroRotator, FVector(22500.f, 7000.f, 0.f)), true, FVector(36.f, 36.f, 0.2f), TEXT("E_Water"));
	Place(TEXT("Props"), TEXT("SM_Ramp"), FTransform(FRotator(0.f, 0.f, 0.f), FVector(18800.f, 7000.f, 15.f)), true, FVector(8.f, 5.f, 1.8f), TEXT("E_MetalDark"));
	Place(TEXT("Props"), TEXT("SM_Fountain"), FTransform(FRotator::ZeroRotator, FVector(26000.f, 0.f, 15.f)), true, FVector(8.f, 8.f, 2.5f), TEXT("E_Concrete"));
	Place(TEXT("Buildings"), TEXT("SM_Gazebo"), FTransform(FRotator::ZeroRotator, FVector(21000.f, 13500.f, 15.f)), true, FVector(7.f, 7.f, 4.f), TEXT("E_White"));
	FRandomStream R(777);
	int32 Trees = 0;
	for (int32 i = 0; i < 400 && Trees < 90; ++i)
	{
		const FVector L(R.FRandRange(P.Min.X + 300.f, P.Max.X - 300.f), R.FRandRange(P.Min.Y + 300.f, P.Max.Y - 300.f), 15.f);
		if (FMath::Abs(L.Y - 7000.f) < 500.f || FMath::Abs(L.X - 26000.f) < 500.f) continue;
		if (FVector::Dist2D(L, FVector(22500.f, 7000.f, 0.f)) < 2400.f) continue;
		if (FVector::Dist2D(L, FVector(26000.f, 0.f, 0.f)) < 700.f || FVector::Dist2D(L, FVector(21000.f, 13500.f, 0.f)) < 700.f) continue;
		if (L.X < 19800.f && FMath::Abs(L.Y - 7000.f) < 900.f) continue;
		const float Pick = R.FRand();
		const TCHAR* M = Pick < 0.4f ? TEXT("SM_Tree_A") : (Pick < 0.75f ? TEXT("SM_Tree_B") : (Pick < 0.9f ? TEXT("SM_Palm_A") : TEXT("SM_Bush")));
		Place(TEXT("Nature"), M, FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), L, FVector(R.FRandRange(0.85f, 1.2f))), true);
		Trees++;
	}
	for (int32 i = 0; i < 10; ++i)
	{
		const float X = P.Min.X + 1500.f + i * 1100.f;
		Place(TEXT("Props"), TEXT("SM_Bench"), FTransform(FRotator(0.f, 90.f, 0.f), FVector(X, 7000.f - 380.f, 15.f)), true);
		if (i % 2 == 0) StreetLamps.Add(FTransform(FRotator(0.f, -90.f, 0.f), FVector(X, 7000.f + 360.f, 15.f)));
	}
	for (const FTransform& T : StreetLamps) Place(TEXT("Props"), TEXT("SM_StreetLamp"), T, true, FVector(0.3f, 0.3f, 7.f), TEXT("E_MetalDark"));
}

// ------------------------------------------------------------------------------------------------ landmark / service buildings

void AGTACity::PlaceSpecial(EGTAPOI Type, int32 Index, const TCHAR* Mesh, float D, float W, float H, const TCHAR* Mat)
{
	const FGTAPOIData* P = FindPOI(Type, Index);
	if (!P) return;
	const FVector Fwd = P->T.GetRotation().GetForwardVector();
	const FVector C = P->T.GetLocation() + Fwd * (100.f + D * 50.f);
	const float Yaw = P->T.Rotator().Yaw + 180.f;
	Place(TEXT("Buildings"), Mesh, FTransform(FRotator(0.f, Yaw, 0.f), FVector(C.X, C.Y, 15.f)), true, FVector(D, W, H), Mat);
	const bool bRot = FMath::Abs(Fwd.Y) > 0.5f;
	const FVector2D Ext = bRot ? FVector2D(W, D) * 50.f : FVector2D(D, W) * 50.f;
	Reserved.Add(FBox2D(FVector2D(C.X, C.Y) - Ext - FVector2D(150.f), FVector2D(C.X, C.Y) + Ext + FVector2D(150.f)));
}

void AGTACity::BuildSpecials()
{
	PlaceSpecial(EGTAPOI::Safehouse, 0, TEXT("SM_Bld_Safehouse_Beach"), 12, 14, 7, TEXT("E_Plaster1"));
	PlaceSpecial(EGTAPOI::Safehouse, 1, TEXT("SM_Bld_Apartment_B"), 24, 16, 22, TEXT("E_Plaster2"));
	PlaceSpecial(EGTAPOI::Safehouse, 2, TEXT("SM_Bld_House_B"), 11, 14, 8, TEXT("E_Plaster2"));
	PlaceSpecial(EGTAPOI::PoliceStation, -1, TEXT("SM_Bld_PoliceStation"), 22, 32, 12, TEXT("E_Concrete"));
	PlaceSpecial(EGTAPOI::Hospital, -1, TEXT("SM_Bld_Hospital"), 24, 36, 18, TEXT("E_White"));
	PlaceSpecial(EGTAPOI::GasStation, -1, TEXT("SM_Bld_GasStation"), 18, 24, 6, TEXT("E_White"));
	PlaceSpecial(EGTAPOI::ModShop, -1, TEXT("SM_Bld_ModShop"), 18, 26, 9, TEXT("E_Metal"));
	PlaceSpecial(EGTAPOI::GunShop, -1, TEXT("SM_Bld_GunShop"), 12, 14, 7, TEXT("E_ConcreteDark"));
	PlaceSpecial(EGTAPOI::ClothesShop, -1, TEXT("SM_Bld_ClothesShop"), 12, 16, 8, TEXT("E_Plaster2"));
	PlaceSpecial(EGTAPOI::Barber, -1, TEXT("SM_Bld_Barber"), 10, 10, 6, TEXT("E_Plaster1"));
	PlaceSpecial(EGTAPOI::Diner, -1, TEXT("SM_Bld_Diner"), 12, 16, 6, TEXT("E_Plaster3"));
	for (int32 i = 0; i < 3; ++i) PlaceSpecial(EGTAPOI::Garage, i, TEXT("SM_Bld_Garage"), 8, 10, 4, TEXT("E_Concrete"));
	PlaceSpecial(EGTAPOI::ShootingRange, -1, TEXT("SM_Bld_Range"), 30, 20, 6, TEXT("E_ConcreteDark"));
	Place(TEXT("Buildings"), TEXT("SM_Bld_Tower_C"), FTransform(FRotator(0.f, 180.f, 0.f), FVector(7000.f, -300.f, 15.f)), true, FVector(26.f, 26.f, 92.f), TEXT("E_Window"));
	Reserved.Add(FBox2D(FVector2D(5550.f, -1750.f), FVector2D(8450.f, 1150.f)));
	// parking next to services (police cars, ambulance, customer cars)
	ParkingSpots.Add(FTransform(FRotator(0.f, 90.f, 0.f), FVector(-8000.f, -9600.f, 40.f)));
	ParkingSpots.Add(FTransform(FRotator(0.f, 90.f, 0.f), FVector(-7400.f, -9600.f, 40.f)));
	ParkingSpots.Add(FTransform(FRotator(0.f, 90.f, 0.f), FVector(-8000.f, 9400.f, 40.f)));
	// stunt ramps
	for (int32 i = 0; i < 3; ++i)
	{
		const FGTAPOIData* S = FindPOI(EGTAPOI::StuntJump, i);
		if (!S || i == 2) continue;   // park ramp is placed by BuildPark
		Place(TEXT("Props"), TEXT("SM_Ramp"), FTransform(S->T.Rotator(), S->T.GetLocation() + FVector(0, 0, 2.f)), true, FVector(8.f, 5.f, 1.8f), TEXT("E_MetalDark"));
	}
	if (const FGTAPOIData* T = FindPOI(EGTAPOI::TaxiStand)) Place(TEXT("Props"), TEXT("SM_TaxiSign"), FTransform(FRotator::ZeroRotator, T->T.GetLocation() + FVector(0, 0, 15.f)), true);
}

// ------------------------------------------------------------------------------------------------ courtyards

void AGTACity::BuildCourtyard(const FGTABlock& B, const TArray<FBox2D>& Used, FRandomStream& R)
{
	auto Free = [&](const FBox2D& Box)
	{
		if (!B.Rect.IsInside(Box.Min) || !B.Rect.IsInside(Box.Max)) return false;
		if (IsReserved(Box)) return false;
		for (const FBox2D& U : Used) if (U.Intersect(Box)) return false;
		return true;
	};
	TArray<FBox2D> Local;
	auto Try = [&](const FVector2D& C, const FVector2D& Half)
	{
		const FBox2D Box(C - Half, C + Half);
		if (!Free(Box)) return false;
		for (const FBox2D& L : Local) if (L.Intersect(Box)) return false;
		Local.Add(Box);
		return true;
	};
	int32 Parked = 0;
	for (float X = B.Rect.Min.X + 400.f; X < B.Rect.Max.X - 400.f; X += 500.f)
	{
		for (float Y = B.Rect.Min.Y + 400.f; Y < B.Rect.Max.Y - 400.f; Y += 500.f)
		{
			const FVector2D C(X + R.FRandRange(-80.f, 80.f), Y + R.FRandRange(-80.f, 80.f));
			const float Roll = R.FRand();
			switch (B.District)
			{
			case EGTADistrict::Downtown:
				if (Roll < 0.25f && Try(C, FVector2D(150.f)))
					Place(TEXT("Nature"), TEXT("SM_Tree_Planter"), FTransform(FRotator::ZeroRotator, FVector(C.X, C.Y, 15.f)), true, FVector(1.5f, 1.5f, 5.f), TEXT("E_Leaf"));
				else if (Roll < 0.35f && Try(C, FVector2D(110.f)))
					Place(TEXT("Props"), TEXT("SM_Bench"), FTransform(FRotator(0.f, R.RandRange(0, 3) * 90.f, 0.f), FVector(C.X, C.Y, 15.f)), true);
				break;
			case EGTADistrict::Hills:
				if (Roll < 0.3f && Try(C, FVector2D(180.f)))
					Place(TEXT("Nature"), R.FRand() < 0.5f ? TEXT("SM_Tree_A") : TEXT("SM_Palm_A"), FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), FVector(C.X, C.Y, 15.f)), true);
				else if (Roll < 0.5f && Try(C, FVector2D(100.f)))
					Place(TEXT("Nature"), TEXT("SM_Bush"), FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), FVector(C.X, C.Y, 15.f)), false);
				break;
			case EGTADistrict::Harbor:
			case EGTADistrict::Industrial:
				if (Roll < 0.3f && Try(C, FVector2D(650.f, 150.f)))
				{
					const TCHAR* Cn[] = { TEXT("SM_Container_A"), TEXT("SM_Container_B"), TEXT("SM_Container_C") };
					const int32 Stack = B.District == EGTADistrict::Harbor ? R.RandRange(1, 3) : 1;
					for (int32 s = 0; s < Stack; ++s)
						Place(TEXT("Props"), Cn[R.RandRange(0, 2)], FTransform(FRotator(0.f, R.FRand() < 0.5f ? 0.f : 180.f, 0.f), FVector(C.X, C.Y, 15.f + s * 260.f)), true, FVector(12.2f, 2.44f, 2.6f), TEXT("E_Container1"));
				}
				else if (Roll < 0.45f && Try(C, FVector2D(80.f)))
					Place(TEXT("Props"), R.FRand() < 0.5f ? TEXT("SM_Crate") : TEXT("SM_Barrel"), FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), FVector(C.X, C.Y, 15.f)), true);
				else if (Parked < 3 && Roll < 0.65f && Try(C, FVector2D(300.f, 150.f)))
				{
					ParkingSpots.Add(FTransform(FRotator::ZeroRotator, FVector(C.X, C.Y, 60.f)));
					Parked++;
				}
				break;
			case EGTADistrict::NeonRow:
				if (Parked < 4 && Roll < 0.3f && Try(C, FVector2D(300.f, 150.f)))
				{
					ParkingSpots.Add(FTransform(FRotator::ZeroRotator, FVector(C.X, C.Y, 60.f)));
					Parked++;
				}
				else if (Roll < 0.4f && Try(C, FVector2D(120.f, 90.f)))
					Place(TEXT("Props"), TEXT("SM_Dumpster"), FTransform(FRotator(0.f, R.RandRange(0, 3) * 90.f, 0.f), FVector(C.X, C.Y, 15.f)), true);
				else if (Roll < 0.5f && Try(C, FVector2D(160.f)))
					Place(TEXT("Nature"), TEXT("SM_Palm_B"), FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), FVector(C.X, C.Y, 15.f)), true);
				break;
			default: break;
			}
		}
	}
}

// ------------------------------------------------------------------------------------------------ street furniture

void AGTACity::BuildStreetProps()
{
	FRandomStream R(9001);
	for (int32 e = 0; e < Edges.Num(); ++e)
	{
		const FGTARoadEdge& E = Edges[e];
		const FVector A = Nodes[E.A].Pos;
		const FVector Right(-E.Dir.Y, E.Dir.X, 0.f);
		const float Yaw = E.Dir.Rotation().Yaw;
		const EGTADistrict Dist = DistrictAt((A + Nodes[E.B].Pos).X * 0.5f, (A + Nodes[E.B].Pos).Y * 0.5f);
		int32 k = 0;
		for (float D = CorridorHalf + 900.f; D < E.Length - CorridorHalf - 400.f; D += 2800.f, ++k)
		{
			const float Side = (k % 2 == 0) ? 1.f : -1.f;
			const FVector L = A + E.Dir * D + Right * Side * (RoadHalfWidth + 70.f) + FVector(0, 0, 15.f);
			const FTransform T(FRotator(0.f, Yaw + (Side > 0.f ? -90.f : 90.f), 0.f), L);
			StreetLamps.Add(T);
			Place(TEXT("Props"), TEXT("SM_StreetLamp"), T, true, FVector(0.3f, 0.3f, 7.f), TEXT("E_MetalDark"));
		}
		// sidewalk props
		const int32 Count = (Dist == EGTADistrict::Downtown || Dist == EGTADistrict::NeonRow) ? 4 : 2;
		for (int32 i = 0; i < Count; ++i)
		{
			const float D = R.FRandRange(CorridorHalf + 600.f, E.Length - CorridorHalf - 600.f);
			const float Side = R.FRand() < 0.5f ? 1.f : -1.f;
			const FVector L = A + E.Dir * D + Right * Side * (RoadHalfWidth + 230.f) + FVector(0, 0, 15.f);
			const float FaceRoad = Yaw + (Side > 0.f ? -90.f : 90.f);
			const float Pick = R.FRand();
			const TCHAR* M = Pick < 0.3f ? TEXT("SM_Bench") : (Pick < 0.55f ? TEXT("SM_TrashBin") : (Pick < 0.7f ? TEXT("SM_Hydrant") : (Pick < 0.82f ? TEXT("SM_Vending") : (Pick < 0.92f ? TEXT("SM_NewsBox") : TEXT("SM_ATM")))));
			Place(TEXT("Props"), M, FTransform(FRotator(0.f, FaceRoad + 180.f, 0.f), L), true);
		}
		// trees on hills streets, palms along the beach road
		if (Dist == EGTADistrict::Hills || FMath::Abs(A.X - (-17500.f)) < 10.f && FMath::Abs(E.Dir.Y) > 0.9f)
		{
			for (float D = CorridorHalf + 1500.f; D < E.Length - CorridorHalf - 600.f; D += 2200.f)
			{
				const FVector L = A + E.Dir * D - Right * (RoadHalfWidth + 220.f) + FVector(0, 0, 15.f);
				Place(TEXT("Nature"), Dist == EGTADistrict::Hills ? TEXT("SM_Tree_A") : TEXT("SM_Palm_A"), FTransform(FRotator(0.f, R.FRandRange(0.f, 360.f), 0.f), L), true);
			}
		}
		// bus stop on every fourth edge
		if (e % 4 == 1 && E.Length > 4000.f)
		{
			const FVector L = A + E.Dir * (E.Length * 0.5f) + Right * (RoadHalfWidth + 220.f) + FVector(0, 0, 15.f);
			Place(TEXT("Props"), TEXT("SM_BusStop"), FTransform(FRotator(0.f, Yaw - 90.f + 180.f, 0.f), L), true, FVector(1.6f, 4.f, 2.6f), TEXT("E_Teal"));
		}
	}
	// traffic signals: one pole per approach at the far-right corner
	UStaticMesh* Sphere = FGTAAssets::Sphere();
	if (Sphere)
	{
		SignalRed = NewObject<UInstancedStaticMeshComponent>(this, NAME_None, RF_Transient);
		SignalGreen = NewObject<UInstancedStaticMeshComponent>(this, NAME_None, RF_Transient);
		for (UInstancedStaticMeshComponent* S : { SignalRed.Get(), SignalGreen.Get() })
		{
			S->SetStaticMesh(Sphere);
			S->SetMobility(EComponentMobility::Movable);
			S->SetCollisionEnabled(ECollisionEnabled::NoCollision);
			S->SetCastShadow(false);
			S->SetupAttachment(RootComponent);
			S->ComponentTags.Add(TEXT("GTACity"));
			S->RegisterComponent();
			AddInstanceComponent(S);
		}
		if (UMaterialInterface* MR = FGTAAssets::Material(TEXT("E_TrafficR"))) SignalRed->SetMaterial(0, MR);
		if (UMaterialInterface* MG = FGTAAssets::Material(TEXT("E_TrafficG"))) SignalGreen->SetMaterial(0, MG);
	}
	SignalPoles.Reset();
	for (int32 n = 0; n < Nodes.Num(); ++n)
	{
		if (!Nodes[n].bSignal) continue;
		for (const FVector& Dir : { FVector(1, 0, 0), FVector(-1, 0, 0), FVector(0, 1, 0), FVector(0, -1, 0) })
		{
			const FVector Right(-Dir.Y, Dir.X, 0.f);
			const FVector L = Nodes[n].Pos + Dir * (RoadHalfWidth + 90.f) + Right * (RoadHalfWidth + 90.f) + FVector(0, 0, 15.f);
			const FTransform T(FRotator(0.f, Dir.Rotation().Yaw, 0.f), L);
			Place(TEXT("Props"), TEXT("SM_TrafficLight"), T, true, FVector(0.3f, 0.3f, 6.f), TEXT("E_MetalDark"));
			FGTASignalPole P;
			P.Node = n;
			P.Dir = Dir;
			P.Red = FTransform(FQuat::Identity, T.TransformPosition(FVector(-28.f, -380.f, 640.f)), FVector(0.22f));
			P.Green = FTransform(FQuat::Identity, T.TransformPosition(FVector(-28.f, -380.f, 560.f)), FVector(0.22f));
			SignalPoles.Add(P);
			if (SignalRed) { SignalRed->AddInstance(P.Red, true); SignalGreen->AddInstance(P.Green, true); }
		}
	}
}

void AGTACity::TickSignals()
{
	if (!SignalRed || !SignalGreen || SignalRed->GetInstanceCount() != SignalPoles.Num()) return;
	for (int32 i = 0; i < SignalPoles.Num(); ++i)
	{
		const FGTASignalPole& P = SignalPoles[i];
		const bool bGreen = SignalGreenFor(P.Node, P.Dir);
		FTransform R = P.Red, G = P.Green;
		if (bGreen) R.SetScale3D(FVector::ZeroVector); else G.SetScale3D(FVector::ZeroVector);
		SignalRed->UpdateInstanceTransform(i, R, true, false, true);
		SignalGreen->UpdateInstanceTransform(i, G, true, false, true);
	}
	SignalRed->MarkRenderStateDirty();
	SignalGreen->MarkRenderStateDirty();
}

void AGTACity::TickLamps()
{
	TickSignals();
	UWorld* W = GetWorld();
	if (!W || !W->IsGameWorld()) return;
	if (LampLights.Num() == 0)
	{
		for (int32 i = 0; i < 16; ++i)
		{
			UPointLightComponent* L = NewObject<UPointLightComponent>(this, NAME_None, RF_Transient);
			L->SetupAttachment(RootComponent);
			L->SetMobility(EComponentMobility::Movable);
			L->SetIntensityUnits(ELightUnits::Candelas);
			L->SetIntensity(180.f);
			L->SetAttenuationRadius(1800.f);
			L->SetLightColor(FLinearColor(1.f, 0.78f, 0.5f));
			L->SetCastShadows(false);
			L->SetVisibility(false);
			L->RegisterComponent();
			LampLights.Add(L);
		}
	}
	bool bNight = false;
	if (AGTAGameMode* M = GTA::Mode(this)) { if (M->Env) bNight = M->Env->NightFactor() > 0.3f; }
	APlayerCameraManager* PCM = UGameplayStatics::GetPlayerCameraManager(this, 0);
	if (!bNight || !PCM)
	{
		for (UPointLightComponent* L : LampLights) if (L->IsVisible()) L->SetVisibility(false);
		return;
	}
	const FVector Cam = PCM->GetCameraLocation();
	TArray<TPair<float, int32>> Near;
	for (int32 i = 0; i < StreetLamps.Num(); ++i)
	{
		const float D = FVector::DistSquared(StreetLamps[i].GetLocation(), Cam);
		if (D < 7000.f * 7000.f) Near.Add({ D, i });
	}
	Near.Sort([](const TPair<float, int32>& A, const TPair<float, int32>& B) { return A.Key < B.Key; });
	for (int32 i = 0; i < LampLights.Num(); ++i)
	{
		if (i < Near.Num())
		{
			const FTransform& T = StreetLamps[Near[i].Value];
			LampLights[i]->SetWorldLocation(T.TransformPosition(FVector(160.f, 0.f, 700.f)));
			LampLights[i]->SetVisibility(true);
		}
		else LampLights[i]->SetVisibility(false);
	}
}

#include "Vehicles/GTAVehicle.h"
#include "Core/GTAGame.h"
#include "Player/GTACharacter.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/AudioComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/PlayerController.h"
#include "Camera/CameraComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInstanceDynamic.h"

AGTAVehicle::AGTAVehicle()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickGroup = TG_PrePhysics;

	Body = CreateDefaultSubobject<UBoxComponent>(TEXT("Body"));
	RootComponent = Body;
	Body->SetBoxExtent(FVector(230.f, 90.f, 50.f));
	Body->SetCollisionProfileName(TEXT("Vehicle"));
	Body->SetCollisionResponseToChannel(GTA_ECC_WEAPON, ECR_Ignore);
	Body->SetNotifyRigidBodyCollision(true);
	Body->BodyInstance.bUseCCD = true;
	Body->SetCanEverAffectNavigation(false);

	BodyMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("BodyMesh"));
	BodyMesh->SetupAttachment(Body);
	BodyMesh->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	BodyMesh->SetCollisionResponseToAllChannels(ECR_Ignore);
	BodyMesh->SetCollisionResponseToChannel(GTA_ECC_WEAPON, ECR_Block);
	BodyMesh->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
	BodyMesh->SetCanEverAffectNavigation(false);

	CamBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CamBoom"));
	CamBoom->SetupAttachment(Body);
	CamBoom->TargetArmLength = 700.f;
	CamBoom->bUsePawnControlRotation = true;
	CamBoom->bEnableCameraLag = true;
	CamBoom->CameraLagSpeed = 9.f;
	CamBoom->bInheritRoll = false;
	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(CamBoom, USpringArmComponent::SocketName);
	Camera->FieldOfView = 85.f;

	auto MakeAudio = [this](const TCHAR* Name)
	{
		UAudioComponent* A = CreateDefaultSubobject<UAudioComponent>(Name);
		A->SetupAttachment(Body);
		A->bAutoActivate = false;
		return A;
	};
	EngineAudio = MakeAudio(TEXT("EngineAudio"));
	SirenAudio = MakeAudio(TEXT("SirenAudio"));
	HornAudio = MakeAudio(TEXT("HornAudio"));
	RadioAudio = MakeAudio(TEXT("RadioAudio"));
	SkidAudio = MakeAudio(TEXT("SkidAudio"));
	AutoPossessAI = EAutoPossessAI::Disabled;
}

AGTAVehicle* AGTAVehicle::SpawnVehicle(UWorld* World, EGTAVehicle Id, const FTransform& T, const FGTAVehicleMods* InMods)
{
	if (!World) return nullptr;
	FTransform SpawnT = T;
	const FGTAVehicleDef& Def = FGTAData::Vehicle(Id);
	if (Def.Kind == EGTAVehicleKind::Plane || Def.Kind == EGTAVehicleKind::Helicopter)
	{
		FCollisionObjectQueryParams Objects;
		Objects.AddObjectTypesToQuery(ECC_Vehicle);
		const FCollisionShape Box = FCollisionShape::MakeBox(FVector(Def.Length*55.f,Def.Width*55.f,Def.Height*60.f));
		bool Clear = false;
		for (int32 I=0;I<5;++I)
		{
			const FVector L=T.GetLocation()+T.GetRotation().GetForwardVector()*(I*(Def.Length*110.f+250.f));
			if (!World->OverlapAnyTestByObjectType(L+FVector(0,0,Def.Height*50.f),T.GetRotation(),Objects,Box))
			{
				SpawnT.SetLocation(L); Clear=true; break;
			}
		}
		if (!Clear) return nullptr;
	}
	AGTAVehicle* V = World->SpawnActorDeferred<AGTAVehicle>(AGTAVehicle::StaticClass(), SpawnT, nullptr, nullptr, ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
	if (!V) return nullptr;
	V->VehicleId = Id;
	if (InMods) V->Mods = *InMods;
	else
	{
		V->Mods.Primary = FGTAData::Vehicle(Id).DefaultPaint;
		V->Mods.Secondary = FLinearColor(0.85f, 0.85f, 0.85f);
	}
	UGameplayStatics::FinishSpawningActor(V, SpawnT);
	return V;
}

void AGTAVehicle::BeginPlay()
{
	Super::BeginPlay();
	InitVehicle(VehicleId);
	Body->OnComponentHit.AddDynamic(this, &AGTAVehicle::OnBodyHit);
}

void AGTAVehicle::InitVehicle(EGTAVehicle Id)
{
	VehicleId = Id;
	const FGTAVehicleDef& D = GetDef();
	const EGTAVehicleKind K = D.Kind;
	const float L = D.Length * 100.f, W = D.Width * 100.f, H = D.Height * 100.f, R = D.WheelRadius * 100.f;
	float Bottom = R * 0.85f, Top = H, HalfX = L * 0.48f, HalfY = W * 0.46f, CenterX = 0.f;
	switch (K)
	{
	case EGTAVehicleKind::Motorcycle:
	case EGTAVehicleKind::Bicycle: Bottom = R * 0.9f; HalfY = 22.f; break;
	case EGTAVehicleKind::Boat: Bottom = 5.f; Top = H * 0.75f; break;
	case EGTAVehicleKind::Helicopter: Bottom = 45.f; Top = 260.f; HalfY = 80.f; HalfX = L * 0.24f; CenterX = L * 0.14f; break;
	case EGTAVehicleKind::Plane:
		Bottom = Id == EGTAVehicle::Jet ? 95.f : 70.f; Top = Id == EGTAVehicle::Jet ? 270.f : 200.f;
		HalfY = Id == EGTAVehicle::Jet ? 85.f : 65.f; HalfX = L * 0.46f; break;
	default: break;
	}
	BodyCenterZ = (Top + Bottom) * 0.5f;
	MeshOffset = FVector(-CenterX, 0.f, -BodyCenterZ);
	Body->SetBoxExtent(FVector(HalfX, HalfY, (Top - Bottom) * 0.5f));
	Health = D.Health;

	UStaticMesh* SM = FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Veh_") + D.Key);
	if (!SM) { SM = FGTAAssets::Cube(); BodyMesh->SetRelativeScale3D(FVector(HalfX / 50.f, HalfY / 50.f, (Top - Bottom) / 100.f)); BodyMesh->SetRelativeLocation(FVector::ZeroVector); }
	else BodyMesh->SetRelativeLocation(MeshOffset);
	BodyMesh->SetStaticMesh(SM);
	BodyMIDs.Reset();
	for (int32 i = 0; i < BodyMesh->GetNumMaterials(); ++i) BodyMIDs.Add(BodyMesh->CreateDynamicMaterialInstance(i));

	// wheels / landing gear
	Wheels.Reset();
	auto AddWheel = [&](float X, float Y, float Rad, bool bSteer, bool bDrive, bool bVisual)
	{
		FGTAWheel Wh;
		Wh.Local = FVector(X, Y, Rad) + MeshOffset;
		Wh.Radius = Rad;
		Wh.bSteer = bSteer;
		Wh.bDrive = bDrive;
		Wh.bRight = Y > 1.f;
		if (bVisual)
		{
			Wh.Mesh = NewObject<UStaticMeshComponent>(this);
			Wh.Mesh->SetupAttachment(Body);
			Wh.Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
			Wh.Mesh->RegisterComponent();
			Wh.Rim = NewObject<UStaticMeshComponent>(this);
			Wh.Rim->SetupAttachment(Wh.Mesh);
			Wh.Rim->SetCollisionEnabled(ECollisionEnabled::NoCollision);
			Wh.Rim->RegisterComponent();
		}
		Wheels.Add(Wh);
	};
	if (K == EGTAVehicleKind::Car)
	{
		const bool bFWD = Id == EGTAVehicle::Compact || Id == EGTAVehicle::Sedan || Id == EGTAVehicle::Taxi || Id == EGTAVehicle::Van || Id == EGTAVehicle::Ambulance;
		const bool bAWD = Id == EGTAVehicle::SUV || Id == EGTAVehicle::Pickup || Id == EGTAVehicle::Tactical;
		const float FX = D.Wheelbase * 50.f, TY = D.Track * 50.f;
		AddWheel(FX, -TY, R, true, bFWD || bAWD, true);
		AddWheel(FX, TY, R, true, bFWD || bAWD, true);
		AddWheel(-FX, -TY, R, false, !bFWD || bAWD, true);
		AddWheel(-FX, TY, R, false, !bFWD || bAWD, true);
	}
	else if (K == EGTAVehicleKind::Motorcycle || K == EGTAVehicleKind::Bicycle)
	{
		AddWheel(D.Wheelbase * 50.f, 0.f, R, true, false, true);
		AddWheel(-D.Wheelbase * 50.f, 0.f, R, false, true, true);
	}
	else if (K == EGTAVehicleKind::Plane)
	{
		const float GR = Id == EGTAVehicle::Jet ? 38.f : 30.f;
		AddWheel(L * 0.33f, 0.f, GR, true, false, true);
		AddWheel(-L * 0.03f, -(Id == EGTAVehicle::Jet ? 170.f : 130.f), GR, false, false, true);
		AddWheel(-L * 0.03f, (Id == EGTAVehicle::Jet ? 170.f : 130.f), GR, false, false, true);
	}
	else if (K == EGTAVehicleKind::Helicopter)
	{
		for (float X : { L * 0.24f, -L * 0.02f }) for (float Y : { -85.f, 85.f }) AddWheel(X, Y, 12.f, false, false, false);
	}

	// rotors
	if (K == EGTAVehicleKind::Helicopter)
	{
		RotorMesh = NewObject<UStaticMeshComponent>(this);
		RotorMesh->SetupAttachment(BodyMesh);
		RotorMesh->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Veh_Rotor")));
		RotorMesh->SetRelativeLocation(FVector(L * 0.14f, 0.f, 300.f));
		RotorMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		RotorMesh->RegisterComponent();
		TailRotorMesh = NewObject<UStaticMeshComponent>(this);
		TailRotorMesh->SetupAttachment(BodyMesh);
		TailRotorMesh->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Veh_TailRotor")));
		TailRotorMesh->SetRelativeLocation(FVector(-L * 0.47f, 22.f, 200.f));
		TailRotorMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		TailRotorMesh->RegisterComponent();
	}
	else if (Id == EGTAVehicle::PropPlane)
	{
		RotorMesh = NewObject<UStaticMeshComponent>(this);
		RotorMesh->SetupAttachment(BodyMesh);
		RotorMesh->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Veh_Propeller")));
		RotorMesh->SetRelativeLocation(FVector(L * 0.5f + 5.f, 0.f, 135.f));
		RotorMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		RotorMesh->RegisterComponent();
	}

	// physics
	Body->SetMassOverrideInKg(NAME_None, D.MassKg, true);
	switch (K)
	{
	case EGTAVehicleKind::Boat: Body->SetLinearDamping(0.1f); Body->SetAngularDamping(1.5f); break;
	case EGTAVehicleKind::Helicopter: Body->SetLinearDamping(0.05f); Body->SetAngularDamping(2.5f); break;
	case EGTAVehicleKind::Plane: Body->SetLinearDamping(0.01f); Body->SetAngularDamping(1.2f); break;
	default: Body->SetLinearDamping(0.02f); Body->SetAngularDamping(0.8f); break;
	}
	const float HalfZ = (Top - Bottom) * 0.5f;
	Body->SetCenterOfMass(FVector(0.f, 0.f, K == EGTAVehicleKind::Car ? -HalfZ * 0.75f : -HalfZ * 0.4f));
	Body->SetSimulatePhysics(true);
	AddActorWorldOffset(FVector(0.f, 0.f, BodyCenterZ + 8.f), false, nullptr, ETeleportType::TeleportPhysics);

	// camera
	float Arm = FMath::Clamp(L * 1.35f, 520.f, 1300.f);
	if (K == EGTAVehicleKind::Helicopter) Arm = 1500.f;
	else if (K == EGTAVehicleKind::Plane) Arm = Id == EGTAVehicle::Jet ? 2300.f : 1700.f;
	else if (K == EGTAVehicleKind::Boat) Arm = 1050.f;
	CamBoom->TargetArmLength = Arm;
	CamBoom->SetRelativeLocation(FVector(0.f, 0.f, H * 0.35f));
	CamBoom->SocketOffset = FVector(0.f, 0.f, FMath::Max(80.f, H * 0.45f));

	// audio
	FString Engine = TEXT("S_Engine_Car");
	if (Id == EGTAVehicle::BoxTruck || Id == EGTAVehicle::FireTruck || Id == EGTAVehicle::Tactical) Engine = TEXT("S_Engine_Truck");
	else if (K == EGTAVehicleKind::Motorcycle) Engine = TEXT("S_Engine_Bike");
	else if (K == EGTAVehicleKind::Boat) Engine = TEXT("S_Engine_Boat");
	else if (K == EGTAVehicleKind::Helicopter) Engine = TEXT("S_Rotor");
	else if (Id == EGTAVehicle::PropPlane) Engine = TEXT("S_Engine_Prop");
	else if (Id == EGTAVehicle::Jet) Engine = TEXT("S_Engine_Jet");
	else if (K == EGTAVehicleKind::Bicycle) Engine = TEXT("");
	if (!Engine.IsEmpty()) EngineAudio->SetSound(FGTAAssets::Sound(Engine));
	SirenAudio->SetSound(FGTAAssets::Sound(TEXT("S_Siren")));
	HornAudio->SetSound(FGTAAssets::Sound(TEXT("S_Horn")));
	SkidAudio->SetSound(FGTAAssets::Sound(TEXT("S_Skid")));
	Occupants.SetNum(NumSeats());
	SetupLights();
	ApplyMods();
	bEngineOn = !IsAircraft();
}

void AGTAVehicle::SetupLights()
{
	const FGTAVehicleDef& D = GetDef();
	const EGTAVehicleKind K = D.Kind;
	if (K == EGTAVehicleKind::Bicycle) return;
	const float L = D.Length, W = D.Width, H = D.Height;
	const float LightZ = K == EGTAVehicleKind::Car ? FMath::Clamp(H * 0.45f, 0.6f, 1.2f) : 0.9f;
	auto MakeSpot = [this](const FVector& Loc, float Intensity)
	{
		USpotLightComponent* S = NewObject<USpotLightComponent>(this);
		S->SetupAttachment(BodyMesh);
		S->SetRelativeLocationAndRotation(Loc, FRotator(-7.f, 0.f, 0.f));
		S->Intensity = Intensity;
		S->AttenuationRadius = 4500.f;
		S->OuterConeAngle = 38.f;
		S->InnerConeAngle = 18.f;
		S->LightColor = FColor(255, 240, 215);
		S->SetCastShadows(false);
		S->SetVisibility(false);
		S->RegisterComponent();
		return S;
	};
	if (K == EGTAVehicleKind::Car || K == EGTAVehicleKind::Motorcycle || K == EGTAVehicleKind::Boat || IsAircraft())
	{
		const float FrontX = K == EGTAVehicleKind::Helicopter ? L * 0.4f : L * 0.5f;
		HeadL = MakeSpot(FVector(FrontX * 100.f, -(K == EGTAVehicleKind::Motorcycle ? 0.f : W * 0.34f * 100.f), LightZ * 100.f), 9000.f);
		if (K == EGTAVehicleKind::Car) HeadR = MakeSpot(FVector(FrontX * 100.f, W * 0.34f * 100.f, LightZ * 100.f), 9000.f);
		TailGlow = NewObject<UPointLightComponent>(this);
		TailGlow->SetupAttachment(BodyMesh);
		TailGlow->SetRelativeLocation(FVector(-L * 52.f, 0.f, LightZ * 100.f));
		TailGlow->LightColor = FColor(255, 20, 10);
		TailGlow->Intensity = 0.f;
		TailGlow->AttenuationRadius = 300.f;
		TailGlow->SetCastShadows(false);
		TailGlow->RegisterComponent();
	}
	if (D.bEmergency && K == EGTAVehicleKind::Car)
	{
		const float RoofX = (D.Id == EGTAVehicle::Ambulance || D.Id == EGTAVehicle::FireTruck) ? L * 0.38f : -L * 0.04f;
		auto MakeSiren = [this](const FVector& Loc, FColor C)
		{
			UPointLightComponent* P = NewObject<UPointLightComponent>(this);
			P->SetupAttachment(BodyMesh);
			P->SetRelativeLocation(Loc);
			P->LightColor = C;
			P->Intensity = 0.f;
			P->AttenuationRadius = 1500.f;
			P->SetCastShadows(false);
			P->RegisterComponent();
			return P;
		};
		SirenRed = MakeSiren(FVector(RoofX * 100.f, -40.f, H * 100.f + 15.f), FColor(255, 20, 10));
		SirenBlue = MakeSiren(FVector(RoofX * 100.f, 40.f, H * 100.f + 15.f), FColor(20, 60, 255));
	}
	if (VehicleId == EGTAVehicle::PoliceHeli)
	{
		Searchlight = NewObject<USpotLightComponent>(this);
		Searchlight->SetupAttachment(BodyMesh);
		Searchlight->SetRelativeLocationAndRotation(FVector(L * 40.f, 0.f, 60.f), FRotator(-60.f, 0.f, 0.f));
		Searchlight->Intensity = 400000.f;
		Searchlight->AttenuationRadius = 9000.f;
		Searchlight->OuterConeAngle = 9.f;
		Searchlight->InnerConeAngle = 4.f;
		Searchlight->SetCastShadows(false);
		Searchlight->SetVisibility(false);
		Searchlight->RegisterComponent();
	}
}

// ------------------------------------------------------------------------------------------------ seats

int32 AGTAVehicle::FreeSeat(bool bDriverFirst) const
{
	if (bDriverFirst && (!Occupants.IsValidIndex(0) || !Occupants[0])) return 0;
	for (int32 i = bDriverFirst ? 0 : 1; i < NumSeats(); ++i)
	{
		if (!Occupants.IsValidIndex(i) || !Occupants[i]) return i;
	}
	return -1;
}

bool AGTAVehicle::AddOccupant(AGTACharacter* C, int32 Seat)
{
	if (!C || Seat < 0 || Seat >= NumSeats()) return false;
	if (Occupants.Num() < NumSeats()) Occupants.SetNum(NumSeats());
	if (Occupants[Seat] && Occupants[Seat] != C) return false;
	Occupants[Seat] = C;
	C->SitInVehicle(this, Seat);
	return true;
}

void AGTAVehicle::RemoveOccupant(AGTACharacter* C)
{
	for (int32 i = 0; i < Occupants.Num(); ++i)
	{
		if (Occupants[i] == C) Occupants[i] = nullptr;
	}
	if (!GetDriver()) ClearInputs();
}

FTransform AGTAVehicle::GetSeatTransform(int32 Seat) const
{
	const FGTAVehicleDef& D = GetDef();
	float X = D.SeatX, Y = 0.f;
	if (D.Kind == EGTAVehicleKind::Car)
	{
		Y = (Seat % 2 == 0) ? -D.Width * 0.22f : D.Width * 0.22f;
		if (Seat >= 2) X -= 0.95f;
	}
	else if (D.Kind == EGTAVehicleKind::Motorcycle && Seat == 1) X -= 0.45f;
	else if (D.Kind == EGTAVehicleKind::Boat) { Y = (Seat % 2 == 0) ? -0.45f : 0.45f; if (Seat >= 2) X -= 1.3f; }
	else if (D.Kind == EGTAVehicleKind::Helicopter) { Y = (Seat % 2 == 0) ? -0.4f : 0.4f; if (Seat >= 2) X -= 1.1f; }
	else if (D.Kind == EGTAVehicleKind::Plane && Seat >= 1) X -= 1.0f;
	// The authored driving/riding clips retain the pelvis at ~0.98 m above their root.
	// Align that pelvis with the physical seat; the old 0.48 m assumption put torsos through roofs.
	return FTransform(FRotator::ZeroRotator, FVector(X * 100.f, Y * 100.f, (D.SeatZ - 0.98f) * 100.f + 92.f));
}

FVector AGTAVehicle::GetDoorLocation(int32 Seat) const
{
	const FGTAVehicleDef& D = GetDef();
	const FVector SeatLocal = GetSeatTransform(Seat).GetLocation() + MeshOffset;   // actor space
	const float Side = (Seat % 2 == 0) ? -1.f : 1.f;
	const float SideOff = IsTwoWheeler() ? 75.f : D.Width * 50.f + 70.f;
	return GetActorTransform().TransformPosition(FVector(SeatLocal.X, Side * SideOff, -BodyCenterZ + 95.f));
}

FVector AGTAVehicle::GetExitLocation(int32 Seat) const
{
	const FGTAVehicleDef& D = GetDef();
	const FCollisionShape Cap = FCollisionShape::MakeCapsule(34.f, 90.f);
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAExit), false, this);
	for (AGTACharacter* C : Occupants) if (C) Q.AddIgnoredActor(C);
	TArray<FVector> Candidates;
	const FVector Up = FVector::UpVector;
	const float BaseZ = GetActorLocation().Z - BodyCenterZ + 95.f;
	for (int32 Side : { (Seat % 2 == 0) ? -1 : 1, (Seat % 2 == 0) ? 1 : -1 })
	{
		const FVector P = GetActorLocation() + GetActorRightVector() * Side * (D.Width * 50.f + 75.f);
		Candidates.Add(FVector(P.X, P.Y, BaseZ));
	}
	Candidates.Add(GetActorLocation() - GetActorForwardVector() * (D.Length * 50.f + 90.f) + Up * 20.f);
	Candidates.Add(GetActorLocation() + GetActorForwardVector() * (D.Length * 50.f + 90.f) + Up * 20.f);
	Candidates.Add(GetActorLocation() + Up * (D.Height * 100.f + 120.f));
	for (const FVector& P : Candidates)
	{
		if (!GetWorld()->OverlapAnyTestByChannel(P, FQuat::Identity, ECC_Pawn, Cap, Q)) return P;
	}
	return Candidates.Last();
}

void AGTAVehicle::ClearInputs()
{
	Throttle = Steer = PitchInput = YawInput = LiftInput = 0.f;
	bHandbrake = false;
	bBoost = false;
	bHornHeld = false;
}

// ------------------------------------------------------------------------------------------------ toggles

void AGTAVehicle::ToggleLights()
{
	bLightsOn = !bLightsOn;
	if (!bLightsOn) bHighBeams = false;
	GTA::Play3D(this, TEXT("S_Click"), GetActorLocation(), 0.5f);
}

void AGTAVehicle::ToggleSiren()
{
	if (!GetDef().bEmergency) return;
	bSirenOn = !bSirenOn;
	if (bSirenOn) SirenAudio->Play();
	else SirenAudio->Stop();
}

void AGTAVehicle::SetHorn(bool b)
{
	bHornHeld = b;
	if (b && !HornAudio->IsPlaying())
	{
		static const float HornPitch[] = { 1.f, 0.75f, 1.35f, 0.55f };
		HornAudio->SetPitchMultiplier(HornPitch[FMath::Clamp(Mods.Horn, 0, 3)] * (IsTwoWheeler() ? 1.4f : 1.f));
		HornAudio->Play();
		GTA::MakeNoise(this, GetActorLocation(), 2500.f, GetDriver(), false);
	}
	else if (!b) HornAudio->Stop();
}

void AGTAVehicle::ToggleRoof()
{
	if (!GetDef().bConvertible) return;
	bRoofOpen = !bRoofOpen;
	Mods.Roof = bRoofOpen ? 2 : 0;
	ApplyMods();
}

FString AGTAVehicle::StationName(int32 Station)
{
	static const TCHAR* N[] = { TEXT("Radio Off"), TEXT("Tide FM"), TEXT("Neon Pulse"), TEXT("Harbor Lo-Fi"), TEXT("Ironworks Rock") };
	return N[FMath::Clamp(Station, 0, 4)];
}

void AGTAVehicle::CycleRadio(int32 Dir)
{
	RadioStation = (RadioStation + Dir + 5) % 5;
	if (RadioStation == 0) { RadioAudio->Stop(); }
	else
	{
		RadioAudio->SetSound(FGTAAssets::Sound(FString::Printf(TEXT("S_Radio_%d"), RadioStation)));
		RadioAudio->SetVolumeMultiplier(0.55f);
		RadioAudio->Play();
	}
	GTA::Notify(this, StationName(RadioStation), 2.f);
}

// ------------------------------------------------------------------------------------------------ customization

float AGTAVehicle::GetPowerMult() const
{
	float P = 1.f + 0.12f * Mods.Engine + (Mods.bTurbo ? 0.16f : 0.f);
	const float HealthFrac = Health / FMath::Max(1.f, GetDef().Health);
	if (HealthFrac < 0.3f) P *= 0.65f;
	if (bBoost) P *= 1.35f;
	return P;
}

float AGTAVehicle::GetArmorMult() const
{
	return FMath::Max(0.3f, 1.f - 0.15f * Mods.Armor) * (GetDef().bArmored ? 0.45f : 1.f);
}

void AGTAVehicle::SetPaintParam(FName Slot, FName Param, const FLinearColor& C)
{
	const int32 Idx = BodyMesh->GetMaterialIndex(Slot);
	if (BodyMIDs.IsValidIndex(Idx) && BodyMIDs[Idx]) BodyMIDs[Idx]->SetVectorParameterValue(Param, C);
}

void AGTAVehicle::SetScalarOnSlot(FName Slot, FName Param, float V)
{
	const int32 Idx = BodyMesh->GetMaterialIndex(Slot);
	if (BodyMIDs.IsValidIndex(Idx) && BodyMIDs[Idx]) BodyMIDs[Idx]->SetScalarParameterValue(Param, V);
}

UStaticMeshComponent* AGTAVehicle::AddPart(const FString& MeshName, const FVector& Loc, const FRotator& Rot, const FVector& Scale)
{
	UStaticMesh* SM = FGTAAssets::GenMesh(TEXT("Vehicles/Parts"), MeshName);
	if (!SM) return nullptr;
	UStaticMeshComponent* C = NewObject<UStaticMeshComponent>(this);
	C->SetupAttachment(BodyMesh);
	C->SetStaticMesh(SM);
	C->SetRelativeLocationAndRotation(Loc, Rot);
	C->SetRelativeScale3D(Scale);
	C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	C->RegisterComponent();
	PartMeshes.Add(C);
	UMaterialInstanceDynamic* MID = C->CreateDynamicMaterialInstance(0);
	if (MID) MID->SetVectorParameterValue(TEXT("Color"), Mods.Primary);
	return C;
}

void AGTAVehicle::ApplyMods()
{
	const FGTAVehicleDef& D = GetDef();
	if (bDestroyed) return;
	static const float FinishRough[] = { 0.22f, 0.3f, 0.75f, 0.05f };
	static const float FinishMetal[] = { 0.4f, 0.85f, 0.0f, 1.0f };
	const int32 F = FMath::Clamp(Mods.Finish, 0, 3);
	const FLinearColor Prim = F == 3 ? FLinearColor(0.85f, 0.85f, 0.88f) * Mods.Primary.GetLuminance() + Mods.Primary * 0.4f : Mods.Primary;
	SetPaintParam(TEXT("V_Paint"), TEXT("Color"), Prim);
	SetScalarOnSlot(TEXT("V_Paint"), TEXT("Roughness"), FinishRough[F]);
	SetScalarOnSlot(TEXT("V_Paint"), TEXT("Metallic"), FinishMetal[F]);
	SetPaintParam(TEXT("V_Paint2"), TEXT("Color"), Mods.Livery == 2 ? Mods.Secondary : (Mods.Livery == 1 ? Mods.Secondary : Prim));
	SetScalarOnSlot(TEXT("V_Paint2"), TEXT("Roughness"), FinishRough[F]);
	static const float Tint[] = { 0.04f, 0.02f, 0.008f, 0.002f };
	const float T = Tint[FMath::Clamp(Mods.WindowTint, 0, 3)];
	SetPaintParam(TEXT("V_Glass"), TEXT("Color"), FLinearColor(T, T * 1.3f, T * 1.6f));
	static const FColor LightCol[] = { FColor(255, 240, 215), FColor(170, 205, 255), FColor(255, 190, 90) };
	const FColor LC = LightCol[FMath::Clamp(Mods.LightColor, 0, 2)];
	if (HeadL) HeadL->SetLightColor(LC);
	if (HeadR) HeadR->SetLightColor(LC);
	SetPaintParam(TEXT("V_HeadLight"), TEXT("EmissiveColor"), FLinearColor(LC));

	// wheels: tire per vehicle class, rim style customizable
	static const TCHAR* Rims[] = { TEXT("A"), TEXT("B"), TEXT("C"), TEXT("D"), TEXT("E") };
	FString RimDefault = TEXT("A");
	if (D.Wheel == TEXT("Sport")) RimDefault = TEXT("B");
	else if (D.Wheel == TEXT("Offroad")) RimDefault = TEXT("C");
	else if (D.Wheel == TEXT("Truck")) RimDefault = TEXT("D");
	else if (D.Wheel == TEXT("Bike")) RimDefault = TEXT("Bike");
	else if (D.Wheel == TEXT("Bicycle")) RimDefault = TEXT("Bicycle");
	const FString RimName = (Mods.Rims > 0 && D.Kind == EGTAVehicleKind::Car) ? FString(Rims[FMath::Clamp(Mods.Rims - 1, 0, 4)]) : RimDefault;
	const FString TireName = D.Wheel.IsEmpty() ? FString(TEXT("Std")) : D.Wheel;
	for (FGTAWheel& Wh : Wheels)
	{
		if (!Wh.Mesh) continue;
		Wh.Mesh->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Tire_") + TireName));
		Wh.Mesh->SetRelativeScale3D(FVector(Wh.Radius / 50.f));
		Wh.Rim->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Rim_") + RimName));
		UMaterialInstanceDynamic* MID = Wh.Rim->CreateDynamicMaterialInstance(0);
		if (MID) MID->SetVectorParameterValue(TEXT("Color"), Mods.RimColor);
	}

	// body kit parts
	for (UStaticMeshComponent* P : PartMeshes) if (P) P->DestroyComponent();
	PartMeshes.Reset();
	if (D.Kind == EGTAVehicleKind::Car)
	{
		const float L = D.Length * 100.f, W = D.Width * 100.f, H = D.Height * 100.f, R = D.WheelRadius * 100.f;
		const FVector WS(1.f, D.Width / 1.85f, 1.f);
		if (Mods.Spoiler > 0) AddPart(FString::Printf(TEXT("SM_Part_Spoiler%d"), FMath::Clamp(Mods.Spoiler, 1, 3)), FVector(-L * 0.45f, 0.f, H * 0.66f), FRotator::ZeroRotator, WS);
		if (Mods.Hood > 0) AddPart(FString::Printf(TEXT("SM_Part_Scoop%d"), FMath::Clamp(Mods.Hood, 1, 2)), FVector(L * 0.27f, 0.f, H * 0.6f), FRotator::ZeroRotator, FVector(1.f));
		if (Mods.Bumper > 0) AddPart(FString::Printf(TEXT("SM_Part_Bumper%d"), FMath::Clamp(Mods.Bumper, 1, 2)), FVector(L * 0.5f, 0.f, R * 0.9f), FRotator::ZeroRotator, WS);
		if (Mods.Exhaust > 0) AddPart(FString::Printf(TEXT("SM_Part_Exhaust%d"), FMath::Clamp(Mods.Exhaust, 1, 2)), FVector(-L * 0.5f, W * 0.25f, R * 0.75f), FRotator::ZeroRotator, FVector(1.f));
		if (Mods.Skirts > 0)
		{
			AddPart(TEXT("SM_Part_Skirt"), FVector(0.f, -W * 0.5f, R * 0.5f), FRotator::ZeroRotator, FVector(D.Wheelbase / 2.8f, 1.f, 1.f));
			AddPart(TEXT("SM_Part_Skirt"), FVector(0.f, W * 0.5f, R * 0.5f), FRotator(0.f, 180.f, 0.f), FVector(D.Wheelbase / 2.8f, 1.f, 1.f));
		}
		if (Mods.Roof == 1) AddPart(TEXT("SM_Part_RoofRack"), FVector(-L * 0.05f, 0.f, H), FRotator::ZeroRotator, WS);
	}
	if (D.bConvertible)
	{
		// the convertible body mesh exposes the hard-top as its own material slot; hide it when open
		SetScalarOnSlot(TEXT("V_Roof"), TEXT("Opacity"), Mods.Roof == 2 ? 0.f : 1.f);
		bRoofOpen = Mods.Roof == 2;
		if (UStaticMesh* Open = FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Veh_") + D.Key + TEXT("_Open")))
		{
			BodyMesh->SetStaticMesh(bRoofOpen ? Open : FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Veh_") + D.Key));
			BodyMIDs.Reset();
			for (int32 i = 0; i < BodyMesh->GetNumMaterials(); ++i) BodyMIDs.Add(BodyMesh->CreateDynamicMaterialInstance(i));
			SetPaintParam(TEXT("V_Paint"), TEXT("Color"), Prim);
			SetPaintParam(TEXT("V_Paint2"), TEXT("Color"), Mods.Livery > 0 ? Mods.Secondary : Prim);
		}
	}
}

void AGTAVehicle::Repair()
{
	const FGTAVehicleDef& D = GetDef();
	Health = D.Health;
	bOnFire = false;
	ExplodeAt = 0.f;
	FireTime = 0.f;
	for (FGTAWheel& Wh : Wheels) Wh.bPopped = false;
	if (bDestroyed)
	{
		bDestroyed = false;
		bEngineOn = true;
	}
	BodyMIDs.Reset();
	for (int32 i = 0; i < BodyMesh->GetNumMaterials(); ++i) BodyMIDs.Add(BodyMesh->CreateDynamicMaterialInstance(i));
	ApplyMods();
}

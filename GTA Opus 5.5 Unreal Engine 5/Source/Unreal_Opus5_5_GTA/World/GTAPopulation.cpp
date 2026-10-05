#include "World/GTAPopulation.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Core/GTAGameInstance.h"
#include "Player/GTACharacter.h"
#include "Player/GTAPlayerCharacter.h"
#include "AI/GTANPCController.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "World/GTAEnvironment.h"
#include "Components/BoxComponent.h"
#include "Engine/OverlapResult.h"
#include "Kismet/GameplayStatics.h"
#include "Camera/PlayerCameraManager.h"

AGTAPopulation::AGTAPopulation()
{
	PrimaryActorTick.bCanEverTick = true;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
}

void AGTAPopulation::BeginPlay()
{
	Super::BeginPlay();
	Rand.Initialize(1234567);
	PedTimer = 1.f;
	TrafficTimer = 1.5f;
}

AGTACity* AGTAPopulation::City() const
{
	AGTAGameMode* M = GTA::Mode(this);
	return M ? M->City.Get() : nullptr;
}

FVector AGTAPopulation::PlayerLoc() const
{
	AGTAPlayerCharacter* P = GTA::Player(this);
	return P ? P->GetActorLocation() : FVector::ZeroVector;
}

bool AGTAPopulation::IsVisibleToPlayer(const FVector& L) const
{
	APlayerCameraManager* PCM = UGameplayStatics::GetPlayerCameraManager(this, 0);
	if (!PCM) return false;
	const FVector Cam = PCM->GetCameraLocation();
	const FVector To = (L + FVector(0, 0, 120.f)) - Cam;
	if (FVector::DotProduct(PCM->GetCameraRotation().Vector(), To.GetSafeNormal()) < 0.35f) return false;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTASpawnVis), false);
	if (AGTAPlayerCharacter* P = GTA::Player(this)) { Q.AddIgnoredActor(P); if (P->Vehicle) Q.AddIgnoredActor(P->Vehicle); }
	FHitResult H;
	return !GetWorld()->LineTraceSingleByChannel(H, Cam, L + FVector(0, 0, 120.f), ECC_Visibility, Q);
}

// ------------------------------------------------------------------------------------------------ spawning

AGTACharacter* AGTAPopulation::SpawnPed(const FVector& Loc, float Yaw, EGTAPedRole InRole, int32 Seed)
{
	const FTransform T(FRotator(0.f, Yaw, 0.f), Loc + FVector(0, 0, 95.f));
	AGTACharacter* C = GetWorld()->SpawnActorDeferred<AGTACharacter>(AGTACharacter::StaticClass(), T, nullptr, nullptr, ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn);
	if (!C) return nullptr;
	C->PedRole = InRole;
	C->RandomizeAppearance(Seed >= 0 ? Seed : (++SpawnSerial * 7919 + Rand.RandHelper(100000)), InRole);
	UGameplayStatics::FinishSpawningActor(C, T);
	if (!C->GetController()) C->SpawnDefaultController();
	C->Cash = InRole == EGTAPedRole::Civilian ? Rand.RandRange(5, 140) : (InRole == EGTAPedRole::Gang ? Rand.RandRange(60, 300) : 0);
	if (InRole == EGTAPedRole::Gang)
	{
		C->GiveWeapon(Rand.FRand() < 0.6f ? EGTAWeapon::Pistol : (Rand.FRand() < 0.5f ? EGTAWeapon::SMG : EGTAWeapon::Bat), 60, true);
		C->AccuracyMult = 1.6f;
	}
	return C;
}

void AGTAPopulation::ArmPolice(AGTACharacter* C, int32 Level, bool bTactical)
{
	if (!C) return;
	C->GiveWeapon(EGTAWeapon::Pistol, 60, true);
	if (bTactical)
	{
		C->GiveWeapon(Rand.FRand() < 0.7f ? EGTAWeapon::AssaultRifle : EGTAWeapon::Carbine, 180, true);
		C->Armor = 100.f;
		C->Appearance.Vest = 2;
		C->Appearance.Hat = 4;
		C->ApplyAppearance();
	}
	else if (Level >= 3)
	{
		C->GiveWeapon(Rand.FRand() < 0.5f ? EGTAWeapon::Shotgun : EGTAWeapon::SMG, 90, true);
		C->Armor = 50.f;
	}
	C->AccuracyMult = FMath::Lerp(1.6f, 0.95f, FMath::Clamp((Level - 1) / 4.f, 0.f, 1.f));
	C->MaxHealth = C->Health = 120.f;
}

AGTAVehicle* AGTAPopulation::SpawnTrafficVehicle(EGTAVehicle Id, int32 Edge, bool bForward, float Alpha, bool bWithDriver)
{
	AGTACity* Ci = City();
	if (!Ci || !Ci->Edges.IsValidIndex(Edge)) return nullptr;
	const FVector L = Ci->LanePoint(Edge, bForward, Alpha);
	const FVector Dir = Ci->LaneDir(Edge, bForward);
	// clearance check
	TArray<FOverlapResult> Over;
	FCollisionObjectQueryParams OQ;
	OQ.AddObjectTypesToQuery(ECC_Vehicle);
	OQ.AddObjectTypesToQuery(ECC_Pawn);
	OQ.AddObjectTypesToQuery(ECC_PhysicsBody);
	if (GetWorld()->OverlapMultiByObjectType(Over, L + FVector(0, 0, 120.f), FQuat::Identity, OQ, FCollisionShape::MakeSphere(450.f))) return nullptr;
	FGTAVehicleMods Mods;
	const FGTAVehicleDef& D = FGTAData::Vehicle(Id);
	Mods.Primary = (D.bPolice || D.bTaxi || D.bEmergency) ? D.DefaultPaint : FGTAData::PaintColor(Rand.RandRange(0, FGTAData::NumPaintColors() - 1));
	Mods.Secondary = FLinearColor(0.85f, 0.85f, 0.85f);
	Mods.Finish = Rand.RandRange(0, 2);
	AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), Id, FTransform(Dir.Rotation(), L), &Mods);
	if (!V) return nullptr;
	if (bWithDriver)
	{
		const EGTAPedRole DriverRole = D.bPolice ? EGTAPedRole::Police : EGTAPedRole::Civilian;
		AGTACharacter* C = SpawnPed(L + FVector(0, 0, 300.f), Dir.Rotation().Yaw, DriverRole);
		if (C)
		{
			if (D.bPolice) ArmPolice(C, 1, false);
			V->AddOccupant(C, 0);
			Peds.Add(C);
			if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController())) AIC->StartDriving(V, Edge, bForward, Alpha);
		}
		if (V->Body) V->Body->SetPhysicsLinearVelocity(Dir * 800.f);
	}
	return V;
}

EGTAVehicle AGTAPopulation::RandomTrafficType()
{
	struct FW { EGTAVehicle Id; int32 W; };
	static const FW Table[] = {
		{ EGTAVehicle::Compact, 18 }, { EGTAVehicle::Sedan, 24 }, { EGTAVehicle::Sports, 6 }, { EGTAVehicle::Muscle, 6 },
		{ EGTAVehicle::SUV, 12 }, { EGTAVehicle::Pickup, 9 }, { EGTAVehicle::Van, 7 }, { EGTAVehicle::Taxi, 8 },
		{ EGTAVehicle::BoxTruck, 4 }, { EGTAVehicle::Police, 3 }, { EGTAVehicle::Motorcycle, 3 }
	};
	int32 Total = 0;
	for (const FW& E : Table) Total += E.W;
	int32 R = Rand.RandRange(0, Total - 1);
	for (const FW& E : Table) { if (R < E.W) return E.Id; R -= E.W; }
	return EGTAVehicle::Sedan;
}

AGTAVehicle* AGTAPopulation::SpawnPoliceUnit(const FVector& Near, bool bTactical)
{
	AGTACity* Ci = City();
	AGTAGameMode* M = GTA::Mode(this);
	if (!Ci || !M) return nullptr;
	for (int32 Try = 0; Try < 8; ++Try)
	{
		int32 E; bool bF; float A;
		if (!Ci->RandomLaneSpawn(Near, 9000.f, 17000.f, Rand, E, bF, A)) continue;
		const FVector L = Ci->LanePoint(E, bF, A);
		if (IsVisibleToPlayer(L)) continue;
		AGTAVehicle* V = SpawnTrafficVehicle(bTactical ? EGTAVehicle::Tactical : EGTAVehicle::Police, E, bF, A, false);
		if (!V) continue;
		const int32 Crew = bTactical ? FMath::Min(4, V->NumSeats()) : FMath::Min(2, V->NumSeats());
		for (int32 s = 0; s < Crew; ++s)
		{
			AGTACharacter* C = SpawnPed(L + FVector(0, 0, 300.f + s * 200.f), 0.f, bTactical ? EGTAPedRole::Swat : EGTAPedRole::Police);
			if (!C) continue;
			ArmPolice(C, M->WantedLevel, bTactical);
			V->AddOccupant(C, s);
			PoliceUnits.Add(C);
			if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController()))
			{
				AIC->bIsDispatchUnit = true;
				if (s == 0) AIC->StartPursuit(V); else AIC->SetState(EGTANPCState::Passenger);
			}
		}
		if (V->Body) V->Body->SetPhysicsLinearVelocity(Ci->LaneDir(E, bF) * 1200.f);
		PoliceVehicles.Add(V);
		return V;
	}
	return nullptr;
}

AGTAVehicle* AGTAPopulation::SpawnPoliceHeli()
{
	AGTAGameMode* M = GTA::Mode(this);
	const FVector P = PlayerLoc();
	const FVector Off = FRotator(0.f, Rand.FRandRange(0.f, 360.f), 0.f).Vector() * 15000.f;
	AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), EGTAVehicle::PoliceHeli, FTransform(FRotator(0.f, (-Off).Rotation().Yaw, 0.f), P + Off + FVector(0, 0, 6000.f)));
	if (!V) return nullptr;
	V->bKinematicAI = true;
	V->AIFlyTarget = P + FVector(0, 0, 4500.f);
	for (int32 s = 0; s < FMath::Min(2, V->NumSeats()); ++s)
	{
		AGTACharacter* C = SpawnPed(P + Off + FVector(0, 0, 6200.f + s * 200.f), 0.f, EGTAPedRole::Police);
		if (!C) continue;
		ArmPolice(C, M ? M->WantedLevel : 3, s > 0);
		V->AddOccupant(C, s);
		PoliceUnits.Add(C);
		if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController())) { AIC->bIsDispatchUnit = true; AIC->SetState(EGTANPCState::Passenger); }
	}
	PoliceVehicles.Add(V);
	return V;
}

void AGTAPopulation::SpawnFootPolice(const FVector& Near, int32 Count)
{
	AGTACity* Ci = City();
	AGTAGameMode* M = GTA::Mode(this);
	if (!Ci) return;
	for (int32 i = 0; i < Count; ++i)
	{
		FVector L;
		if (!Ci->RandomSidewalkPoint(Near, 2500.f, 6000.f, Rand, L)) continue;
		AGTACharacter* C = SpawnPed(L, 0.f, EGTAPedRole::Police);
		if (!C) continue;
		ArmPolice(C, M ? M->WantedLevel : 1, false);
		PoliceUnits.Add(C);
		if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController()))
		{
			AIC->bIsDispatchUnit = true;
			AIC->StartInvestigate(M ? M->LastKnownPos : Near);
		}
	}
}

void AGTAPopulation::SpawnRoadblock()
{
	AGTACity* Ci = City();
	AGTAGameMode* M = GTA::Mode(this);
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!Ci || !M || !P) return;
	FVector Dir = P->GetVelocity().GetSafeNormal2D();
	if (Dir.IsNearlyZero()) Dir = P->GetActorForwardVector();
	const FVector Ahead = P->GetActorLocation() + Dir * 13000.f;
	float T = 0.f;
	const int32 E = Ci->NearestEdge(Ahead, &T);
	if (E == INDEX_NONE) return;
	const FGTARoadEdge& Ed = Ci->Edges[E];
	const FVector C = FMath::Lerp(Ci->Nodes[Ed.A].Pos, Ci->Nodes[Ed.B].Pos, FMath::Clamp(T, 0.3f, 0.7f));
	if (IsVisibleToPlayer(C) && FVector::Dist2D(C, P->GetActorLocation()) < 9000.f) return;
	const FVector Right(-Ed.Dir.Y, Ed.Dir.X, 0.f);
	const float Yaw = Ed.Dir.Rotation().Yaw + 90.f;
	for (int32 i = 0; i < 2; ++i)
	{
		const FVector L = C + Right * (i == 0 ? -260.f : 260.f) + FVector(0, 0, 20.f);
		AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), M->WantedLevel >= 4 ? EGTAVehicle::Tactical : EGTAVehicle::Police, FTransform(FRotator(0.f, Yaw + (i ? 180.f : 0.f), 0.f), L));
		if (!V) continue;
		V->bParked = true;
		if (!V->bSirenOn) V->ToggleSiren();
		PoliceVehicles.Add(V);
		for (int32 k = 0; k < 2; ++k)
		{
			const FVector OL = L + Ed.Dir * (k == 0 ? 450.f : -450.f) * (i == 0 ? 1.f : -1.f);
			AGTACharacter* O = SpawnPed(OL, Yaw, M->WantedLevel >= 4 ? EGTAPedRole::Swat : EGTAPedRole::Police);
			if (!O) continue;
			ArmPolice(O, M->WantedLevel, M->WantedLevel >= 4);
			PoliceUnits.Add(O);
			if (AGTANPCController* AIC = Cast<AGTANPCController>(O->GetController())) { AIC->bIsDispatchUnit = true; AIC->StartInvestigate(OL); }
		}
	}
	GTA::Notify(this, TEXT("Police roadblock ahead!"), 3.f);
}

AGTAVehicle* AGTAPopulation::CallTaxi(const FVector& Pickup)
{
	AGTACity* Ci = City();
	if (!Ci) return nullptr;
	if (IsValid(ActiveTaxi) && !ActiveTaxi->bDestroyed && ActiveTaxi->GetDriver())
	{
		if (AGTANPCController* AIC = Cast<AGTANPCController>(ActiveTaxi->GetDriver()->GetController())) AIC->StartTaxi(ActiveTaxi, Pickup, true);
		GTA::Notify(this, TEXT("Your Neon Cab is on the way."), 3.f);
		return ActiveTaxi;
	}
	for (int32 Try = 0; Try < 12; ++Try)
	{
		int32 E; bool bF; float A;
		if (!Ci->RandomLaneSpawn(Pickup, 5000.f, 12000.f, Rand, E, bF, A)) continue;
		AGTAVehicle* V = SpawnTrafficVehicle(EGTAVehicle::Taxi, E, bF, A, true);
		if (!V || !V->GetDriver()) continue;
		if (AGTANPCController* AIC = Cast<AGTANPCController>(V->GetDriver()->GetController())) AIC->StartTaxi(V, Pickup, true);
		ActiveTaxi = V;
		GTA::Notify(this, TEXT("Your Neon Cab is on the way."), 3.f);
		return V;
	}
	GTA::Notify(this, TEXT("No cabs available right now."), 2.f);
	return nullptr;
}

void AGTAPopulation::DestroyPed(AGTACharacter* C)
{
	if (!C) return;
	if (C->Vehicle) C->Vehicle->RemoveOccupant(C);
	if (AController* Ctrl = C->GetController()) { Ctrl->UnPossess(); Ctrl->Destroy(); }
	C->Destroy();
}

void AGTAPopulation::DestroyVehicle(AGTAVehicle* V)
{
	if (!V) return;
	for (const TObjectPtr<AGTACharacter>& O : V->Occupants)
	{
		if (O && !O->IsPlayerCharacter()) DestroyPed(O.Get());
	}
	V->Destroy();
}

void AGTAPopulation::ClearPolice()
{
	for (AGTACharacter* C : PoliceUnits) if (C && !C->IsInVehicle()) DestroyPed(C);
	for (AGTAVehicle* V : PoliceVehicles)
	{
		if (!V) continue;
		AGTAPlayerCharacter* P = GTA::Player(this);
		if (P && P->Vehicle == V) continue;
		DestroyVehicle(V);
	}
	PoliceUnits.Reset();
	PoliceVehicles.Reset();
}

void AGTAPopulation::ClearAll()
{
	ClearPolice();
	AGTAPlayerCharacter* P = GTA::Player(this);
	for (AGTACharacter* C : Peds) if (C) DestroyPed(C);
	for (AGTAVehicle* V : Traffic) if (V && (!P || P->Vehicle != V)) DestroyVehicle(V);
	for (AGTAVehicle* V : Parked) if (V && (!P || P->Vehicle != V) && !V->bPlayerOwned) DestroyVehicle(V);
	Peds.Reset();
	Traffic.Reset();
	Parked.Reset();
	ParkedSpotOf.Reset();
	ParkedSpotsUsed.Reset();
}

// ------------------------------------------------------------------------------------------------ events

void AGTAPopulation::OnWantedChanged(int32 OldLevel, int32 NewLevel)
{
	DispatchTimer = 0.f;
	if (NewLevel <= 0)
	{
		// units return to normal life; they are recycled when far away
		for (AGTACharacter* C : PoliceUnits)
		{
			if (!C || C->bDead) continue;
			if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController()))
			{
				if (!C->IsInVehicle()) AIC->StartWander();
			}
		}
		return;
	}
	if (NewLevel > OldLevel)
	{
		for (AGTACharacter* C : PoliceUnits) if (C && !C->bDead) ArmPolice(C, NewLevel, C->PedRole == EGTAPedRole::Swat);
		GTA::Play2D(this, TEXT("S_WantedUp"), 0.6f);
	}
}

void AGTAPopulation::OnPlayerRespawned()
{
	ClearPolice();
	for (AGTACharacter* C : Peds) if (C && C->bDead) DestroyPed(C);
	Peds.RemoveAll([](const TObjectPtr<AGTACharacter>& C) { return !IsValid(C); });
}

void AGTAPopulation::OnNoise(const FVector& Loc, float Radius, AActor* NoiseMaker, bool bThreat)
{
}

void AGTAPopulation::OnPedKilled(AGTACharacter* Victim)
{
	if (Victim && Victim->IsPolice()) PoliceKilled++;
}

// ------------------------------------------------------------------------------------------------ tick

void AGTAPopulation::Tick(float Dt)
{
	Super::Tick(Dt);
	if (!GTA::Player(this) || !City()) return;
	TickPeds(Dt);
	TickTraffic(Dt);
	TickParked(Dt);
	TickDispatch(Dt);
	TierTimer -= Dt;
	if (TierTimer <= 0.f) { TierTimer = 1.f; TickSimTiers(); TickFixedVehicles(); }
}

void AGTAPopulation::TickPeds(float Dt)
{
	PedTimer -= Dt;
	if (PedTimer > 0.f) return;
	PedTimer = 0.5f;
	UGTAGameInstance* GI = GTA::Instance(this);
	AGTACity* Ci = City();
	const FVector P = PlayerLoc();
	const float Now = GetWorld()->GetTimeSeconds();
	for (int32 i = Peds.Num() - 1; i >= 0; --i)
	{
		AGTACharacter* C = Peds[i];
		if (!IsValid(C)) { Peds.RemoveAt(i); continue; }
		const float D = FVector::Dist2D(C->GetActorLocation(), P);
		const bool bFar = D > 17000.f && !IsVisibleToPlayer(C->GetActorLocation());
		const bool bOldBody = C->bDead && Now - C->LastDamageTime > 40.f && !IsVisibleToPlayer(C->GetActorLocation());
		if (bFar || D > 26000.f || bOldBody || C->GetActorLocation().Z < -5000.f)
		{
			if (C->IsInVehicle()) continue;   // drivers are owned by their vehicle
			DestroyPed(C);
			Peds.RemoveAt(i);
		}
	}
	if (GI && !GI->bPedsEnabled) return;
	float Density = 1.f;
	if (AGTAGameMode* M = GTA::Mode(this)) { if (M->Env) Density = FMath::Lerp(1.f, 0.55f, M->Env->NightFactor()) * FMath::Lerp(1.f, 0.6f, M->Env->GetRain()); }
	const int32 Target = FMath::RoundToInt(TargetPeds * Density);
	int32 Alive = 0;
	for (AGTACharacter* C : Peds) if (C && !C->bDead && !C->IsInVehicle()) Alive++;
	for (int32 k = 0; k < 3 && Alive < Target; ++k)
	{
		FVector L;
		if (!Ci->RandomSidewalkPoint(P, 4500.f, 13000.f, Rand, L)) continue;
		if (IsVisibleToPlayer(L) && FVector::Dist2D(L, P) < 8000.f) continue;
		const EGTADistrict Dist = AGTACity::DistrictAt(L.X, L.Y);
		EGTAPedRole NewRole = EGTAPedRole::Civilian;
		const float R = Rand.FRand();
		if ((Dist == EGTADistrict::Industrial || Dist == EGTADistrict::Harbor) && R < 0.22f) NewRole = EGTAPedRole::Gang;
		else if ((Dist == EGTADistrict::Downtown || Dist == EGTADistrict::NeonRow) && R < 0.05f) NewRole = EGTAPedRole::Police;
		AGTACharacter* C = SpawnPed(L, Rand.FRandRange(0.f, 360.f), NewRole);
		if (!C) continue;
		if (NewRole == EGTAPedRole::Police) ArmPolice(C, 1, false);
		if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController()))
		{
			if (NewRole == EGTAPedRole::Gang && Rand.FRand() < 0.5f) { AIC->SetState(EGTANPCState::Idle); }
			else AIC->StartWander();
		}
		Peds.Add(C);
		Alive++;
	}
}

void AGTAPopulation::TickTraffic(float Dt)
{
	TrafficTimer -= Dt;
	if (TrafficTimer > 0.f) return;
	TrafficTimer = 0.5f;
	UGTAGameInstance* GI = GTA::Instance(this);
	AGTACity* Ci = City();
	AGTAPlayerCharacter* Player = GTA::Player(this);
	const FVector P = PlayerLoc();
	for (int32 i = Traffic.Num() - 1; i >= 0; --i)
	{
		AGTAVehicle* V = Traffic[i];
		if (!IsValid(V)) { Traffic.RemoveAt(i); continue; }
		if (Player && Player->Vehicle == V && V->GetDriver() == Player) { Traffic.RemoveAt(i); continue; }   // stolen: no longer traffic
		if (V == ActiveTaxi) continue;
		const float D = FVector::Dist2D(V->GetActorLocation(), P);
		const bool bDriverless = !V->GetDriver() || V->GetDriver()->bDead;
		if ((D > 22000.f && !IsVisibleToPlayer(V->GetActorLocation())) || D > 30000.f || (bDriverless && D > 12000.f) || V->GetActorLocation().Z < -3000.f)
		{
			DestroyVehicle(V);
			Traffic.RemoveAt(i);
		}
	}
	if (GI && !GI->bTrafficEnabled) return;
	float Density = 1.f;
	if (AGTAGameMode* M = GTA::Mode(this)) { if (M->Env) Density = FMath::Lerp(1.f, 0.6f, M->Env->NightFactor()); }
	const int32 Target = FMath::RoundToInt(TargetTraffic * Density);
	for (int32 k = 0; k < 2 && Traffic.Num() < Target; ++k)
	{
		int32 E; bool bF; float A;
		if (!Ci->RandomLaneSpawn(P, 8000.f, 17000.f, Rand, E, bF, A)) continue;
		const FVector L = Ci->LanePoint(E, bF, A);
		if (IsVisibleToPlayer(L) && FVector::Dist2D(L, P) < 12000.f) continue;
		if (AGTAVehicle* V = SpawnTrafficVehicle(RandomTrafficType(), E, bF, A, true)) Traffic.Add(V);
	}
}

void AGTAPopulation::TickParked(float Dt)
{
	ParkedTimer -= Dt;
	if (ParkedTimer > 0.f) return;
	ParkedTimer = 1.f;
	AGTACity* Ci = City();
	AGTAPlayerCharacter* Player = GTA::Player(this);
	const FVector P = PlayerLoc();
	for (int32 i = Parked.Num() - 1; i >= 0; --i)
	{
		AGTAVehicle* V = Parked[i];
		if (!IsValid(V)) { Parked.RemoveAt(i); continue; }
		const bool bUsed = (Player && Player->Vehicle == V) || V->bPlayerOwned || V->bWasStolen;
		if (bUsed) continue;
		if (FVector::Dist2D(V->GetActorLocation(), P) > 17000.f && !IsVisibleToPlayer(V->GetActorLocation()))
		{
			if (int32* Spot = ParkedSpotOf.Find(V)) ParkedSpotsUsed.Remove(*Spot);
			ParkedSpotOf.Remove(V);
			DestroyVehicle(V);
			Parked.RemoveAt(i);
		}
	}
	for (int32 s = 0; s < Ci->ParkingSpots.Num(); ++s)
	{
		if (ParkedSpotsUsed.Contains(s)) continue;
		const FTransform& T = Ci->ParkingSpots[s];
		const float D = FVector::Dist2D(T.GetLocation(), P);
		if (D > 13000.f || D < 2500.f) continue;
		if (IsVisibleToPlayer(T.GetLocation()) && D < 7000.f) continue;
		EGTAVehicle Id = RandomTrafficType();
		if (s < 2) Id = EGTAVehicle::Police;
		else if (s == 2) Id = EGTAVehicle::Ambulance;
		if (Id == EGTAVehicle::Motorcycle && Rand.FRand() < 0.5f) Id = EGTAVehicle::Bicycle;
		FGTAVehicleMods Mods;
		const FGTAVehicleDef& Def = FGTAData::Vehicle(Id);
		Mods.Primary = (Def.bPolice || Def.bTaxi || Def.bEmergency) ? Def.DefaultPaint : FGTAData::PaintColor(Rand.RandRange(0, FGTAData::NumPaintColors() - 1));
		AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), Id, T, &Mods);
		if (!V) continue;
		V->bParked = true;
		V->bEngineOn = false;
		Parked.Add(V);
		ParkedSpotsUsed.Add(s);
		ParkedSpotOf.Add(V, s);
	}
}

void AGTAPopulation::TickFixedVehicles()
{
	AGTACity* Ci = City();
	AGTAPlayerCharacter* Player = GTA::Player(this);
	if (!Ci) return;
	const int32 NumSpots = Ci->BoatSpots.Num() + Ci->AircraftSpots.Num();
	if (FixedVehicles.Num() != NumSpots) FixedVehicles.SetNum(NumSpots);
	for (int32 i = 0; i < NumSpots; ++i)
	{
		const bool bBoat = i < Ci->BoatSpots.Num();
		const FTransform& T = bBoat ? Ci->BoatSpots[i] : Ci->AircraftSpots[i - Ci->BoatSpots.Num()];
		AGTAVehicle* V = FixedVehicles[i];
		const bool bAway = !IsValid(V) || V->bDestroyed || FVector::Dist2D(V->GetActorLocation(), T.GetLocation()) > 6000.f;
		if (!bAway) continue;
		if (IsValid(V) && Player && Player->Vehicle == V) continue;
		if (IsValid(V) && V->bDestroyed && IsVisibleToPlayer(V->GetActorLocation())) continue;
		if (IsVisibleToPlayer(T.GetLocation()) && FVector::Dist2D(T.GetLocation(), PlayerLoc()) < 9000.f) continue;
		EGTAVehicle Id = EGTAVehicle::Speedboat;
		if (!bBoat)
		{
			const int32 k = i - Ci->BoatSpots.Num();
			Id = k == 0 ? EGTAVehicle::PropPlane : (k == 1 ? EGTAVehicle::Jet : EGTAVehicle::Helicopter);
		}
		AGTAVehicle* N = AGTAVehicle::SpawnVehicle(GetWorld(), Id, T);
		if (!N) continue;
		N->bParked = true;
		N->bEngineOn = false;
		FixedVehicles[i] = N;
	}
}

void AGTAPopulation::TickDispatch(float Dt)
{
	AGTAGameMode* M = GTA::Mode(this);
	if (!M) return;
	PoliceUnits.RemoveAll([](const TObjectPtr<AGTACharacter>& C) { return !IsValid(C); });
	PoliceVehicles.RemoveAll([](const TObjectPtr<AGTAVehicle>& V) { return !IsValid(V); });
	DispatchTimer -= Dt;
	if (DispatchTimer > 0.f) return;
	DispatchTimer = 1.f;
	const FVector P = PlayerLoc();
	AGTAPlayerCharacter* Player = GTA::Player(this);
	// recycle far / idle units
	for (int32 i = PoliceVehicles.Num() - 1; i >= 0; --i)
	{
		AGTAVehicle* V = PoliceVehicles[i];
		if (Player && Player->Vehicle == V) { PoliceVehicles.RemoveAt(i); continue; }
		const float D = FVector::Dist2D(V->GetActorLocation(), P);
		if ((M->WantedLevel == 0 && D > 12000.f && !IsVisibleToPlayer(V->GetActorLocation())) || D > 30000.f || (V->bDestroyed && D > 9000.f))
		{
			DestroyVehicle(V);
			PoliceVehicles.RemoveAt(i);
		}
	}
	for (int32 i = PoliceUnits.Num() - 1; i >= 0; --i)
	{
		AGTACharacter* C = PoliceUnits[i];
		if (C->IsInVehicle()) continue;
		const float D = FVector::Dist2D(C->GetActorLocation(), P);
		if ((M->WantedLevel == 0 && D > 9000.f && !IsVisibleToPlayer(C->GetActorLocation())) || D > 26000.f || (C->bDead && D > 9000.f))
		{
			DestroyPed(C);
			PoliceUnits.RemoveAt(i);
		}
	}
	if (M->WantedLevel <= 0 || M->bRespawning) return;

	int32 Cars = 0, Helis = 0;
	for (AGTAVehicle* V : PoliceVehicles)
	{
		if (V->bDestroyed) continue;
		if (V->IsAircraft()) { Helis++; continue; }
		const AGTACharacter* Dr = V->GetDriver();
		if (Dr && !Dr->bDead && !V->bParked) Cars++;
	}
	const int32 WantCars = FMath::Min(1 + M->WantedLevel, 6);
	if (Cars < WantCars) SpawnPoliceUnit(M->LastKnownPos, M->WantedLevel >= 4 && Rand.FRand() < 0.5f);
	const int32 WantHelis = M->WantedLevel >= 5 ? 2 : (M->WantedLevel >= 3 ? 1 : 0);
	if (Helis < WantHelis) SpawnPoliceHeli();
	int32 Foot = 0;
	for (AGTACharacter* C : PoliceUnits) if (C && !C->bDead && !C->IsInVehicle()) Foot++;
	if (Player && !Player->IsInVehicle() && Foot < M->WantedLevel * 2) SpawnFootPolice(M->LastKnownPos, 1);
	// helicopters track the suspect (or the search area) and light it at night
	const float Now = GetWorld()->GetTimeSeconds();
	int32 HeliIdx = 0;
	for (AGTAVehicle* V : PoliceVehicles)
	{
		if (!V->IsAircraft() || V->bDestroyed) continue;
		const FVector Focus = M->IsPursuit() ? P : M->LastKnownPos;
		const float A = Now * 0.25f + HeliIdx * PI;
		V->AIFlyTarget = Focus + FVector(FMath::Cos(A) * 2800.f, FMath::Sin(A) * 2800.f, 4500.f);
		V->AIFlySpeed = 2600.f;
		V->bSearchlightOn = GTA::IsNight(this);
		V->SearchlightTarget = Focus;
		HeliIdx++;
	}
	if (M->WantedLevel >= 3)
	{
		RoadblockTimer -= 1.f;
		if (RoadblockTimer <= 0.f && Player && Player->IsInVehicle())
		{
			RoadblockTimer = M->WantedLevel >= 4 ? 30.f : 45.f;
			SpawnRoadblock();
		}
	}
}

void AGTAPopulation::TickSimTiers()
{
	const FVector P = PlayerLoc();
	auto Tier = [&](AGTACharacter* C)
	{
		if (!C || C->bDead) return;
		const float D = FVector::Dist2D(C->GetActorLocation(), P);
		C->SetSimTier(D < 4000.f ? 0 : (D < 9000.f ? 1 : 2));
	};
	for (AGTACharacter* C : Peds) Tier(C);
	for (AGTACharacter* C : PoliceUnits) Tier(C);
}

// NPC behaviour on foot: wandering, panic, witnesses, combat, police arrest and search.
#include "AI/GTANPCController.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Player/GTACharacter.h"
#include "Player/GTAPlayerCharacter.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "World/GTAPickup.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Navigation/PathFollowingComponent.h"

AGTANPCController::AGTANPCController()
{
	PrimaryActorTick.bCanEverTick = true;
	bWantsPlayerState = false;
	bSetControlRotationFromPawnOrientation = true;
}

void AGTANPCController::OnPossess(APawn* InPawn)
{
	Super::OnPossess(InPawn);
	Rand.Initialize(GetUniqueID() * 2654435761u);
	PerceptionTimer = Rand.FRandRange(0.f, 0.3f);
	if (AGTACharacter* C = Me())
	{
		Bravery = C->PedRole == EGTAPedRole::Gang ? 1.f : (C->IsPolice() ? 1.f : Rand.FRandRange(0.f, 0.35f));
	}
}

AGTACharacter* AGTANPCController::Me() const { return Cast<AGTACharacter>(GetPawn()); }
AGTAVehicle* AGTANPCController::MyVehicle() const { AGTACharacter* C = Me(); return C ? C->Vehicle.Get() : nullptr; }
AGTACity* AGTANPCController::City() const { AGTAGameMode* M = GTA::Mode(this); return M ? M->City.Get() : nullptr; }

bool AGTANPCController::IsAlerted() const
{
	switch (State)
	{
	case EGTANPCState::Idle:
	case EGTANPCState::Wander:
	case EGTANPCState::Drive:
	case EGTANPCState::Passenger:
	case EGTANPCState::Guard: return false;
	default: return true;
	}
}

void AGTANPCController::SetState(EGTANPCState S)
{
	AGTACharacter* C = Me();
	if (C && State != S)
	{
		if (S != EGTANPCState::Fight) { C->SetAiming(false); C->SetTriggerHeld(false); C->bUseAimPoint = false; ClearFocus(EAIFocusPriority::Gameplay); }
		if (S != EGTANPCState::HandsUp && S != EGTANPCState::Cower && C->bForcePose && !C->IsInVehicle()) { C->SetHandsUp(false); C->bForcePose = false; }
		C->SetSprinting(false);
	}
	State = S;
	StateTime = 0.f;
	bPhoning = false;
}

void AGTANPCController::StartWander()
{
	SetState(EGTANPCState::Wander);
	WanderEdge = INDEX_NONE;
	if (AGTACharacter* C = Me()) C->MoveSpeedScale = Rand.FRandRange(0.33f, 0.42f);
}

void AGTANPCController::StartGuard(const FVector& Post, float Yaw)
{
	SetState(EGTANPCState::Guard);
	Goal = Post;
	ThreatLoc = Post + FRotator(0.f, Yaw, 0.f).Vector() * 200.f;
}

void AGTANPCController::StartFight(AActor* InTarget)
{
	Target = InTarget;
	SetState(EGTANPCState::Fight);
	LastSeenTargetTime = GetWorld()->GetTimeSeconds();
	if (InTarget) LastSeenTargetLoc = InTarget->GetActorLocation();
	if (AGTACharacter* C = Me()) C->MoveSpeedScale = 1.f;
}

void AGTANPCController::StartInvestigate(const FVector& L)
{
	Goal = L;
	SetState(EGTANPCState::Investigate);
	if (AGTACharacter* C = Me()) C->MoveSpeedScale = 1.f;
}

// ------------------------------------------------------------------------------------------------ world events

void AGTANPCController::OnDamaged(AActor* Attacker, float Damage)
{
	AGTACharacter* C = Me();
	if (!C || C->bDead) return;
	if (AGTACharacter* AC = Cast<AGTACharacter>(Attacker)) { if (AC->IsPolice() && C->IsPolice()) return; }
	ThreatLoc = Attacker ? Attacker->GetActorLocation() : C->GetActorLocation();
	if (C->IsInVehicle())
	{
		if (C->SeatIndex == 0 && State == EGTANPCState::Drive) { CruiseKmh = 80.f; SetState(EGTANPCState::Flee); }
		return;
	}
	if (C->IsPolice() || C->PedRole == EGTAPedRole::Gang || Rand.FRand() < Bravery)
	{
		if (Attacker) StartFight(Attacker);
		return;
	}
	SetState(EGTANPCState::Flee);
	C->Cash = FMath::Max(C->Cash, 0);
}

void AGTANPCController::OnPawnDied()
{
	SetState(EGTANPCState::Dead);
	StopMovement();
}

void AGTANPCController::OnNoise(const FVector& Loc, float Radius, AActor* NoiseMaker, bool bThreat)
{
	AGTACharacter* C = Me();
	if (!C || C->bDead || !bThreat) return;
	const float D = FVector::Dist(C->GetActorLocation(), Loc);
	if (C->IsPolice())
	{
		if (State == EGTANPCState::Fight || State == EGTANPCState::Arrest || C->IsInVehicle()) return;
		AGTACharacter* IC = Cast<AGTACharacter>(NoiseMaker);
		if (IC && IC->IsPlayerCharacter() && CanSee(IC, 6000.f)) { StartFight(IC); return; }
		if (State != EGTANPCState::Investigate) StartInvestigate(Loc);
		return;
	}
	if (C->PedRole == EGTAPedRole::Gang)
	{
		if (NoiseMaker && D < 2500.f && State != EGTANPCState::Fight && CanSee(NoiseMaker, 3000.f)) StartFight(NoiseMaker);
		return;
	}
	if (C->IsInVehicle())
	{
		if (C->SeatIndex == 0 && State == EGTANPCState::Drive && D < 3000.f) { CruiseKmh = 75.f; SetState(EGTANPCState::Flee); }
		return;
	}
	if (State == EGTANPCState::ReportCrime || State == EGTANPCState::HandsUp) return;
	ThreatLoc = Loc;
	if (D < 600.f && Rand.FRand() < 0.4f) SetState(EGTANPCState::Cower);
	else SetState(EGTANPCState::Flee);
	if (Rand.FRand() < 0.3f) GTA::Play3D(this, TEXT("S_Scream"), C->GetActorLocation(), 0.7f, Rand.FRandRange(0.85f, 1.2f));
}

void AGTANPCController::OnAimedAt(AActor* Aimer)
{
	AGTACharacter* C = Me();
	if (!C || C->bDead || C->IsInVehicle()) return;
	if (C->IsPolice() || C->PedRole == EGTAPedRole::Gang) { if (State != EGTANPCState::Fight) StartFight(Aimer); return; }
	ThreatLoc = Aimer ? Aimer->GetActorLocation() : C->GetActorLocation();
	if (C->PedRole == EGTAPedRole::Shopkeeper)
	{
		if (State != EGTANPCState::HandsUp)
		{
			SetState(EGTANPCState::HandsUp);
			C->SetHandsUp(true);
			// hand over the till after a moment (robbery)
			FTimerHandle H;
			TWeakObjectPtr<AGTANPCController> WeakThis(this);
			GetWorldTimerManager().SetTimer(H, FTimerDelegate::CreateWeakLambda(this, [WeakThis, Aimer]()
			{
				AGTANPCController* Self = WeakThis.Get();
				AGTACharacter* SC = Self ? Self->Me() : nullptr;
				if (!SC || SC->bDead || Self->State != EGTANPCState::HandsUp) return;
				AGTAPickup::SpawnCash(SC->GetWorld(), SC->GetActorLocation() + SC->GetActorForwardVector() * 80.f, FMath::RandRange(250, 900));
				if (AGTACharacter* A = Cast<AGTACharacter>(Aimer)) GTA::ReportCrime(SC, A, EGTACrime::Robbery, SC->GetActorLocation(), SC);
			}), 2.5f, false);
		}
		return;
	}
	if (FVector::Dist(C->GetActorLocation(), ThreatLoc) < 900.f)
	{
		if (State != EGTANPCState::HandsUp) { SetState(EGTANPCState::HandsUp); C->SetHandsUp(true); }
	}
	else if (State != EGTANPCState::Flee) SetState(EGTANPCState::Flee);
}

void AGTANPCController::StartReportingCrime(const FVector& Loc, AActor* Offender)
{
	AGTACharacter* C = Me();
	if (!C || C->bDead || C->IsInVehicle()) return;
	ThreatLoc = Offender ? Offender->GetActorLocation() : Loc;
	SetState(EGTANPCState::ReportCrime);
	ReportUntil = GetWorld()->GetTimeSeconds() + 8.f;
}

void AGTANPCController::OnVehicleJacked(AActor* Jacker)
{
	AGTACharacter* C = Me();
	if (!C) return;
	ThreatLoc = Jacker ? Jacker->GetActorLocation() : C->GetActorLocation();
	if (C->PedRole == EGTAPedRole::Gang || C->IsPolice() || Rand.FRand() < Bravery * 0.6f) StartFight(Jacker);
	else SetState(EGTANPCState::Flee);
}

void AGTANPCController::ExitVehicleAndFight()
{
	AGTACharacter* C = Me();
	AGTAVehicle* V = MyVehicle();
	if (!C || !V) return;
	const int32 Seat = C->SeatIndex;
	const FVector Exit = V->GetExitLocation(Seat);
	V->RemoveOccupant(C);
	C->LeaveVehicleTo(Exit, V->GetActorRotation().Yaw);
	if (AGTAPlayerCharacter* P = GTA::Player(this)) StartFight(P);
}

// ------------------------------------------------------------------------------------------------ perception

bool AGTANPCController::CanSee(const AActor* T, float Range) const
{
	const AGTACharacter* C = Me();
	if (!C || !T) return false;
	const FVector Eye = C->GetActorLocation() + FVector(0, 0, 65.f);
	const FVector TL = T->GetActorLocation() + FVector(0, 0, 40.f);
	const float D = FVector::Dist(Eye, TL);
	if (D > Range) return false;
	if (D > 1200.f)
	{
		const FVector Fwd = C->IsInVehicle() && C->Vehicle ? C->Vehicle->GetActorForwardVector() : C->GetActorForwardVector();
		if (FVector::DotProduct(Fwd, (TL - Eye).GetSafeNormal()) < -0.3f) return false;
	}
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTANPCSight), false, C);
	if (C->Vehicle) Q.AddIgnoredActor(C->Vehicle);
	Q.AddIgnoredActor(T);
	if (const AGTACharacter* TC = Cast<AGTACharacter>(T)) { if (TC->Vehicle) Q.AddIgnoredActor(TC->Vehicle); }
	FHitResult H;
	return !GetWorld()->LineTraceSingleByChannel(H, Eye, TL, ECC_Visibility, Q);
}

AActor* AGTANPCController::PickTarget() const
{
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (P && !P->bDead) return P;
	return nullptr;
}

void AGTANPCController::TickPerception(float Dt)
{
	PerceptionTimer -= Dt;
	if (PerceptionTimer > 0.f) return;
	PerceptionTimer = 0.3f;
	AGTACharacter* C = Me();
	AGTAGameMode* M = GTA::Mode(this);
	if (!C || !M || !C->IsPolice() || M->WantedLevel <= 0) return;
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!P || P->bDead) return;
	if (CanSee(P, M->PoliceSightRange()))
	{
		M->PlayerSpotted(P->GetActorLocation());
		LastSeenTargetTime = GetWorld()->GetTimeSeconds();
		LastSeenTargetLoc = P->GetActorLocation();
		if (!C->IsInVehicle() && State != EGTANPCState::Fight && State != EGTANPCState::Arrest)
		{
			const bool bArrest = M->WantedLevel <= 1 && GetWorld()->GetTimeSeconds() - M->LastResistTime > 4.f;
			if (bArrest) { Target = P; SetState(EGTANPCState::Arrest); C->MoveSpeedScale = 1.f; }
			else StartFight(P);
		}
	}
}

// ------------------------------------------------------------------------------------------------ movement helpers

void AGTANPCController::MoveTowards(const FVector& L, float Accept, bool bRun)
{
	AGTACharacter* C = Me();
	if (!C) return;
	C->SetSprinting(bRun);
	if (!bRun && C->MoveSpeedScale > 0.9f && State == EGTANPCState::Wander) C->MoveSpeedScale = 0.38f;
	RepathTimer -= GetWorld()->GetDeltaSeconds();
	const bool bGoalMoved = FVector::DistSquared(L, LastMoveGoal) > 250.f * 250.f;
	if (!bDirectMove && (bGoalMoved || RepathTimer <= 0.f))
	{
		RepathTimer = 1.0f;
		LastMoveGoal = L;
		const EPathFollowingRequestResult::Type R = MoveToLocation(L, Accept, true, true, true, true, nullptr, true);
		if (R == EPathFollowingRequestResult::Failed) bDirectMove = true;
	}
	if (bDirectMove)
	{
		FVector Dir = (L - C->GetActorLocation());
		Dir.Z = 0.f;
		const float Dist = Dir.Size();
		if (Dist < Accept) return;
		Dir /= Dist;
		// simple obstacle avoidance: probe ahead and steer around
		FHitResult H;
		FCollisionQueryParams Q(SCENE_QUERY_STAT(GTANPCProbe), false, C);
		const FVector From = C->GetActorLocation();
		if (GetWorld()->SweepSingleByChannel(H, From, From + Dir * 150.f, FQuat::Identity, ECC_Pawn, FCollisionShape::MakeSphere(30.f), Q))
		{
			Dir = FVector::CrossProduct(FVector::UpVector, H.ImpactNormal).GetSafeNormal2D() * (FVector::DotProduct(FVector::CrossProduct(FVector::UpVector, H.ImpactNormal), Dir) >= 0.f ? 1.f : -1.f);
		}
		C->AddMovementInput(Dir, 1.f);
		// try pathfinding again from time to time
		if (RepathTimer <= -4.f) { bDirectMove = false; RepathTimer = 0.f; }
	}
}

void AGTANPCController::StopMoving()
{
	StopMovement();
	if (AGTACharacter* C = Me()) C->SetSprinting(false);
	LastMoveGoal = FVector(1e9f);
}

void AGTANPCController::AimAndShoot(AActor* T, float Dt)
{
	AGTACharacter* C = Me();
	if (!C || !T) return;
	C->SetAiming(true);
	SetFocus(T, EAIFocusPriority::Gameplay);
	const FVector Origin = C->GetAimOrigin();
	FVector TL = T->GetActorLocation() + FVector(0, 0, 25.f);
	const float Dist = FVector::Dist(Origin, TL);
	const float Err = Dist * (0.035f + 0.02f * C->AccuracyMult) + T->GetVelocity().Size() * 0.12f;
	C->bUseAimPoint = true;
	C->AimPoint = TL + FVector(Rand.FRandRange(-Err, Err), Rand.FRandRange(-Err, Err), Rand.FRandRange(-Err, Err) * 0.6f);
	C->AimPitch = FMath::RadiansToDegrees(FMath::Atan2(TL.Z - Origin.Z, FVector::Dist2D(Origin, TL)));
	BurstTimer -= Dt;
	if (BurstTimer <= 0.f)
	{
		bBurstOn = !bBurstOn;
		BurstTimer = bBurstOn ? Rand.FRandRange(0.35f, 1.0f) : Rand.FRandRange(0.7f, 1.8f);
	}
	const float Facing = FVector::DotProduct(C->GetActorForwardVector(), (TL - Origin).GetSafeNormal2D());
	if (bBurstOn && Facing > 0.9f && !C->IsTriggerHeld())
	{
		const FGTAWeaponDef& D = C->CurrentDef();
		if (D.bAuto || Rand.FRand() < Dt * 3.f) C->SetTriggerHeld(true);
	}
	else if (!bBurstOn && C->IsTriggerHeld()) C->SetTriggerHeld(false);
}

// ------------------------------------------------------------------------------------------------ tick

void AGTANPCController::Tick(float Dt)
{
	Super::Tick(Dt);
	AGTACharacter* C = Me();
	if (!C) return;
	if (C->bDead) { if (State != EGTANPCState::Dead) SetState(EGTANPCState::Dead); return; }
	StateTime += Dt;
	TickPerception(Dt);
	if (C->IsKnockedDown()) return;
	if (C->IsInVehicle())
	{
		AGTAVehicle* V = C->Vehicle;
		if (C->SeatIndex != 0 && V)
		{
			// passengers: police shoot from vehicles / helicopters at higher wanted levels
			AGTAGameMode* M = GTA::Mode(this);
			AGTAPlayerCharacter* P = GTA::Player(this);
			const bool bShoot = C->IsPolice() && M && P && !P->bDead && M->WantedLevel >= 3 && C->CurrentDef().Cat != EGTAWeaponCat::Melee && CanSee(P, 5500.f);
			if (bShoot) AimAndShoot(P, Dt);
			else if (C->bAiming) { C->SetAiming(false); C->SetTriggerHeld(false); }
			return;
		}
		if (!V) return;
		if (V->bDestroyed || (V->bOnFire && State != EGTANPCState::PursuitDrive))
		{
			const FVector Exit = V->GetExitLocation(0);
			V->RemoveOccupant(C);
			C->LeaveVehicleTo(Exit, V->GetActorRotation().Yaw);
			ThreatLoc = V->GetActorLocation();
			SetState(EGTANPCState::Flee);
			return;
		}
		if (State == EGTANPCState::PursuitDrive) TickPursuitDrive(Dt);
		else if (State == EGTANPCState::Taxi) TickTaxi(Dt);
		else if (State == EGTANPCState::Drive || State == EGTANPCState::Flee) TickDrive(Dt);
		else { V->ClearInputs(); V->Throttle = V->ForwardSpeed() > 50.f ? -1.f : 0.f; V->bHandbrake = V->ForwardSpeed() < 50.f; }
		return;
	}
	TickFoot(Dt);
}

void AGTANPCController::TickFoot(float Dt)
{
	AGTACharacter* C = Me();
	const float Now = GetWorld()->GetTimeSeconds();
	switch (State)
	{
	case EGTANPCState::Idle:
		if (StateTime > IdleUntil) { if (C->PedRole == EGTAPedRole::Civilian) StartWander(); }
		break;
	case EGTANPCState::Wander: TickWander(Dt); break;
	case EGTANPCState::Flee: TickFlee(Dt); break;
	case EGTANPCState::Cower:
		StopMoving();
		if (!C->bForcePose) C->SetCower(true);
		if (StateTime > 7.f) { C->SetCower(false); SetState(EGTANPCState::Flee); }
		break;
	case EGTANPCState::HandsUp:
		StopMoving();
		if (StateTime > 8.f) { C->SetHandsUp(false); SetState(EGTANPCState::Flee); }
		break;
	case EGTANPCState::ReportCrime:
		if (StateTime < 2.5f) { C->MoveSpeedScale = 1.f; MoveTowards(C->GetActorLocation() + (C->GetActorLocation() - ThreatLoc).GetSafeNormal2D() * 1500.f, 100.f, true); }
		else if (Now < ReportUntil)
		{
			StopMoving();
			if (!bPhoning) { bPhoning = true; C->PlayAction(EGTAClip::Phone, true, 1.f); }
			if (FMath::Fmod(StateTime, 2.f) < Dt) C->PlayAction(EGTAClip::Phone, true, 1.f);
		}
		else SetState(EGTANPCState::Flee);
		break;
	case EGTANPCState::Fight: TickFight(Dt); break;
	case EGTANPCState::Arrest: TickArrest(Dt); break;
	case EGTANPCState::Investigate:
		MoveTowards(Goal, 300.f, true);
		if (FVector::Dist2D(C->GetActorLocation(), Goal) < 400.f || StateTime > 25.f)
		{
			AGTAGameMode* M = GTA::Mode(this);
			if (C->IsPolice() && M && M->WantedLevel > 0) SetState(EGTANPCState::Search);
			else if (StateTime > 30.f || !C->IsPolice()) StartWander();
		}
		break;
	case EGTANPCState::Search: TickSearch(Dt); break;
	case EGTANPCState::Guard:
	{
		if (FVector::Dist2D(C->GetActorLocation(), Goal) > 150.f) MoveTowards(Goal, 80.f, false);
		else { StopMoving(); SetFocalPoint(ThreatLoc); }
		break;
	}
	default: break;
	}
}

void AGTANPCController::TickWander(float Dt)
{
	AGTACharacter* C = Me();
	AGTACity* Ci = City();
	if (!Ci || Ci->Edges.Num() == 0) return;
	if (StateTime < IdleUntil) { StopMoving(); return; }
	const FVector Pos = C->GetActorLocation();
	if (!Ci->Edges.IsValidIndex(WanderEdge))
	{
		float T = 0.f;
		WanderEdge = Ci->NearestEdge(Pos, &T);
		if (WanderEdge == INDEX_NONE) return;
		const FGTARoadEdge& E = Ci->Edges[WanderEdge];
		const FVector Right(-E.Dir.Y, E.Dir.X, 0.f);
		bWanderLeft = FVector::DotProduct(Pos - Ci->Nodes[E.A].Pos, Right) < 0.f;
		bWanderToB = Rand.FRand() < 0.5f;
	}
	const FGTARoadEdge& E = Ci->Edges[WanderEdge];
	const float EndAlpha = FMath::Clamp(AGTACity::CorridorHalf / FMath::Max(E.Length, 1.f), 0.02f, 0.3f);
	const FVector Dest = Ci->SidewalkPoint(WanderEdge, bWanderLeft, bWanderToB ? 1.f - EndAlpha : EndAlpha);
	bDirectMove = true;
	MoveTowards(Dest, 120.f, false);
	if (FVector::Dist2D(Pos, Dest) < 160.f)
	{
		// reached the corner: choose the next street, staying on the nearest sidewalk
		const int32 Node = bWanderToB ? E.B : E.A;
		const int32 Next = Ci->PickNextEdge(Node, WanderEdge, Rand);
		const FGTARoadEdge& N = Ci->Edges[Next];
		const bool bToB = N.A == Node;
		const float A0 = FMath::Clamp(AGTACity::CorridorHalf / FMath::Max(N.Length, 1.f), 0.02f, 0.3f);
		const float StartAlpha = bToB ? A0 : 1.f - A0;
		const FVector L = Ci->SidewalkPoint(Next, true, StartAlpha), R = Ci->SidewalkPoint(Next, false, StartAlpha);
		bWanderLeft = FVector::DistSquared2D(Pos, L) < FVector::DistSquared2D(Pos, R);
		WanderEdge = Next;
		bWanderToB = bToB;
		if (Rand.FRand() < 0.12f)
		{
			IdleUntil = StateTime + Rand.FRandRange(2.f, 6.f);
			if (Rand.FRand() < 0.4f) C->PlayAction(EGTAClip::Phone, true, 1.f);
		}
	}
}

void AGTANPCController::TickFlee(float Dt)
{
	AGTACharacter* C = Me();
	const FVector Pos = C->GetActorLocation();
	FVector Away = (Pos - ThreatLoc).GetSafeNormal2D();
	if (Away.IsNearlyZero()) Away = C->GetActorForwardVector();
	C->MoveSpeedScale = 1.f;
	MoveTowards(Pos + Away * 2000.f, 150.f, true);
	if (StateTime > 10.f && FVector::Dist2D(Pos, ThreatLoc) > 4000.f) StartWander();
	if (StateTime > 25.f) StartWander();
}

void AGTANPCController::TickFight(float Dt)
{
	AGTACharacter* C = Me();
	AActor* T = Target.Get();
	AGTACharacter* TC = Cast<AGTACharacter>(T);
	const float Now = GetWorld()->GetTimeSeconds();
	AGTAGameMode* M = GTA::Mode(this);
	if (!T || (TC && TC->bDead) || (C->IsPolice() && M && M->WantedLevel <= 0 && TC && TC->IsPlayerCharacter()))
	{
		Target = nullptr;
		if (C->IsPolice()) { SetState(EGTANPCState::Investigate); Goal = C->GetActorLocation(); }
		else StartWander();
		return;
	}
	const bool bSee = CanSee(T, 7000.f);
	if (bSee)
	{
		LastSeenTargetTime = Now;
		LastSeenTargetLoc = T->GetActorLocation();
	}
	const FGTAWeaponDef& D = C->CurrentDef();
	const bool bGun = D.Cat != EGTAWeaponCat::Melee && D.Cat != EGTAWeaponCat::Throwable;
	const float Dist = FVector::Dist(C->GetActorLocation(), T->GetActorLocation());
	if (!bGun)
	{
		C->SetAiming(false);
		if (Dist > 160.f) { C->MoveSpeedScale = 1.f; MoveTowards(T->GetActorLocation(), 110.f, true); }
		else
		{
			StopMoving();
			SetFocus(T, EAIFocusPriority::Gameplay);
			C->SetActorRotation(FRotator(0.f, (T->GetActorLocation() - C->GetActorLocation()).Rotation().Yaw, 0.f));
			if (Rand.FRand() < Dt * 1.5f) C->Melee(Rand.FRand() < 0.2f);
		}
		return;
	}
	const float Engage = D.Cat == EGTAWeaponCat::Shotgun ? 1300.f : (D.Cat == EGTAWeaponCat::Handgun ? 2400.f : 3800.f);
	if (!bSee || Dist > Engage)
	{
		C->SetTriggerHeld(false);
		C->SetAiming(false);
		ClearFocus(EAIFocusPriority::Gameplay);
		MoveTowards(bSee ? T->GetActorLocation() : LastSeenTargetLoc, 400.f, true);
		if (!bSee && Now - LastSeenTargetTime > 8.f)
		{
			if (C->IsPolice()) SetState(EGTANPCState::Search);
			else StartWander();
		}
		return;
	}
	// in range with line of sight: shoot, occasionally shift position
	RepositionTimer -= Dt;
	if (RepositionTimer <= 0.f)
	{
		RepositionTimer = Rand.FRandRange(3.5f, 7.f);
		const FVector Side = FVector::CrossProduct((T->GetActorLocation() - C->GetActorLocation()).GetSafeNormal2D(), FVector::UpVector);
		RepositionGoal = C->GetActorLocation() + Side * Rand.FRandRange(-600.f, 600.f);
	}
	if (RepositionTimer > 2.5f && FVector::Dist2D(C->GetActorLocation(), RepositionGoal) > 120.f) MoveTowards(RepositionGoal, 100.f, false);
	else StopMoving();
	AimAndShoot(T, Dt);
}

void AGTANPCController::TickArrest(float Dt)
{
	AGTACharacter* C = Me();
	AGTAGameMode* M = GTA::Mode(this);
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!M || !P || P->bDead || M->WantedLevel <= 0) { StartWander(); return; }
	const float Now = GetWorld()->GetTimeSeconds();
	if (M->WantedLevel >= 2 || Now - M->LastResistTime < 4.f)
	{
		StartFight(P);
		return;
	}
	const float Dist = FVector::Dist2D(C->GetActorLocation(), P->GetActorLocation());
	// draw a pistol and approach
	if (!C->HasWeapon(EGTAWeapon::Pistol)) C->GiveWeapon(EGTAWeapon::Pistol, 36, true);
	if (C->CurrentWeapon() != EGTAWeapon::Pistol) C->EquipWeapon(EGTAWeapon::Pistol);
	SetFocus(P, EAIFocusPriority::Gameplay);
	if (Dist > 220.f)
	{
		C->SetAiming(Dist < 1200.f);
		C->MoveSpeedScale = 1.f;
		MoveTowards(P->GetActorLocation(), 150.f, Dist > 900.f);
		ArrestTimer = 0.f;
		return;
	}
	StopMoving();
	C->SetAiming(true);
	const bool bPlayerStill = P->GetVelocity().Size2D() < 120.f && (!P->Vehicle || P->Vehicle->ForwardSpeed() < 150.f);
	if (bPlayerStill || P->bForcePose)
	{
		ArrestTimer += Dt;
		if (ArrestTimer > 1.4f) M->OnPlayerBusted();
	}
	else ArrestTimer = FMath::Max(0.f, ArrestTimer - Dt);
}

void AGTANPCController::TickSearch(float Dt)
{
	AGTACharacter* C = Me();
	AGTAGameMode* M = GTA::Mode(this);
	if (!M || M->WantedLevel <= 0) { if (C->IsPolice() && bIsDispatchUnit) SetState(EGTANPCState::Idle); else StartWander(); return; }
	if (StateTime < 0.1f || FVector::Dist2D(C->GetActorLocation(), Goal) < 300.f || StateTime > 14.f)
	{
		StateTime = 0.2f;
		const float R = M->SearchRadius() * 0.6f;
		Goal = M->LastKnownPos + FVector(Rand.FRandRange(-R, R), Rand.FRandRange(-R, R), 0.f);
	}
	C->MoveSpeedScale = 1.f;
	MoveTowards(Goal, 250.f, false);
}

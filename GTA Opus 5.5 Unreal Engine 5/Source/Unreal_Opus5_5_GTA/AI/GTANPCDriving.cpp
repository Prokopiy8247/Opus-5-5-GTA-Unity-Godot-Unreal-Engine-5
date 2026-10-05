// NPC driving: lane-following traffic with signals and obstacle braking, and police pursuit driving.
#include "AI/GTANPCController.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Player/GTACharacter.h"
#include "Player/GTAPlayerCharacter.h"
#include "Player/GTAPlayerController.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "Components/BoxComponent.h"

void AGTANPCController::StartDriving(AGTAVehicle* V, int32 InEdge, bool bInForward, float InAlpha)
{
	SetState(EGTANPCState::Drive);
	Edge = InEdge;
	bForward = bInForward;
	NextEdge = INDEX_NONE;
	CruiseKmh = Rand.FRandRange(36.f, 50.f);
	StuckTime = 0.f;
	if (V) V->bAIDriven = true;
}

void AGTANPCController::StartPursuit(AGTAVehicle* V)
{
	SetState(EGTANPCState::PursuitDrive);
	if (V)
	{
		V->bAIDriven = true;
		if (V->GetDef().bPolice || V->GetDef().bEmergency) { if (!V->bSirenOn) V->ToggleSiren(); }
	}
	Route.Reset();
	RouteTime = 0.f;
}

float AGTANPCController::ObstacleDistanceAhead(float Range) const
{
	AGTAVehicle* V = MyVehicle();
	if (!V) return 1e9f;
	const FVector Fwd = V->GetActorForwardVector();
	const float HalfLen = V->GetDef().Length * 50.f;
	const FVector Start = V->GetActorLocation() + Fwd * (HalfLen + 60.f) + FVector(0, 0, 40.f);
	const FVector End = Start + Fwd * Range;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTATrafficProbe), false, V);
	for (const TObjectPtr<AGTACharacter>& O : V->Occupants) if (O) Q.AddIgnoredActor(O.Get());
	FCollisionObjectQueryParams OQ;
	OQ.AddObjectTypesToQuery(ECC_Pawn);
	OQ.AddObjectTypesToQuery(ECC_Vehicle);
	OQ.AddObjectTypesToQuery(ECC_PhysicsBody);
	FHitResult H;
	const FVector Half(10.f, V->GetDef().Width * 45.f, 50.f);
	if (GetWorld()->SweepSingleByObjectType(H, Start, End, V->GetActorQuat(), OQ, FCollisionShape::MakeBox(Half), Q))
	{
		return H.Distance;
	}
	return 1e9f;
}

void AGTANPCController::DriveTowards(const FVector& Dest, float DesiredKmh, float Dt, bool bAvoid)
{
	AGTAVehicle* V = MyVehicle();
	if (!V) return;
	const float Now = GetWorld()->GetTimeSeconds();
	const FVector Pos = V->GetActorLocation();
	const FVector Fwd = V->GetActorForwardVector();
	const FVector Right = V->GetActorRightVector();
	FVector To = Dest - Pos;
	To.Z = 0.f;
	const float Angle = FMath::RadiansToDegrees(FMath::Atan2(FVector::DotProduct(To, Right), FVector::DotProduct(To, Fwd)));
	const float SpeedKmh = V->ForwardSpeed() * 0.036f;

	if (Now < ReverseUntil)
	{
		V->Throttle = -0.8f;
		V->Steer = Angle > 0.f ? -1.f : 1.f;
		V->bHandbrake = false;
		return;
	}
	float Desired = DesiredKmh;
	// slow for sharp corners
	Desired = FMath::Min(Desired, FMath::Lerp(DesiredKmh, 18.f, FMath::Clamp((FMath::Abs(Angle) - 15.f) / 50.f, 0.f, 1.f)));
	if (bAvoid)
	{
		const float Brake = ObstacleDistanceAhead(FMath::Max(700.f, SpeedKmh * 25.f));
		if (Brake < 1e8f)
		{
			Desired = FMath::Min(Desired, FMath::Max(0.f, (Brake - 250.f) / 25.f));
			if (Brake < 400.f && SpeedKmh < 3.f)
			{
				HonkCooldown -= Dt;
				if (HonkCooldown <= 0.f) { HonkCooldown = Rand.FRandRange(4.f, 9.f); V->SetHorn(true); FTimerHandle H; GetWorldTimerManager().SetTimer(H, FTimerDelegate::CreateWeakLambda(V, [V]() { V->SetHorn(false); }), 0.4f, false); }
			}
		}
	}
	V->Steer = FMath::Clamp(Angle / 32.f, -1.f, 1.f);
	if (FMath::Abs(Angle) > 100.f && SpeedKmh < 15.f)
	{
		// target behind: reverse-turn
		V->Throttle = -0.6f;
		V->Steer = Angle > 0.f ? -1.f : 1.f;
		V->bHandbrake = false;
		return;
	}
	if (Desired < 1.f)
	{
		V->Throttle = SpeedKmh > 2.f ? -1.f : 0.f;
		V->bHandbrake = SpeedKmh <= 2.f;
	}
	else
	{
		V->bHandbrake = false;
		V->Throttle = FMath::Clamp((Desired - SpeedKmh) / 12.f, -1.f, 1.f);
		if (SpeedKmh < Desired * 0.5f) V->Throttle = FMath::Max(V->Throttle, 0.7f);
	}
	// stuck recovery
	if (Desired > 5.f && SpeedKmh < 2.f && V->Throttle > 0.3f) StuckTime += Dt; else StuckTime = FMath::Max(0.f, StuckTime - Dt);
	if (StuckTime > 3.5f) { StuckTime = 0.f; ReverseUntil = Now + 1.4f; }
}

void AGTANPCController::TickDrive(float Dt)
{
	AGTAVehicle* V = MyVehicle();
	AGTACity* Ci = City();
	if (!V || !Ci || !Ci->Edges.IsValidIndex(Edge)) return;
	const FVector Pos = V->GetActorLocation();
	const FGTARoadEdge& E = Ci->Edges[Edge];
	const FVector LaneA = Ci->LanePoint(Edge, bForward, 0.f), LaneB = Ci->LanePoint(Edge, bForward, 1.f);
	const FVector Dir = (LaneB - LaneA).GetSafeNormal2D();
	const float Along = FVector::DotProduct(Pos - LaneA, Dir);
	const float Remaining = E.Length - Along;
	const int32 EndNode = Ci->EdgeEndNode(Edge, bForward);
	if (!Ci->Edges.IsValidIndex(NextEdge)) NextEdge = Ci->PickNextEdge(EndNode, Edge, Rand);
	const bool bNextForward = Ci->NextEdgeForward(NextEdge, EndNode);
	const float SpeedKmh = V->ForwardSpeed() * 0.036f;
	const float Look = FMath::Clamp(SpeedKmh * 22.f, 700.f, 1800.f);
	FVector Aim;
	if (Remaining > Look) Aim = Ci->LanePoint(Edge, bForward, FMath::Clamp((Along + Look) / E.Length, 0.f, 1.f));
	else
	{
		const float Over = Look - Remaining;
		Aim = Ci->LanePoint(NextEdge, bNextForward, FMath::Clamp((AGTACity::CorridorHalf * 0.5f + Over) / Ci->Edges[NextEdge].Length, 0.f, 1.f));
	}
	if (Remaining < 200.f)
	{
		Edge = NextEdge;
		bForward = bNextForward;
		NextEdge = INDEX_NONE;
	}
	float Desired = State == EGTANPCState::Flee ? 80.f : CruiseKmh;
	// NextEdge is consumed above (and reset to INDEX_NONE once taken), so only test the
	// turn when a successor edge is still pending -- indexing with INDEX_NONE asserts.
	const bool bTurning = Ci->Edges.IsValidIndex(NextEdge)
		&& FVector::DotProduct(Ci->LaneDir(NextEdge, bNextForward), Dir) < 0.7f;
	if (bTurning && Remaining < 2800.f) Desired = FMath::Min(Desired, 22.f);
	// traffic light: stop line at the corridor edge
	if (State != EGTANPCState::Flee && Remaining > AGTACity::CorridorHalf + 150.f && Remaining < AGTACity::CorridorHalf + 2600.f && !Ci->SignalGreenFor(EndNode, Dir))
	{
		const float ToLine = Remaining - AGTACity::CorridorHalf - 250.f;
		Desired = FMath::Min(Desired, FMath::Max(0.f, ToLine / 40.f));
		if (ToLine < 150.f) Desired = 0.f;
	}
	DriveTowards(Aim, Desired, Dt, true);
	if (State == EGTANPCState::Flee && StateTime > 20.f) SetState(EGTANPCState::Drive);
}

void AGTANPCController::TickPursuitDrive(float Dt)
{
	AGTAVehicle* V = MyVehicle();
	AGTAGameMode* M = GTA::Mode(this);
	AGTAPlayerCharacter* P = GTA::Player(this);
	AGTACity* Ci = City();
	if (!V || !M || !P) return;
	if (M->WantedLevel <= 0)
	{
		if (V->bSirenOn) V->ToggleSiren();
		// return to normal patrol traffic
		float T = 0.f;
		const int32 E = Ci ? Ci->NearestEdge(V->GetActorLocation(), &T) : INDEX_NONE;
		if (E != INDEX_NONE) StartDriving(V, E, FVector::DotProduct(V->GetActorForwardVector(), Ci->Edges[E].Dir) > 0.f, T);
		else SetState(EGTANPCState::Idle);
		return;
	}
	const float Now = GetWorld()->GetTimeSeconds();
	const bool bSeen = Now - M->LastSeenTime < 2.f;
	FVector Goal3 = bSeen ? P->GetActorLocation() : M->LastKnownPos;
	const float Dist = FVector::Dist2D(V->GetActorLocation(), Goal3);
	AGTAVehicle* PV = P->Vehicle;

	// target on foot and close: bail out and chase on foot
	if (bSeen && !PV && Dist < 1800.f && V->ForwardSpeed() < 600.f)
	{
		V->ClearInputs();
		V->bHandbrake = true;
		for (int32 i = V->Occupants.Num() - 1; i >= 0; --i)
		{
			AGTACharacter* O = V->Occupants[i];
			if (!O || O->bDead) continue;
			if (AGTANPCController* AIC = Cast<AGTANPCController>(O->GetController())) AIC->ExitVehicleAndFight();
		}
		return;
	}
	if (!bSeen && Dist < 2000.f)
	{
		// reached the last known position: search on foot at higher levels, otherwise circle the area
		Goal3 = M->LastKnownPos + FVector(FMath::Sin(Now * 0.2f + GetUniqueID()) * M->SearchRadius() * 0.5f, FMath::Cos(Now * 0.2f + GetUniqueID()) * M->SearchRadius() * 0.5f, 0.f);
	}
	FVector Aim = Goal3;
	float Desired = FMath::Clamp(Dist / 25.f, 35.f, 130.f);
	if (Ci && Dist > 6000.f)
	{
		// follow the road graph toward the target
		RouteTime -= Dt;
		if (RouteTime <= 0.f || Route.Num() == 0)
		{
			RouteTime = 2.f;
			Ci->FindRoute(Ci->NearestNode(V->GetActorLocation()), Ci->NearestNode(Goal3), Route);
		}
		while (Route.Num() > 1 && FVector::Dist2D(Ci->Nodes[Route[0]].Pos, V->GetActorLocation()) < 1200.f) Route.RemoveAt(0);
		if (Route.Num() > 0) Aim = Ci->Nodes[Route[0]].Pos;
	}
	else if (PV && bSeen)
	{
		// close pursuit: aim for the rear quarter (PIT) when the suspect is fast, ram when slow
		const FVector PF = PV->GetActorForwardVector();
		const float PSpeed = PV->GetVelocity().Size();
		if (PSpeed > 800.f) Aim = PV->GetActorLocation() - PF * 250.f + PV->GetActorRightVector() * ((GetUniqueID() & 1) ? 150.f : -150.f) + PV->GetVelocity() * 0.35f;
		else Aim = PV->GetActorLocation() + PV->GetVelocity() * 0.3f;
		Desired = FMath::Max(Desired, PSpeed * 0.036f + 15.f);
	}
	DriveTowards(Aim, Desired, Dt, Dist > 3000.f);
	if (bSeen && Dist < 2500.f && PV && PV->ForwardSpeed() < 100.f && V->ForwardSpeed() < 200.f)
	{
		// suspect stopped in a vehicle: officers get out and engage
		for (int32 i = V->Occupants.Num() - 1; i >= 0; --i)
		{
			AGTACharacter* O = V->Occupants[i];
			if (O && !O->bDead) { if (AGTANPCController* AIC = Cast<AGTANPCController>(O->GetController())) AIC->ExitVehicleAndFight(); }
		}
	}
}

// ------------------------------------------------------------------------------------------------ route following / taxi service

bool AGTANPCController::FollowRoute(const FVector& InGoal, float CruiseKmhIn, float Dt)
{
	AGTAVehicle* V = MyVehicle();
	AGTACity* Ci = City();
	if (!V || !Ci) return true;
	const FVector Pos = V->GetActorLocation();
	const float GoalDist = FVector::Dist2D(Pos, InGoal);
	if (GoalDist < 1500.f)
	{
		DriveTowards(InGoal, 0.f, Dt, true);
		return true;
	}
	RouteTime -= Dt;
	if (RouteTime <= 0.f || Route.Num() == 0)
	{
		RouteTime = 3.f;
		Ci->FindRoute(Ci->NearestNode(Pos), Ci->NearestNode(InGoal), Route);
	}
	while (Route.Num() > 0 && FVector::Dist2D(Ci->Nodes[Route[0]].Pos, Pos) < 1100.f) Route.RemoveAt(0);
	FVector Aim = InGoal;
	float Kmh = CruiseKmhIn;
	if (Route.Num() > 0)
	{
		const FVector N = Ci->Nodes[Route[0]].Pos;
		const FVector Dir = (N - Pos).GetSafeNormal2D();
		Aim = N + FVector(-Dir.Y, Dir.X, 0.f) * AGTACity::LaneOffset;
		if (FVector::Dist2D(N, Pos) < 2500.f && Route.Num() > 1) Kmh = FMath::Min(Kmh, 28.f);
	}
	else if (GoalDist < 4000.f) Kmh = FMath::Min(Kmh, 25.f);
	DriveTowards(Aim, Kmh, Dt, true);
	return false;
}

void AGTANPCController::StartTaxi(AGTAVehicle* V, const FVector& InGoal, bool bPickup)
{
	SetState(EGTANPCState::Taxi);
	Goal = InGoal;
	bTaxiPickup = bPickup;
	bTaxiArrived = false;
	Route.Reset();
	RouteTime = 0.f;
	if (V) V->bAIDriven = true;
}

void AGTANPCController::TickTaxi(float Dt)
{
	AGTAVehicle* V = MyVehicle();
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!V || !P) return;
	const bool bPlayerAboard = P->Vehicle == V && P->SeatIndex > 0;
	const float Now = GetWorld()->GetTimeSeconds();
	if (bTaxiPickup)
	{
		if (bPlayerAboard)
		{
			bTaxiPickup = false;
			bTaxiArrived = false;
			TaxiStartLoc = V->GetActorLocation();
			Goal = FVector::ZeroVector;
			Route.Reset();
			return;
		}
		Goal = P->IsInVehicle() ? Goal : P->GetActorLocation();
		if (FollowRoute(Goal, 50.f, Dt) && !bTaxiArrived)
		{
			bTaxiArrived = true;
			V->SetHorn(true);
			FTimerHandle H;
			GetWorldTimerManager().SetTimer(H, FTimerDelegate::CreateWeakLambda(V, [V]() { V->SetHorn(false); }), 0.5f, false);
			GTA::Notify(this, TEXT("Your cab is here — get in a rear seat (F)."), 4.f);
		}
		if (StateTime > 120.f && !bTaxiArrived) { StartWander(); }
		return;
	}
	// trip: drive to the player's waypoint
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetWorld()->GetFirstPlayerController());
	if (!bPlayerAboard)
	{
		// passenger left: back to regular traffic after a moment
		if (StateTime > 3.f)
		{
			float T = 0.f;
			AGTACity* Ci = City();
			const int32 E = Ci ? Ci->NearestEdge(V->GetActorLocation(), &T) : INDEX_NONE;
			if (E != INDEX_NONE) StartDriving(V, E, FVector::DotProduct(V->GetActorForwardVector(), Ci->Edges[E].Dir) > 0.f, T);
		}
		DriveTowards(V->GetActorLocation(), 0.f, Dt, false);
		return;
	}
	StateTime = 0.f;
	if (!PC || !PC->bHasWaypoint)
	{
		DriveTowards(V->GetActorLocation(), 0.f, Dt, false);
		if (FMath::Fmod(Now, 6.f) < Dt) GTA::Notify(this, TEXT("Driver: \"Where to?\" — set a waypoint on the map (M)."), 3.f);
		return;
	}
	Goal = PC->Waypoint;
	// hold Space to skip the trip
	if (PC->IsInputKeyDown(EKeys::SpaceBar) && FVector::Dist2D(V->GetActorLocation(), Goal) > 3000.f)
	{
		AGTACity* Ci = City();
		float T = 0.f;
		const int32 E = Ci ? Ci->NearestEdge(Goal, &T) : INDEX_NONE;
		if (E != INDEX_NONE)
		{
			const FVector L = Ci->LanePoint(E, true, FMath::Clamp(T, 0.15f, 0.85f)) + FVector(0, 0, V->BodyCenterZ + 20.f);
			V->SetActorLocationAndRotation(L, Ci->LaneDir(E, true).Rotation(), false, nullptr, ETeleportType::ResetPhysics);
			Route.Reset();
		}
	}
	if (!bTaxiArrived && FollowRoute(Goal, 55.f, Dt))
	{
		bTaxiArrived = true;
		const float Km = FVector::Dist2D(TaxiStartLoc, V->GetActorLocation()) / 100000.f;
		const int32 Fare = FMath::Max(20, FMath::RoundToInt(20.f + Km * 60.f));
		GTA::AddMoney(this, -FMath::Min(Fare, GTA::Money(this)));
		GTA::Notify(this, FString::Printf(TEXT("Arrived. Fare: $%d"), Fare), 4.f);
		PC->bHasWaypoint = false;
	}
	else if (bTaxiArrived) DriveTowards(V->GetActorLocation(), 0.f, Dt, false);
}

// Wanted system: witnesses, police line of sight, pursuit vs search, escape.
#include "Core/GTAGameMode.h"
#include "Core/GTAGame.h"
#include "Player/GTAPlayerCharacter.h"
#include "AI/GTANPCController.h"
#include "World/GTAPopulation.h"
#include "World/GTAEnvironment.h"
#include "Vehicles/GTAVehicle.h"
#include "EngineUtils.h"

static const float GTAHeatThreshold[6] = { 0.f, 100.f, 300.f, 600.f, 1000.f, 1600.f };

float AGTAGameMode::CrimeHeat(EGTACrime C)
{
	switch (C)
	{
	case EGTACrime::Assault: return 40.f;
	case EGTACrime::Murder: return 110.f;
	case EGTACrime::Gunfire: return 60.f;
	case EGTACrime::AttackCop: return 130.f;
	case EGTACrime::KillCop: return 240.f;
	case EGTACrime::CarJack: return 70.f;
	case EGTACrime::StealCopCar: return 130.f;
	case EGTACrime::Explosion: return 150.f;
	case EGTACrime::VehicleHit: return 45.f;
	case EGTACrime::DestroyCopCar: return 220.f;
	case EGTACrime::Robbery: return 120.f;
	}
	return 40.f;
}

int32 AGTAGameMode::CrimeMinLevel(EGTACrime C)
{
	switch (C)
	{
	case EGTACrime::KillCop:
	case EGTACrime::DestroyCopCar: return 2;
	case EGTACrime::Murder:
	case EGTACrime::Gunfire:
	case EGTACrime::AttackCop:
	case EGTACrime::StealCopCar:
	case EGTACrime::Explosion:
	case EGTACrime::Robbery:
	case EGTACrime::CarJack: return 1;
	default: return 0;
	}
}

float AGTAGameMode::PoliceSightRange() const
{
	float R = 5500.f + 900.f * WantedLevel;
	if (Env) R *= Env->VisibilityFactor();
	if (WantedState == EGTAWantedState::Search)
	{
		// changing / abandoning the identified vehicle makes recognition harder (not an instant clear)
		AGTAPlayerCharacter* P = GTA::Player(this);
		AGTAVehicle* Now = P ? P->Vehicle.Get() : nullptr;
		if (LastSeenVehicle.IsValid() && Now != LastSeenVehicle.Get()) R *= 0.6f;
		if (P && P->bStealth && !P->IsInVehicle()) R *= 0.75f;
	}
	return R;
}

static bool GTAHasLOS(UWorld* W, const FVector& From, const FVector& To, const AActor* IgnoreA, const AActor* IgnoreB)
{
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAWitness), false);
	if (IgnoreA) Q.AddIgnoredActor(IgnoreA);
	if (IgnoreB) Q.AddIgnoredActor(IgnoreB);
	if (const AGTACharacter* C = Cast<AGTACharacter>(IgnoreB)) { if (C->Vehicle) Q.AddIgnoredActor(C->Vehicle); }
	if (const AGTACharacter* C = Cast<AGTACharacter>(IgnoreA)) { if (C->Vehicle) Q.AddIgnoredActor(C->Vehicle); }
	FHitResult H;
	return !W->LineTraceSingleByChannel(H, From, To, ECC_Visibility, Q);
}

void AGTAGameMode::ReportCrime(AGTACharacter* Offender, EGTACrime Crime, const FVector& Loc, AActor* Victim)
{
	if (!Offender || !Offender->IsPlayerCharacter() || bRespawning) return;
	UWorld* W = GetWorld();
	const float Now = W->GetTimeSeconds();
	if (Crime == EGTACrime::AttackCop || Crime == EGTACrime::KillCop || Crime == EGTACrime::Gunfire) LastResistTime = Now;

	// police that are already tracking the player see everything
	if (WantedLevel > 0 && Now - LastSeenTime < 1.5f)
	{
		RegisterCrime(Crime, Loc, true);
		return;
	}

	float HearRadius = 0.f;
	if (Crime == EGTACrime::Gunfire)
	{
		const FGTAWeaponSlot* S = Offender->CurrentSlotPtr();
		HearRadius = (S && S->HasMod(EGTAWeaponMod::Suppressor)) ? 900.f : 9000.f;
	}
	else if (Crime == EGTACrime::Explosion) HearRadius = 14000.f;

	const float Sight = PoliceSightRange();
	bool bPoliceSaw = false, bPoliceHeard = false;
	AGTACharacter* Caller = nullptr;
	float CallerDist = 1e9f;
	for (TActorIterator<AGTACharacter> It(W); It; ++It)
	{
		AGTACharacter* C = *It;
		if (C == Offender || C == Victim || C->bDead || C->IsKnockedDown()) continue;
		const FVector Eye = C->GetActorLocation() + FVector(0, 0, 60.f);
		const float D = FVector::Dist(Eye, Loc);
		if (C->IsPolice())
		{
			if (D < Sight && GTAHasLOS(W, Eye, Loc + FVector(0, 0, 40.f), C, Offender)) { bPoliceSaw = true; break; }
			if (D < HearRadius) bPoliceHeard = true;
			continue;
		}
		if (C->PedRole == EGTAPedRole::Gang) continue;   // gangs never call the police
		const float WitnessRange = FMath::Max(3500.f, HearRadius * 0.5f);
		if (D < WitnessRange && D < CallerDist && GTAHasLOS(W, Eye, Loc + FVector(0, 0, 40.f), C, Offender))
		{
			Caller = C;
			CallerDist = D;
		}
	}

	if (bPoliceSaw) { CrimesWitnessed++; RegisterCrime(Crime, Loc, true); return; }
	if (bPoliceHeard) { CrimesWitnessed++; RegisterCrime(Crime, Loc, false); return; }
	if (!Caller)
	{
		// gunshots / explosions are reported indirectly by somebody out of sight after a longer delay
		if (HearRadius > 5000.f)
		{
			FGTAPendingReport R;
			R.Crime = Crime;
			R.Loc = Loc;
			R.Due = Now + FMath::FRandRange(12.f, 18.f);
			PendingReports.Add(R);
		}
		else CrimesUnwitnessed++;
		return;
	}
	// one pending report per witness; upgrade its severity
	for (FGTAPendingReport& R : PendingReports)
	{
		if (R.Witness.Get() == Caller)
		{
			if (CrimeHeat(Crime) > CrimeHeat(R.Crime)) R.Crime = Crime;
			R.Loc = Loc;
			return;
		}
	}
	FGTAPendingReport R;
	R.Crime = Crime;
	R.Loc = Loc;
	R.Witness = Caller;
	R.Due = Now + FMath::FRandRange(5.f, 8.f);
	PendingReports.Add(R);
	CrimesWitnessed++;
	if (AGTANPCController* AIC = Cast<AGTANPCController>(Caller->GetController())) AIC->StartReportingCrime(Loc, Offender);
}

void AGTAGameMode::TickReports(float Dt)
{
	const float Now = GetWorld()->GetTimeSeconds();
	for (int32 i = PendingReports.Num() - 1; i >= 0; --i)
	{
		FGTAPendingReport& R = PendingReports[i];
		const bool bHadWitness = !R.Witness.IsExplicitlyNull();
		if (bHadWitness && (!R.Witness.IsValid() || R.Witness->bDead || R.Witness->IsKnockedDown()))
		{
			PendingReports.RemoveAt(i);   // report prevented
			continue;
		}
		if (Now >= R.Due)
		{
			const EGTACrime C = R.Crime;
			const FVector L = R.Loc;
			PendingReports.RemoveAt(i);
			RegisterCrime(C, L, false);
			Notify(TEXT("A witness called Halcyon PD."), 3.f);
		}
	}
}

void AGTAGameMode::RegisterCrime(EGTACrime Crime, const FVector& Loc, bool bSeenByPolice)
{
	if (bRespawning) return;
	UGTAGameInstance* GI = GTA::Instance(this);
	const float Now = GetWorld()->GetTimeSeconds();
	LastCrimeTime = Now;
	Heat += CrimeHeat(Crime);
	int32 L = 0;
	for (int32 i = 5; i >= 1; --i) { if (Heat >= GTAHeatThreshold[i]) { L = i; break; } }
	L = FMath::Max3(L, CrimeMinLevel(Crime), WantedLevel);
	if (bSeenByPolice) L = FMath::Max(L, 1);
	if (L == 0) return;
	const int32 Old = WantedLevel;
	WantedLevel = FMath::Clamp(L, 0, 5);
	Heat = FMath::Max(Heat, GTAHeatThreshold[WantedLevel]);
	if (bSeenByPolice)
	{
		LastSeenTime = Now;
		LastKnownPos = Loc;
		EscapeProgress = 0.f;
		WantedState = EGTAWantedState::Pursuit;
		if (AGTAPlayerCharacter* P = GTA::Player(this)) LastSeenVehicle = P->Vehicle.Get();
	}
	else if (WantedState != EGTAWantedState::Pursuit)
	{
		LastKnownPos = Loc;
		WantedState = EGTAWantedState::Search;
	}
	if (WantedLevel != Old && Population) Population->OnWantedChanged(Old, WantedLevel);
	(void)GI;
}

void AGTAGameMode::SetWantedLevel(int32 Level, bool bPursuit)
{
	const int32 Old = WantedLevel;
	WantedLevel = FMath::Clamp(Level, 0, 5);
	if (WantedLevel == 0) { ClearWanted(); return; }
	Heat = GTAHeatThreshold[WantedLevel];
	if (AGTAPlayerCharacter* P = GTA::Player(this))
	{
		LastKnownPos = P->GetActorLocation();
		LastSeenVehicle = P->Vehicle.Get();
	}
	if (bPursuit)
	{
		LastSeenTime = GetWorld()->GetTimeSeconds();
		WantedState = EGTAWantedState::Pursuit;
	}
	else WantedState = EGTAWantedState::Search;
	EscapeProgress = 0.f;
	if (Population && Old != WantedLevel) Population->OnWantedChanged(Old, WantedLevel);
}

void AGTAGameMode::ClearWanted()
{
	const int32 Old = WantedLevel;
	WantedLevel = 0;
	Heat = 0.f;
	WantedState = EGTAWantedState::None;
	EscapeProgress = 0.f;
	PendingReports.Reset();
	LastSeenVehicle = nullptr;
	if (Population && Old != 0) Population->OnWantedChanged(Old, 0);
}

void AGTAGameMode::PlayerSpotted(const FVector& Where)
{
	if (WantedLevel <= 0) return;
	LastSeenTime = GetWorld()->GetTimeSeconds();
	LastKnownPos = Where;
	EscapeProgress = 0.f;
	if (AGTAPlayerCharacter* P = GTA::Player(this)) LastSeenVehicle = P->Vehicle.Get();
}

void AGTAGameMode::TickWanted(float Dt)
{
	if (WantedLevel <= 0)
	{
		WantedState = EGTAWantedState::None;
		Heat = FMath::Max(0.f, Heat - 15.f * Dt);
		return;
	}
	const float Now = GetWorld()->GetTimeSeconds();
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!P || bRespawning) return;
	if (Now - LastSeenTime < 1.25f)
	{
		WantedState = EGTAWantedState::Pursuit;
		EscapeProgress = 0.f;
		return;
	}
	WantedState = EGTAWantedState::Search;
	float Rate = 1.f;
	if (FVector::Dist2D(P->GetActorLocation(), LastKnownPos) > SearchRadius()) Rate *= 1.75f;
	if (LastSeenVehicle.IsValid() && P->Vehicle != LastSeenVehicle.Get()) Rate *= 1.2f;
	EscapeProgress += Dt * Rate;
	if (EscapeProgress >= EscapeRequired())
	{
		ClearWanted();
		Notify(TEXT("You lost the police."), 4.f);
	}
}

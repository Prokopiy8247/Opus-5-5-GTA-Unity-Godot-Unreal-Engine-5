#include "Core/GTAGameMode.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameInstance.h"
#include "Player/GTAPlayerCharacter.h"
#include "Player/GTAPlayerController.h"
#include "UI/GTAHUD.h"
#include "World/GTACity.h"
#include "World/GTAEnvironment.h"
#include "World/GTAFX.h"
#include "World/GTAPopulation.h"
#include "World/GTAWildlife.h"
#include "Core/GTATestDirector.h"
#include "Vehicles/GTAVehicle.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerStart.h"
#include "Components/CapsuleComponent.h"
#include "Engine/EngineTypes.h"
#include "Engine/OverlapResult.h"
#include "Camera/PlayerCameraManager.h"


AGTAGameMode::AGTAGameMode()
{
	PrimaryActorTick.bCanEverTick = true;
	DefaultPawnClass = AGTAPlayerCharacter::StaticClass();
	PlayerControllerClass = AGTAPlayerController::StaticClass();
	HUDClass = AGTAHUD::StaticClass();
}

void AGTAGameMode::SpawnServices()
{
	UWorld* W = GetWorld();
	for (TActorIterator<AGTACity> It(W); It; ++It) { City = *It; break; }
	if (!City)
	{
		City = W->SpawnActor<AGTACity>(AGTACity::StaticClass(), FTransform::Identity);
	}
	for (TActorIterator<AGTAEnvironment> It(W); It; ++It) { Env = *It; break; }
	if (!Env) Env = W->SpawnActor<AGTAEnvironment>(AGTAEnvironment::StaticClass(), FTransform::Identity);
	FX = W->SpawnActor<AGTAFX>(AGTAFX::StaticClass(), FTransform::Identity);
	Population = W->SpawnActor<AGTAPopulation>(AGTAPopulation::StaticClass(), FTransform::Identity);
	W->SpawnActor<AGTAWildlife>(AGTAWildlife::StaticClass(), FTransform::Identity);
	if (UGTAGameInstance* GI = GTA::Instance(this))
	{
		if (GI->bTestMode) TestDirector = W->SpawnActor<AGTATestDirector>(AGTATestDirector::StaticClass(), FTransform::Identity);
		if (Env)
		{
			Env->SetTimeOfDay(GI->Profile.TimeOfDay);
			Env->SetWeather((EGTAWeather)GI->Profile.Weather, true);
		}
	}
}

void AGTAGameMode::StartPlay()
{
	SpawnServices();
	Super::StartPlay();
	UE_LOG(LogGTA, Log, TEXT("Port Halcyon started. City=%s"), City ? *City->GetName() : TEXT("none"));
}

AActor* AGTAGameMode::ChoosePlayerStart_Implementation(AController* Player)
{
	for (TActorIterator<APlayerStart> It(GetWorld()); It; ++It) return *It;
	return Super::ChoosePlayerStart_Implementation(Player);
}

void AGTAGameMode::RestartPlayer(AController* NewPlayer)
{
	Super::RestartPlayer(NewPlayer);
	AGTAPlayerCharacter* P = Cast<AGTAPlayerCharacter>(NewPlayer ? NewPlayer->GetPawn() : nullptr);
	if (P)
	{
		P->LoadFromProfile();
		if (UGTAGameInstance* GI = GTA::Instance(this))
			if (!GI->Profile.bHasPlayerTransform)
			{
				P->SetActorRotation(FRotator::ZeroRotator);
				NewPlayer->SetControlRotation(FRotator(-12.f,0.f,0.f));
			}
		// The player start is a fixed point in a generated layout, and traffic/parked cars spawn
		// around it at runtime. If the pawn ends up overlapping anything, the third-person camera
		// boom has nowhere to go and the whole frame fills with the inside of that object, so nudge
		// the pawn upward until it is clear.
		UWorld* W = GetWorld();
		UCapsuleComponent* Cap = P->GetCapsuleComponent();
		if (W && Cap)
		{
			for (int32 Try = 0; Try < 12; ++Try)
			{
				TArray<FOverlapResult> Overlaps;
				FCollisionQueryParams Q(SCENE_QUERY_STAT(GTASpawnOverlap), false, P);
				const bool bBlocked = W->OverlapMultiByChannel(Overlaps, Cap->GetComponentLocation(),
					Cap->GetComponentQuat(), ECC_Pawn, FCollisionShape::MakeCapsule(
						Cap->GetScaledCapsuleRadius() * 1.1f, Cap->GetScaledCapsuleHalfHeight()), Q);
				if (!bBlocked) break;
				P->AddActorWorldOffset(FVector(0.f, 0.f, 120.f), false);
				UE_LOG(LogGTA, Warning, TEXT("spawn overlap: lifted player to %s (try %d)"),
					*P->GetActorLocation().ToString(), Try);
			}
		}	}
}

void AGTAGameMode::Tick(float Dt)
{
	Super::Tick(Dt);
	TickReports(Dt);
	TickWanted(Dt);
	const float Now = GetWorld()->GetTimeSeconds();
	Notes.RemoveAll([Now](const FGTANotification& N) { return N.Until < Now; });
	if (bRespawning && Now >= RespawnAt) DoRespawn();
}

void AGTAGameMode::Notify(const FString& Msg, float Seconds)
{
	FGTANotification N;
	N.Text = Msg;
	N.Until = GetWorld()->GetTimeSeconds() + Seconds;
	Notes.Add(N);
	if (Notes.Num() > 5) Notes.RemoveAt(0);
	UE_LOG(LogGTA, Log, TEXT("NOTIFY: %s"), *Msg);
}

// ------------------------------------------------------------------------------------------------ respawn

void AGTAGameMode::OnPlayerWasted()
{
	if (bRespawning) return;
	bRespawning = true;
	bRespawnBusted = false;
	RespawnAt = GetWorld()->GetTimeSeconds() + 4.5f;
	ShowBigMessage(TEXT("WASTED"), 4.5f);
	if (UGTAGameInstance* GI = GTA::Instance(this)) GI->Profile.Deaths++;
	if (APlayerController* PC = GetWorld()->GetFirstPlayerController())
	{
		if (PC->PlayerCameraManager) PC->PlayerCameraManager->StartCameraFade(0.f, 1.f, 4.0f, FLinearColor::Black, false, true);
	}
	GetWorldSettings()->SetTimeDilation(0.35f);
}

void AGTAGameMode::OnPlayerBusted()
{
	if (bRespawning) return;
	bRespawning = true;
	bRespawnBusted = true;
	RespawnAt = GetWorld()->GetTimeSeconds() + 4.f;
	ShowBigMessage(TEXT("BUSTED"), 4.f);
	if (UGTAGameInstance* GI = GTA::Instance(this)) GI->Profile.Busted++;
	if (AGTAPlayerCharacter* P = GTA::Player(this))
	{
		P->SetHandsUp(true);
		P->bInvulnerable = true;
	}
	if (APlayerController* PC = GetWorld()->GetFirstPlayerController())
	{
		if (PC->PlayerCameraManager) PC->PlayerCameraManager->StartCameraFade(0.f, 1.f, 3.6f, FLinearColor::Black, false, true);
	}
}

void AGTAGameMode::DoRespawn()
{
	bRespawning = false;
	GetWorldSettings()->SetTimeDilation(1.f);
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!P) return;
	FTransform T = P->GetActorTransform();
	if (City) T = bRespawnBusted ? City->PoliceRespawn : City->HospitalRespawn;
	if (P->Vehicle) P->Vehicle->RemoveOccupant(P);
	P->Revive();
	P->SetHandsUp(false);
	P->bInvulnerable = false;
	P->TeleportTo(T.GetLocation() + FVector(0, 0, 100.f), T.Rotator(), false, true);
	if (AController* C = P->GetController()) C->SetControlRotation(T.Rotator());
	if (UGTAGameInstance* GI = GTA::Instance(this))
	{
		const int32 Fee = FMath::Min(GI->Profile.Money, FMath::Max(200, GI->Profile.Money / 10));
		GI->Profile.Money -= Fee;
		if (bRespawnBusted)
		{
			// confiscate firearms, keep melee
			P->Weapons.RemoveAll([](const FGTAWeaponSlot& S) { return FGTAData::Weapon(S.Id).Cat != EGTAWeaponCat::Melee; });
			P->CurrentSlot = 0;
			P->UpdateWeaponVisual();
			Notify(FString::Printf(TEXT("Released from Halcyon PD. Fine: $%d. Firearms confiscated."), Fee), 6.f);
		}
		else
		{
			Notify(FString::Printf(TEXT("Discharged from St. Brine Hospital. Bill: $%d."), Fee), 6.f);
		}
	}
	ClearWanted();
	if (Population) Population->OnPlayerRespawned();
	if (APlayerController* PC = GetWorld()->GetFirstPlayerController())
	{
		if (PC->PlayerCameraManager) PC->PlayerCameraManager->StartCameraFade(1.f, 0.f, 1.5f, FLinearColor::Black, false, false);
	}
}

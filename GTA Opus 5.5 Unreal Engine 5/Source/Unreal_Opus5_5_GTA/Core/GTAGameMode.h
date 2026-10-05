// Game mode: owns the world services and the wanted / respawn rules.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "Core/GTATypes.h"
#include "GTAGameMode.generated.h"

class AGTACity;
class AGTAEnvironment;
class AGTAFX;
class AGTAPopulation;
class AGTACharacter;
class AGTAVehicle;
class AGTATestDirector;

struct FGTANotification
{
	FString Text;
	float Until = 0.f;
};

struct FGTAPendingReport
{
	EGTACrime Crime = EGTACrime::Assault;
	FVector Loc = FVector::ZeroVector;
	TWeakObjectPtr<AGTACharacter> Witness;
	float Due = 0.f;
};

enum class EGTAWantedState : uint8 { None, Pursuit, Search };

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAGameMode : public AGameModeBase
{
	GENERATED_BODY()
public:
	AGTAGameMode();
	virtual void StartPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual AActor* ChoosePlayerStart_Implementation(AController* Player) override;
	virtual void RestartPlayer(AController* NewPlayer) override;

	UPROPERTY() TObjectPtr<AGTACity> City;
	UPROPERTY() TObjectPtr<AGTAEnvironment> Env;
	UPROPERTY() TObjectPtr<AGTAFX> FX;
	UPROPERTY() TObjectPtr<AGTAPopulation> Population;
	UPROPERTY() TObjectPtr<AGTATestDirector> TestDirector;

	// ---------------------------------------------------------------- wanted
	int32 WantedLevel = 0;
	float Heat = 0.f;
	EGTAWantedState WantedState = EGTAWantedState::None;
	FVector LastKnownPos = FVector::ZeroVector;
	float EscapeProgress = 0.f;
	float LastSeenTime = -100.f;
	float LastCrimeTime = -100.f;
	float LastResistTime = -100.f;
	TWeakObjectPtr<AGTAVehicle> LastSeenVehicle;
	TArray<FGTAPendingReport> PendingReports;

	void ReportCrime(AGTACharacter* Offender, EGTACrime Crime, const FVector& Loc, AActor* Victim);
	void RegisterCrime(EGTACrime Crime, const FVector& Loc, bool bSeenByPolice);
	void SetWantedLevel(int32 Level, bool bPursuit = true);
	void ClearWanted();
	/** Police (officer, vehicle, helicopter) currently has eyes on the player. */
	void PlayerSpotted(const FVector& Where);
	float EscapeRequired() const { return 8.f + 6.f * WantedLevel; }
	float SearchRadius() const { return WantedLevel > 0 ? 6000.f + 3000.f * WantedLevel : 0.f; }
	bool IsPursuit() const { return WantedState == EGTAWantedState::Pursuit; }
	/** Detection range of police against the player (smaller after changing vehicle while unseen). */
	float PoliceSightRange() const;
	int32 PendingReportCount() const { return PendingReports.Num(); }

	// ---------------------------------------------------------------- death / arrest
	void OnPlayerWasted();
	void OnPlayerBusted();
	bool bRespawning = false;
	bool bRespawnBusted = false;
	float RespawnAt = 0.f;
	FString BigMessage;
	float BigMessageUntil = 0.f;
	void ShowBigMessage(const FString& Msg, float Seconds) { BigMessage = Msg; BigMessageUntil = GetWorld()->GetTimeSeconds() + Seconds; }

	// ---------------------------------------------------------------- notifications
	TArray<FGTANotification> Notes;
	void Notify(const FString& Msg, float Seconds);

	// ---------------------------------------------------------------- statistics for QA overlay
	int32 CrimesWitnessed = 0;
	int32 CrimesUnwitnessed = 0;

private:
	void TickWanted(float Dt);
	void TickReports(float Dt);
	void DoRespawn();
	void SpawnServices();
	static float CrimeHeat(EGTACrime C);
	static int32 CrimeMinLevel(EGTACrime C);
};

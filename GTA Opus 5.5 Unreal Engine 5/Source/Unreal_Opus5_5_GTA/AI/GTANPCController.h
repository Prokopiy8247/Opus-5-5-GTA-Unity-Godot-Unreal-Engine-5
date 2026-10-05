// NPC brain: pedestrians, witnesses, police (foot / vehicle / air), gangs, shopkeepers and traffic drivers.
#pragma once

#include "CoreMinimal.h"
#include "AIController.h"
#include "Core/GTATypes.h"
#include "GTANPCController.generated.h"

class AGTACharacter;
class AGTAVehicle;
class AGTACity;

UENUM()
enum class EGTANPCState : uint8
{
	Idle, Wander, Flee, Cower, HandsUp, ReportCrime, Fight, Arrest, Investigate, Search,
	Drive, PursuitDrive, Passenger, Guard, Taxi, Dead
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTANPCController : public AAIController
{
	GENERATED_BODY()
public:
	AGTANPCController();
	virtual void OnPossess(APawn* InPawn) override;
	virtual void Tick(float DeltaSeconds) override;

	// ---------------------------------------------------------------- events from the world
	bool IsAlerted() const;
	void OnDamaged(AActor* Attacker, float Damage);
	void OnPawnDied();
	void OnNoise(const FVector& Loc, float Radius, AActor* NoiseMaker, bool bThreat);
	void OnAimedAt(AActor* Aimer);
	void StartReportingCrime(const FVector& Loc, AActor* Offender);
	void OnVehicleJacked(AActor* Jacker);

	// ---------------------------------------------------------------- orders from the population manager
	void SetState(EGTANPCState S);
	void StartWander();
	void StartGuard(const FVector& Post, float Yaw);
	void StartDriving(AGTAVehicle* V, int32 InEdge, bool bInForward, float InAlpha);
	void StartPursuit(AGTAVehicle* V);
	void StartFight(AActor* InTarget);
	void StartInvestigate(const FVector& L);
	void ExitVehicleAndFight();
	void StartTaxi(AGTAVehicle* V, const FVector& InGoal, bool bPickup);
	bool bTaxiPickup = true;
	bool bTaxiArrived = false;
	float TaxiFareStart = 0.f;
	FVector TaxiStartLoc = FVector::ZeroVector;

	EGTANPCState State = EGTANPCState::Idle;
	TWeakObjectPtr<AActor> Target;
	FVector Goal = FVector::ZeroVector;
	FVector ThreatLoc = FVector::ZeroVector;
	float StateTime = 0.f;
	float Bravery = 0.3f;        // chance to fight back instead of fleeing
	bool bDespawnable = true;    // population may recycle this NPC
	bool bIsDispatchUnit = false;

	// driving state (traffic / pursuit)
	int32 Edge = INDEX_NONE;
	bool bForward = true;
	int32 NextEdge = INDEX_NONE;
	float CruiseKmh = 42.f;
	float StuckTime = 0.f;
	float ReverseUntil = 0.f;
	float HonkCooldown = 0.f;
	TArray<int32> Route;         // node path for pursuit / navigation
	float RouteTime = 0.f;

	AGTACharacter* Me() const;
	AGTAVehicle* MyVehicle() const;
	AGTACity* City() const;

protected:
	// on foot
	void TickFoot(float Dt);
	void TickWander(float Dt);
	void TickFlee(float Dt);
	void TickFight(float Dt);
	void TickArrest(float Dt);
	void TickSearch(float Dt);
	void TickPerception(float Dt);
	void MoveTowards(const FVector& L, float Accept, bool bRun);
	void StopMoving();
	void AimAndShoot(AActor* T, float Dt);
	bool CanSee(const AActor* T, float Range) const;
	AActor* PickTarget() const;

	// driving
	void TickDrive(float Dt);
	void TickPursuitDrive(float Dt);
	void TickTaxi(float Dt);
	bool FollowRoute(const FVector& InGoal, float CruiseKmhIn, float Dt);
	void DriveTowards(const FVector& Dest, float DesiredKmh, float Dt, bool bAvoid);
	float ObstacleDistanceAhead(float Range) const;

	float PerceptionTimer = 0.f;
	float RepathTimer = 0.f;
	FVector LastMoveGoal = FVector(1e9f);
	bool bDirectMove = false;
	float BurstTimer = 0.f;
	bool bBurstOn = false;
	float RepositionTimer = 0.f;
	FVector RepositionGoal = FVector::ZeroVector;
	float ArrestTimer = 0.f;
	float ReportUntil = 0.f;
	bool bPhoning = false;
	int32 WanderEdge = INDEX_NONE;
	bool bWanderLeft = false;
	bool bWanderToB = true;
	float IdleUntil = 0.f;
	float LastSeenTargetTime = -100.f;
	FVector LastSeenTargetLoc = FVector::ZeroVector;
	FRandomStream Rand;
};

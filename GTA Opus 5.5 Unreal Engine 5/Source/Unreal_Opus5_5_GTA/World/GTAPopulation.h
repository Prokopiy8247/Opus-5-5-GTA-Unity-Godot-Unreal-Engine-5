// Population manager: pedestrians, traffic, parked vehicles, police dispatch and AI simulation tiers.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/GTATypes.h"
#include "GTAPopulation.generated.h"

class AGTACharacter;
class AGTAVehicle;
class AGTACity;

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAPopulation : public AActor
{
	GENERATED_BODY()
public:
	AGTAPopulation();
	virtual void Tick(float DeltaSeconds) override;

	// events
	void OnWantedChanged(int32 OldLevel, int32 NewLevel);
	void OnPlayerRespawned();
	void OnNoise(const FVector& Loc, float Radius, AActor* NoiseMaker, bool bThreat);
	void OnPedKilled(AGTACharacter* Victim);

	// spawning helpers (also used by the admin menu / test director)
	AGTACharacter* SpawnPed(const FVector& Loc, float Yaw, EGTAPedRole InRole, int32 Seed = -1);
	AGTAVehicle* SpawnTrafficVehicle(EGTAVehicle Id, int32 Edge, bool bForward, float Alpha, bool bWithDriver);
	AGTAVehicle* SpawnPoliceUnit(const FVector& Near, bool bTactical);
	AGTAVehicle* SpawnPoliceHeli();
	void SpawnRoadblock();
	void SpawnFootPolice(const FVector& Near, int32 Count);
	void ClearPolice();
	void ClearAll();
	void ArmPolice(AGTACharacter* C, int32 Level, bool bTactical);
	AGTAVehicle* CallTaxi(const FVector& Pickup);
	UPROPERTY() TObjectPtr<AGTAVehicle> ActiveTaxi;

	UPROPERTY() TArray<TObjectPtr<AGTACharacter>> Peds;
	UPROPERTY() TArray<TObjectPtr<AGTAVehicle>> Traffic;
	UPROPERTY() TArray<TObjectPtr<AGTAVehicle>> Parked;
	UPROPERTY() TArray<TObjectPtr<AGTAVehicle>> PoliceVehicles;
	UPROPERTY() TArray<TObjectPtr<AGTACharacter>> PoliceUnits;
	UPROPERTY() TArray<TObjectPtr<AGTAVehicle>> FixedVehicles;   // boats / aircraft at the marina and airfield

	int32 TargetPeds = 34;
	int32 TargetTraffic = 20;
	int32 PoliceKilled = 0;

protected:
	virtual void BeginPlay() override;

private:
	void TickPeds(float Dt);
	void TickTraffic(float Dt);
	void TickParked(float Dt);
	void TickFixedVehicles();
	void TickDispatch(float Dt);
	void TickSimTiers();
	bool IsVisibleToPlayer(const FVector& L) const;
	FVector PlayerLoc() const;
	EGTAVehicle RandomTrafficType();
	AGTACity* City() const;
	void DestroyPed(AGTACharacter* C);
	void DestroyVehicle(AGTAVehicle* V);
	FRandomStream Rand;
	float PedTimer = 0.f;
	float TrafficTimer = 0.f;
	float ParkedTimer = 0.f;
	float DispatchTimer = 0.f;
	float TierTimer = 0.f;
	float RoadblockTimer = 0.f;
	int32 SpawnSerial = 0;
	TSet<int32> ParkedSpotsUsed;
	TMap<TObjectPtr<AGTAVehicle>, int32> ParkedSpotOf;
};

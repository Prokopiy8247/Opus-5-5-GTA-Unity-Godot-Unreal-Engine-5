// Persistent player profile: money, skills, appearance, weapons, garage, settings, save/load.
#pragma once

#include "CoreMinimal.h"
#include "Engine/GameInstance.h"
#include "GameFramework/SaveGame.h"
#include "Core/GTATypes.h"
#include "GTAGameInstance.generated.h"

USTRUCT()
struct FGTAStoredVehicle
{
	GENERATED_BODY()
	UPROPERTY() EGTAVehicle Id = EGTAVehicle::Sedan;
	UPROPERTY() FGTAVehicleMods Mods;
	UPROPERTY() int32 Garage = 0;
};

USTRUCT()
struct FGTAProfile
{
	GENERATED_BODY()
	UPROPERTY() int32 Money = 2500;
	UPROPERTY() FTransform PlayerTransform = FTransform::Identity;
	UPROPERTY() bool bHasPlayerTransform = false;
	UPROPERTY() float SavedMouseSensitivity = 1.f;
	UPROPERTY() bool bSavedInvertY = false;
	UPROPERTY() bool bSavedShowFPS = false;
	UPROPERTY() TArray<float> Skills;
	UPROPERTY() FGTAAppearance Appearance;
	UPROPERTY() TArray<FGTAWeaponSlot> Weapons;
	UPROPERTY() TArray<FGTAStoredVehicle> Garage;
	UPROPERTY() TArray<int32> OwnedSafehouses;
	UPROPERTY() int32 LastSafehouse = 0;
	UPROPERTY() float TimeOfDay = 9.5f;
	UPROPERTY() uint8 Weather = 0;
	UPROPERTY() float Health = 100.f;
	UPROPERTY() float Armor = 0.f;
	UPROPERTY() bool bHasParachute = false;
	UPROPERTY() int32 StuntJumpsDone = 0;
	UPROPERTY() int32 RangeBestScore = 0;
	UPROPERTY() float BestRaceTime = 0.f;
	UPROPERTY() int32 Kills = 0;
	UPROPERTY() int32 Deaths = 0;
	UPROPERTY() int32 Busted = 0;
	UPROPERTY() float DistanceDrivenKm = 0.f;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTASaveGame : public USaveGame
{
	GENERATED_BODY()
public:
	UPROPERTY() FGTAProfile Profile;
	UPROPERTY() int32 Version = 2;
	UPROPERTY() FDateTime Saved;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTAGameInstance : public UGameInstance
{
	GENERATED_BODY()
public:
	virtual void Init() override;

	UPROPERTY() FGTAProfile Profile;

	// settings (not part of the save slot)
	float MouseSensitivity = 1.f;
	bool bInvertY = false;
	bool bShowFPS = false;
	bool bShowCoords = false;
	bool bInvulnerable = false;
	bool bTrafficEnabled = true;
	bool bPedsEnabled = true;
	bool bWildlifeEnabled = true;
	bool bAllModsUnlocked = false;
	bool bTestMode = false;

	float GetSkill(EGTASkill S) const;
	void AddSkill(EGTASkill S, float Delta);
	void SetAllSkills(float V);

	bool SaveProfile(const FString& Slot = TEXT("PortHalcyon"));
	bool LoadProfile(const FString& Slot = TEXT("PortHalcyon"));
	bool HasSave(const FString& Slot = TEXT("PortHalcyon")) const;
	void ResetProfile();
};

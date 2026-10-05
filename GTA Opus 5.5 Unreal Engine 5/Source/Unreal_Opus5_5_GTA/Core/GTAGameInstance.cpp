#include "Core/GTAGameInstance.h"
#include "Kismet/GameplayStatics.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Player/GTAPlayerCharacter.h"
#include "World/GTAEnvironment.h"

void UGTAGameInstance::Init()
{
	Super::Init();
	ResetProfile();
	bTestMode = FParse::Param(FCommandLine::Get(), TEXT("gtatest"));
}

void UGTAGameInstance::ResetProfile()
{
	Profile = FGTAProfile();
	Profile.Skills.Init(0.f, (int32)EGTASkill::MAX);
	FGTAWeaponSlot Fists;
	Fists.Id = EGTAWeapon::Fists;
	Profile.Weapons = { Fists };
}

float UGTAGameInstance::GetSkill(EGTASkill S) const
{
	const int32 I = (int32)S;
	return Profile.Skills.IsValidIndex(I) ? Profile.Skills[I] : 0.f;
}

void UGTAGameInstance::AddSkill(EGTASkill S, float Delta)
{
	const int32 I = (int32)S;
	if (Profile.Skills.Num() < (int32)EGTASkill::MAX) Profile.Skills.SetNumZeroed((int32)EGTASkill::MAX);
	Profile.Skills[I] = FMath::Clamp(Profile.Skills[I] + Delta, 0.f, 1.f);
}

void UGTAGameInstance::SetAllSkills(float V)
{
	Profile.Skills.Init(FMath::Clamp(V, 0.f, 1.f), (int32)EGTASkill::MAX);
}

bool UGTAGameInstance::SaveProfile(const FString& Slot)
{
	if (AGTAPlayerCharacter* P = GTA::Player(this)) P->SaveToProfile();
	if (AGTAGameMode* M = GTA::Mode(this)) if (M->Env)
	{
		Profile.TimeOfDay = M->Env->TimeOfDay;
		Profile.Weather = (uint8)M->Env->Weather;
	}
	Profile.SavedMouseSensitivity = MouseSensitivity;
	Profile.bSavedInvertY = bInvertY;
	Profile.bSavedShowFPS = bShowFPS;
	UGTASaveGame* SG = Cast<UGTASaveGame>(UGameplayStatics::CreateSaveGameObject(UGTASaveGame::StaticClass()));
	if (!SG) return false;
	SG->Profile = Profile;
	SG->Saved = FDateTime::Now();
	const bool bOk = UGameplayStatics::SaveGameToSlot(SG, Slot, 0);
	UE_LOG(LogGTA, Log, TEXT("SaveProfile %s -> %d"), *Slot, bOk ? 1 : 0);
	return bOk;
}

bool UGTAGameInstance::LoadProfile(const FString& Slot)
{
	if (!UGameplayStatics::DoesSaveGameExist(Slot, 0)) return false;
	UGTASaveGame* SG = Cast<UGTASaveGame>(UGameplayStatics::LoadGameFromSlot(Slot, 0));
	if (!SG) return false;
	Profile = SG->Profile;
	MouseSensitivity = Profile.SavedMouseSensitivity;
	bInvertY = Profile.bSavedInvertY;
	bShowFPS = Profile.bSavedShowFPS;
	if (AGTAGameMode* M = GTA::Mode(this)) if (M->Env)
	{
		M->Env->SetTimeOfDay(Profile.TimeOfDay);
		M->Env->SetWeather((EGTAWeather)Profile.Weather, true);
	}
	if (Profile.Skills.Num() < (int32)EGTASkill::MAX) Profile.Skills.SetNumZeroed((int32)EGTASkill::MAX);
	UE_LOG(LogGTA, Log, TEXT("LoadProfile %s ok"), *Slot);
	return true;
}

bool UGTAGameInstance::HasSave(const FString& Slot) const
{
	return UGameplayStatics::DoesSaveGameExist(Slot, 0);
}

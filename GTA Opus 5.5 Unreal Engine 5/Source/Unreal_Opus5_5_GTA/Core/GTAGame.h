// Global gameplay services (crime reporting, FX, audio, money, skills, notifications).
#pragma once

#include "CoreMinimal.h"
#include "Core/GTATypes.h"

class AGTACharacter;
class AGTAPlayerCharacter;
class AGTAGameMode;
class UGTAGameInstance;

namespace GTA
{
	/** World-space water surface height (cm). The sea covers the southern edge of the map. */
	UNREAL_OPUS5_5_GTA_API float SeaLevel();
	UNREAL_OPUS5_5_GTA_API bool IsOverSea(const FVector& L);
	UNREAL_OPUS5_5_GTA_API float WaveHeight(const UObject* Ctx, const FVector& L);

	UNREAL_OPUS5_5_GTA_API AGTAGameMode* Mode(const UObject* Ctx);
	UNREAL_OPUS5_5_GTA_API AGTAPlayerCharacter* Player(const UObject* Ctx);
	UNREAL_OPUS5_5_GTA_API UGTAGameInstance* Instance(const UObject* Ctx);

	UNREAL_OPUS5_5_GTA_API void ReportCrime(const UObject* Ctx, AGTACharacter* Offender, EGTACrime Crime, const FVector& Loc, AActor* Victim);
	UNREAL_OPUS5_5_GTA_API void MakeNoise(const UObject* Ctx, const FVector& Loc, float RadiusCm, AActor* Instigator, bool bThreat);

	UNREAL_OPUS5_5_GTA_API void SpawnImpactFX(const UObject* Ctx, const FVector& Loc, const FVector& Normal, int32 Kind); // 0 dust 1 sparks 2 blood 3 water 4 hit
	UNREAL_OPUS5_5_GTA_API void SpawnMuzzleFX(const UObject* Ctx, const FVector& Loc, const FVector& Dir, bool bSuppressed);
	UNREAL_OPUS5_5_GTA_API void SpawnTracer(const UObject* Ctx, const FVector& A, const FVector& B);
	UNREAL_OPUS5_5_GTA_API void Explode(const UObject* Ctx, const FVector& Loc, float RadiusCm, float Damage, AActor* Causer, AController* Instigator);

	UNREAL_OPUS5_5_GTA_API void Play3D(const UObject* Ctx, const FString& Sound, const FVector& Loc, float Volume = 1.f, float Pitch = 1.f);
	UNREAL_OPUS5_5_GTA_API void Play2D(const UObject* Ctx, const FString& Sound, float Volume = 1.f, float Pitch = 1.f);
	UNREAL_OPUS5_5_GTA_API void CameraShake(const UObject* Ctx, const FVector& Loc, float Strength, float RadiusCm);

	UNREAL_OPUS5_5_GTA_API void Notify(const UObject* Ctx, const FString& Msg, float Seconds = 3.f);
	UNREAL_OPUS5_5_GTA_API void AddMoney(const UObject* Ctx, int32 Delta);
	UNREAL_OPUS5_5_GTA_API int32 Money(const UObject* Ctx);
	UNREAL_OPUS5_5_GTA_API bool SpendMoney(const UObject* Ctx, int32 Amount);
	UNREAL_OPUS5_5_GTA_API void AddSkill(const UObject* Ctx, EGTASkill S, float Amount);
	UNREAL_OPUS5_5_GTA_API float Skill(const UObject* Ctx, EGTASkill S);

	UNREAL_OPUS5_5_GTA_API void OnPedKilled(const UObject* Ctx, AGTACharacter* Victim);
	UNREAL_OPUS5_5_GTA_API void OnCharacterDied(const UObject* Ctx, AGTACharacter* C);
	UNREAL_OPUS5_5_GTA_API int32 WantedLevel(const UObject* Ctx);
	UNREAL_OPUS5_5_GTA_API bool IsNight(const UObject* Ctx);
}

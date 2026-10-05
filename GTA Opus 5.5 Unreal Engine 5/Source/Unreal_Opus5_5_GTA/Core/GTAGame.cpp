#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Core/GTAGameInstance.h"
#include "Player/GTAPlayerCharacter.h"
#include "Player/GTAPlayerController.h"
#include "AI/GTANPCController.h"
#include "World/GTACity.h"
#include "World/GTAFX.h"
#include "World/GTAEnvironment.h"
#include "World/GTAPopulation.h"
#include "Vehicles/GTAVehicle.h"
#include "Kismet/GameplayStatics.h"
#include "Sound/SoundBase.h"
#include "Sound/SoundAttenuation.h"
#include "Engine/OverlapResult.h"
#include "Components/PrimitiveComponent.h"
#include "EngineUtils.h"

float GTAWetGripFactor = 1.f;

namespace
{
	UWorld* WorldOf(const UObject* Ctx)
	{
		return Ctx ? GEngine->GetWorldFromContextObject(Ctx, EGetWorldErrorMode::ReturnNull) : nullptr;
	}

	USoundAttenuation* Attenuation()
	{
		static TStrongObjectPtr<USoundAttenuation> A;
		if (!A.IsValid())
		{
			A.Reset(NewObject<USoundAttenuation>(GetTransientPackage()));
			FSoundAttenuationSettings& S = A->Attenuation;
			S.bAttenuate = true;
			S.bSpatialize = true;
			S.AttenuationShape = EAttenuationShape::Sphere;
			S.AttenuationShapeExtents = FVector(400.f, 0.f, 0.f);
			S.FalloffDistance = 6000.f;
			S.DistanceAlgorithm = EAttenuationDistanceModel::NaturalSound;
		}
		return A.Get();
	}
}

namespace GTA
{
	float SeaLevel() { return AGTACity::SeaLevelZ; }

	bool IsOverSea(const FVector& L)
	{
		return AGTACity::IsWaterAt(L.X, L.Y);
	}

	float WaveHeight(const UObject* Ctx, const FVector& L)
	{
		UWorld* W = WorldOf(Ctx);
		const float T = W ? W->GetTimeSeconds() : 0.f;
		float Amp = 1.f;
		if (AGTAGameMode* M = Mode(Ctx)) { if (M->Env) Amp = M->Env->WaveAmplitude(); }
		return Amp * (11.f * FMath::Sin(T * 0.9f + L.X * 0.0021f) + 6.f * FMath::Sin(T * 1.6f + L.Y * 0.0033f + 1.3f));
	}

	AGTAGameMode* Mode(const UObject* Ctx)
	{
		UWorld* W = WorldOf(Ctx);
		return W ? Cast<AGTAGameMode>(W->GetAuthGameMode()) : nullptr;
	}

	AGTAPlayerCharacter* Player(const UObject* Ctx)
	{
		UWorld* W = WorldOf(Ctx);
		AGTAPlayerController* PC = W ? Cast<AGTAPlayerController>(W->GetFirstPlayerController()) : nullptr;
		if (!PC) return nullptr;
		if (PC->PlayerChar) return PC->PlayerChar;
		return Cast<AGTAPlayerCharacter>(PC->GetPawn());
	}

	UGTAGameInstance* Instance(const UObject* Ctx)
	{
		UWorld* W = WorldOf(Ctx);
		return W ? Cast<UGTAGameInstance>(W->GetGameInstance()) : nullptr;
	}

	void ReportCrime(const UObject* Ctx, AGTACharacter* Offender, EGTACrime Crime, const FVector& Loc, AActor* Victim)
	{
		if (AGTAGameMode* M = Mode(Ctx)) M->ReportCrime(Offender, Crime, Loc, Victim);
	}

	void MakeNoise(const UObject* Ctx, const FVector& Loc, float RadiusCm, AActor* Instigator, bool bThreat)
	{
		UWorld* W = WorldOf(Ctx);
		if (!W) return;
		const float R2 = RadiusCm * RadiusCm;
		for (TActorIterator<AGTACharacter> It(W); It; ++It)
		{
			AGTACharacter* C = *It;
			if (C == Instigator || C->bDead) continue;
			if (FVector::DistSquared(C->GetActorLocation(), Loc) > R2) continue;
			if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController())) AIC->OnNoise(Loc, RadiusCm, Instigator, bThreat);
		}
		if (AGTAGameMode* M = Mode(Ctx)) { if (M->Population) M->Population->OnNoise(Loc, RadiusCm, Instigator, bThreat); }
	}

	void SpawnImpactFX(const UObject* Ctx, const FVector& Loc, const FVector& Normal, int32 Kind)
	{
		if (AGTAGameMode* M = Mode(Ctx)) { if (M->FX) M->FX->Impact(Loc, Normal, Kind); }
	}

	void SpawnMuzzleFX(const UObject* Ctx, const FVector& Loc, const FVector& Dir, bool bSuppressed)
	{
		if (AGTAGameMode* M = Mode(Ctx)) { if (M->FX) M->FX->Muzzle(Loc, Dir, bSuppressed); }
	}

	void SpawnTracer(const UObject* Ctx, const FVector& A, const FVector& B)
	{
		if (AGTAGameMode* M = Mode(Ctx)) { if (M->FX) M->FX->Tracer(A, B); }
	}

	void Explode(const UObject* Ctx, const FVector& Loc, float RadiusCm, float Damage, AActor* Causer, AController* Instigator)
	{
		UWorld* W = WorldOf(Ctx);
		if (!W) return;
		TArray<AActor*> Ignore;
		UGameplayStatics::ApplyRadialDamageWithFalloff(W, Damage, Damage * 0.1f, Loc, RadiusCm * 0.35f, RadiusCm, 1.5f,
			UGTADamage_Explosion::StaticClass(), Ignore, Causer, Instigator, ECC_WorldStatic);
		// physics push
		TArray<FOverlapResult> Over;
		FCollisionObjectQueryParams OQ;
		OQ.AddObjectTypesToQuery(ECC_PhysicsBody);
		OQ.AddObjectTypesToQuery(ECC_Vehicle);
		OQ.AddObjectTypesToQuery(ECC_WorldDynamic);
		W->OverlapMultiByObjectType(Over, Loc, FQuat::Identity, OQ, FCollisionShape::MakeSphere(RadiusCm * 1.2f));
		TSet<UPrimitiveComponent*> Pushed;
		for (const FOverlapResult& O : Over)
		{
			UPrimitiveComponent* P = O.GetComponent();
			if (!P || Pushed.Contains(P) || !P->IsSimulatingPhysics()) continue;
			Pushed.Add(P);
			P->AddRadialImpulse(Loc, RadiusCm * 1.2f, 900.f, ERadialImpulseFalloff::RIF_Linear, true);
		}
		if (AGTAGameMode* M = Mode(Ctx)) { if (M->FX) M->FX->Explosion(Loc, RadiusCm); }
		Play3D(Ctx, TEXT("S_Explosion"), Loc, 1.f, FMath::FRandRange(0.85f, 1.05f));
		CameraShake(Ctx, Loc, 1.f, RadiusCm * 6.f);
		MakeNoise(Ctx, Loc, 12000.f, Causer, true);
	}

	void Play3D(const UObject* Ctx, const FString& Sound, const FVector& Loc, float Volume, float Pitch)
	{
		UWorld* W = WorldOf(Ctx);
		USoundBase* S = FGTAAssets::Sound(Sound);
		if (W && S) UGameplayStatics::PlaySoundAtLocation(W, S, Loc, FRotator::ZeroRotator, Volume, Pitch, 0.f, Attenuation());
	}

	void Play2D(const UObject* Ctx, const FString& Sound, float Volume, float Pitch)
	{
		UWorld* W = WorldOf(Ctx);
		USoundBase* S = FGTAAssets::Sound(Sound);
		if (W && S) UGameplayStatics::PlaySound2D(W, S, Volume, Pitch);
	}

	void CameraShake(const UObject* Ctx, const FVector& Loc, float Strength, float RadiusCm)
	{
		UWorld* W = WorldOf(Ctx);
		AGTAPlayerController* PC = W ? Cast<AGTAPlayerController>(W->GetFirstPlayerController()) : nullptr;
		if (!PC || !PC->GetPawn()) return;
		const float D = FVector::Dist(PC->GetPawn()->GetActorLocation(), Loc);
		const float F = FMath::Clamp(1.f - D / FMath::Max(RadiusCm, 1.f), 0.f, 1.f);
		if (F > 0.f) PC->AddCameraShake(Strength * F);
	}

	void Notify(const UObject* Ctx, const FString& Msg, float Seconds)
	{
		if (AGTAGameMode* M = Mode(Ctx)) M->Notify(Msg, Seconds);
	}

	void AddMoney(const UObject* Ctx, int32 Delta)
	{
		if (UGTAGameInstance* GI = Instance(Ctx)) GI->Profile.Money = FMath::Max(0, GI->Profile.Money + Delta);
	}

	int32 Money(const UObject* Ctx)
	{
		UGTAGameInstance* GI = Instance(Ctx);
		return GI ? GI->Profile.Money : 0;
	}

	bool SpendMoney(const UObject* Ctx, int32 Amount)
	{
		UGTAGameInstance* GI = Instance(Ctx);
		if (!GI || GI->Profile.Money < Amount) { Notify(Ctx, TEXT("Not enough money."), 2.f); Play2D(Ctx, TEXT("S_UI_Error"), 0.6f); return false; }
		GI->Profile.Money -= Amount;
		Play2D(Ctx, TEXT("S_UI_Buy"), 0.7f);
		return true;
	}

	void AddSkill(const UObject* Ctx, EGTASkill S, float Amount)
	{
		UGTAGameInstance* GI = Instance(Ctx);
		if (!GI) return;
		const float Before = GI->GetSkill(S);
		GI->AddSkill(S, Amount);
		const float After = GI->GetSkill(S);
		if (FMath::FloorToInt(Before * 10.f) != FMath::FloorToInt(After * 10.f))
		{
			Notify(Ctx, FString::Printf(TEXT("%s skill increased (%d%%)"), *FGTAData::SkillName(S), FMath::RoundToInt(After * 100.f)), 2.5f);
		}
	}

	float Skill(const UObject* Ctx, EGTASkill S)
	{
		UGTAGameInstance* GI = Instance(Ctx);
		return GI ? GI->GetSkill(S) : 0.f;
	}

	void OnPedKilled(const UObject* Ctx, AGTACharacter* Victim)
	{
		if (Victim && Victim->LastAttacker.IsValid())
		{
			const AGTACharacter* K = Cast<AGTACharacter>(Victim->LastAttacker.Get());
			if (K && K->IsPlayerCharacter()) { if (UGTAGameInstance* GI = Instance(Ctx)) GI->Profile.Kills++; }
		}
		if (AGTAGameMode* M = Mode(Ctx)) { if (M->Population) M->Population->OnPedKilled(Victim); }
	}

	void OnCharacterDied(const UObject* Ctx, AGTACharacter* C)
	{
		if (C && C->IsPlayerCharacter())
		{
			if (AGTAGameMode* M = Mode(Ctx)) M->OnPlayerWasted();
		}
	}

	int32 WantedLevel(const UObject* Ctx)
	{
		AGTAGameMode* M = Mode(Ctx);
		return M ? M->WantedLevel : 0;
	}

	bool IsNight(const UObject* Ctx)
	{
		AGTAGameMode* M = Mode(Ctx);
		return M && M->Env ? M->Env->IsNight() : false;
	}
}

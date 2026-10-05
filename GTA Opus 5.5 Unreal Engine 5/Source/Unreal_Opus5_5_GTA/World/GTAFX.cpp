#include "World/GTAFX.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "World/GTAEnvironment.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/PointLightComponent.h"
#include "Engine/StaticMesh.h"
#include "Kismet/GameplayStatics.h"
#include "Camera/PlayerCameraManager.h"

static UInstancedStaticMeshComponent* GTAMakePool(AActor* Owner, const TCHAR* Name, const TCHAR* Mat)
{
	UInstancedStaticMeshComponent* P = Owner->CreateDefaultSubobject<UInstancedStaticMeshComponent>(Name);
	P->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	P->SetCastShadow(false);
	P->NumCustomDataFloats = 4;
	P->SetMobility(EComponentMobility::Movable);
	P->bAffectDistanceFieldLighting = false;
	return P;
}

AGTAFX::AGTAFX()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickGroup = TG_PostPhysics;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	TransPool = GTAMakePool(this, TEXT("TransPool"), TEXT("M_GTA_Particle"));
	TransPool->SetupAttachment(RootComponent);
	AddPool = GTAMakePool(this, TEXT("AddPool"), TEXT("M_GTA_ParticleAdd"));
	AddPool->SetupAttachment(RootComponent);
	HolePool = GTAMakePool(this, TEXT("HolePool"), TEXT("M_GTA_Particle"));
	HolePool->SetupAttachment(RootComponent);
	for (int32 i = 0; i < 6; ++i)
	{
		UPointLightComponent* L = CreateDefaultSubobject<UPointLightComponent>(*FString::Printf(TEXT("FlashLight%d"), i));
		L->SetupAttachment(RootComponent);
		L->SetIntensity(0.f);
		L->SetCastShadows(false);
		L->SetVisibility(false);
		L->bUseInverseSquaredFalloff = false;
		L->LightFalloffExponent = 2.f;
		Lights.Add(L);
	}
}

void AGTAFX::BeginPlay()
{
	Super::BeginPlay();
	UStaticMesh* Quad = FGTAAssets::Plane();
	UMaterialInterface* MT = FGTAAssets::Material(TEXT("Particle"));
	UMaterialInterface* MA = FGTAAssets::Material(TEXT("ParticleAdd"));
	TransPool->SetStaticMesh(Quad);
	AddPool->SetStaticMesh(Quad);
	HolePool->SetStaticMesh(Quad);
	if (MT) { TransPool->SetMaterial(0, MT); HolePool->SetMaterial(0, MT); }
	if (MA) AddPool->SetMaterial(0, MA);
	TArray<FTransform> Zero;
	Zero.Init(FTransform(FQuat::Identity, FVector(0, 0, -100000.f), FVector::ZeroVector), Capacity);
	TransPool->AddInstances(Zero, false, true);
	AddPool->AddInstances(Zero, false, true);
	Zero.SetNum(HoleCapacity);
	HolePool->AddInstances(Zero, false, true);
	LightLife.Init(0.f, Lights.Num());
	LightMax.Init(1.f, Lights.Num());
	LightPeak.Init(0.f, Lights.Num());
}

void AGTAFX::Emit(bool bAdditive, const FGTAParticle& P)
{
	TArray<FGTAParticle>& A = Parts[bAdditive ? 1 : 0];
	if (A.Num() >= Capacity) A.RemoveAtSwap(0, 1, EAllowShrinking::No);
	A.Add(P);
}

void AGTAFX::Flash(const FVector& Loc, const FLinearColor& Color, float Intensity, float Radius, float Life)
{
	if (Lights.Num() == 0) return;
	const int32 i = NextLight++ % Lights.Num();
	UPointLightComponent* L = Lights[i];
	L->SetWorldLocation(Loc);
	L->SetLightColor(Color);
	L->SetAttenuationRadius(Radius);
	L->SetIntensity(Intensity);
	L->SetVisibility(true);
	LightLife[i] = Life;
	LightMax[i] = Life;
	LightPeak[i] = Intensity;
}

void AGTAFX::BulletHole(const FVector& Loc, const FVector& Normal, float Size, const FLinearColor& Color)
{
	if (!HolePool || HolePool->GetInstanceCount() < HoleCapacity) return;
	const int32 i = NextHole++ % HoleCapacity;
	const FRotator R = FRotationMatrix::MakeFromZ(Normal).Rotator() + FRotator(0, 0, 0);
	FTransform T(FRotator(R.Pitch, R.Yaw, FMath::FRandRange(0.f, 360.f)).Quaternion(), Loc + Normal * 0.6f, FVector(Size / 100.f));
	T.SetRotation(FQuat(Normal, FMath::FRandRange(0.f, 6.28f)) * FRotationMatrix::MakeFromZ(Normal).ToQuat());
	HolePool->UpdateInstanceTransform(i, T, true, false, true);
	const float D[4] = { Color.R, Color.G, Color.B, Color.A };
	HolePool->SetCustomData(i, MakeArrayView(D, 4), true);
}

static FGTAParticle GTAPart(const FVector& Pos, const FVector& Vel, float Life, float S0, float S1, const FLinearColor& C, float Alpha)
{
	FGTAParticle P;
	P.Pos = Pos;
	P.Vel = Vel;
	P.Life = Life;
	P.Size0 = S0;
	P.Size1 = S1;
	P.Color = C;
	P.Alpha = Alpha;
	return P;
}

void AGTAFX::Impact(const FVector& Loc, const FVector& Normal, int32 Kind)
{
	const FVector N = Normal.GetSafeNormal();
	auto Cone = [&N](float Spread) { return (N + FMath::VRand() * Spread).GetSafeNormal(); };
	switch (Kind)
	{
	case 0: // dust
		for (int32 i = 0; i < 5; ++i)
		{
			FGTAParticle P = GTAPart(Loc, Cone(0.6f) * FMath::FRandRange(80.f, 260.f), FMath::FRandRange(0.5f, 1.0f), 6.f, 45.f, FLinearColor(0.55f, 0.5f, 0.42f), 0.55f);
			P.Drag = 3.f; P.Gravity = -60.f;
			Emit(false, P);
		}
		BulletHole(Loc, N, FMath::FRandRange(4.f, 6.f), FLinearColor(0.02f, 0.02f, 0.02f, 0.92f));
		break;
	case 1: // sparks
		for (int32 i = 0; i < 7; ++i)
		{
			FGTAParticle P = GTAPart(Loc, Cone(0.8f) * FMath::FRandRange(300.f, 900.f), FMath::FRandRange(0.15f, 0.4f), 2.f, 1.f, FLinearColor(4.f, 2.4f, 0.8f), 1.f);
			P.Gravity = 900.f; P.Stretch = 0.025f; P.bLit = false;
			Emit(true, P);
		}
		BulletHole(Loc, N, 4.f, FLinearColor(0.05f, 0.05f, 0.06f, 0.9f));
		break;
	case 2: // blood
		for (int32 i = 0; i < 6; ++i)
		{
			FGTAParticle P = GTAPart(Loc, Cone(0.7f) * FMath::FRandRange(80.f, 300.f), FMath::FRandRange(0.3f, 0.6f), 5.f, 18.f, FLinearColor(0.25f, 0.0f, 0.0f), 0.9f);
			P.Gravity = 600.f; P.Drag = 1.f;
			Emit(false, P);
		}
		{
			FHitResult H;
			FCollisionQueryParams Q(SCENE_QUERY_STAT(GTABlood), false);
			if (GetWorld()->LineTraceSingleByChannel(H, Loc, Loc - FVector(0, 0, 250.f), ECC_WorldStatic, Q))
			{
				BulletHole(H.ImpactPoint, H.ImpactNormal, FMath::FRandRange(25.f, 55.f), FLinearColor(0.12f, 0.0f, 0.0f, 0.85f));
			}
		}
		break;
	case 3: // water
	case 9:
	{
		const int32 Count = Kind == 9 ? 22 : 8;
		const float Sc = Kind == 9 ? 2.5f : 1.f;
		for (int32 i = 0; i < Count; ++i)
		{
			FVector V = FVector(FMath::FRandRange(-1.f, 1.f), FMath::FRandRange(-1.f, 1.f), FMath::FRandRange(1.5f, 3.5f)).GetSafeNormal() * FMath::FRandRange(200.f, 520.f) * FMath::Sqrt(Sc);
			FGTAParticle P = GTAPart(Loc, V, FMath::FRandRange(0.5f, 1.1f), 8.f * Sc, 30.f * Sc, FLinearColor(0.75f, 0.85f, 0.9f), 0.7f);
			P.Gravity = 980.f;
			Emit(false, P);
		}
		break;
	}
	case 4: // hit puff
	{
		FGTAParticle P = GTAPart(Loc, N * 60.f, 0.35f, 8.f, 30.f, FLinearColor(0.6f, 0.6f, 0.6f), 0.5f);
		Emit(false, P);
		break;
	}
	case 5: // smoke (vehicle damage, fires)
	{
		FGTAParticle P = GTAPart(Loc + FMath::VRand() * 10.f, FVector(FMath::FRandRange(-30.f, 30.f), FMath::FRandRange(-30.f, 30.f), FMath::FRandRange(90.f, 160.f)),
			FMath::FRandRange(1.6f, 2.6f), 30.f, 180.f, FLinearColor(0.08f, 0.08f, 0.085f), 0.55f);
		P.Drag = 0.4f;
		Emit(false, P);
		break;
	}
	case 6: // fire
	{
		for (int32 i = 0; i < 2; ++i)
		{
			FGTAParticle P = GTAPart(Loc + FMath::VRand() * 25.f, FVector(0, 0, FMath::FRandRange(120.f, 260.f)), FMath::FRandRange(0.35f, 0.7f), 45.f, 12.f,
				FLinearColor(3.5f, FMath::FRandRange(1.0f, 1.8f), 0.25f), 0.85f);
			P.bLit = false;
			Emit(true, P);
		}
		break;
	}
	case 7: // tire smoke
	{
		FGTAParticle P = GTAPart(Loc + FVector(0, 0, 15.f), FVector(FMath::FRandRange(-40.f, 40.f), FMath::FRandRange(-40.f, 40.f), FMath::FRandRange(20.f, 60.f)),
			FMath::FRandRange(0.9f, 1.6f), 30.f, 150.f, FLinearColor(0.7f, 0.7f, 0.7f), 0.35f);
		P.Drag = 1.2f;
		Emit(false, P);
		break;
	}
	case 8: // rocket trail
	{
		FGTAParticle F = GTAPart(Loc, N * 100.f, 0.12f, 22.f, 6.f, FLinearColor(4.f, 2.f, 0.6f), 1.f);
		F.bLit = false;
		Emit(true, F);
		FGTAParticle S = GTAPart(Loc, FMath::VRand() * 20.f, 1.4f, 15.f, 90.f, FLinearColor(0.55f, 0.55f, 0.55f), 0.4f);
		S.Drag = 0.8f;
		Emit(false, S);
		break;
	}
	default: break;
	}
}

void AGTAFX::Muzzle(const FVector& Loc, const FVector& Dir, bool bSuppressed)
{
	if (bSuppressed)
	{
		FGTAParticle P = GTAPart(Loc, Dir * 40.f, 0.25f, 4.f, 18.f, FLinearColor(0.7f, 0.7f, 0.7f), 0.25f);
		Emit(false, P);
		return;
	}
	for (int32 i = 0; i < 3; ++i)
	{
		FGTAParticle P = GTAPart(Loc + Dir * (4.f + i * 7.f), Dir * 30.f, 0.05f, 16.f - i * 3.f, 10.f, FLinearColor(5.f, 3.2f, 1.2f), 1.f);
		P.bLit = false;
		Emit(true, P);
	}
	FGTAParticle S = GTAPart(Loc + Dir * 10.f, Dir * 60.f + FVector(0, 0, 20.f), 0.6f, 6.f, 30.f, FLinearColor(0.6f, 0.6f, 0.6f), 0.25f);
	S.Drag = 2.f;
	Emit(false, S);
	Flash(Loc + Dir * 15.f, FLinearColor(1.f, 0.7f, 0.35f), 9000.f, 450.f, 0.05f);
}

void AGTAFX::Tracer(const FVector& A, const FVector& B)
{
	const FVector D = (B - A);
	const float Len = D.Size();
	if (Len < 200.f) return;
	const FVector Dir = D / Len;
	FGTAParticle P = GTAPart(A + Dir * 120.f, Dir * 30000.f, FMath::Min(0.1f, Len / 30000.f), 1.6f, 1.6f, FLinearColor(3.f, 2.4f, 1.4f), 0.9f);
	P.Stretch = 0.012f;
	P.bLit = false;
	Emit(true, P);
}

void AGTAFX::Explosion(const FVector& Loc, float Radius)
{
	const float S = FMath::Clamp(Radius / 600.f, 0.5f, 2.5f);
	for (int32 i = 0; i < 26; ++i)
	{
		FGTAParticle P = GTAPart(Loc + FMath::VRand() * 40.f * S, FMath::VRand() * FMath::FRandRange(200.f, 700.f) * S + FVector(0, 0, 250.f),
			FMath::FRandRange(0.35f, 0.8f), 90.f * S, 260.f * S, FLinearColor(4.f, FMath::FRandRange(1.2f, 2.2f), 0.3f), 0.9f);
		P.Drag = 3.f; P.bLit = false;
		Emit(true, P);
	}
	for (int32 i = 0; i < 18; ++i)
	{
		FGTAParticle P = GTAPart(Loc + FMath::VRand() * 80.f * S, FMath::VRand() * FMath::FRandRange(100.f, 350.f) * S + FVector(0, 0, 300.f),
			FMath::FRandRange(2.5f, 4.5f), 120.f * S, 520.f * S, FLinearColor(0.07f, 0.065f, 0.06f), 0.75f);
		P.Drag = 1.2f; P.Gravity = -40.f;
		Emit(false, P);
	}
	for (int32 i = 0; i < 24; ++i)
	{
		FGTAParticle P = GTAPart(Loc, FMath::VRand() * FMath::FRandRange(600.f, 1600.f) + FVector(0, 0, 400.f), FMath::FRandRange(0.5f, 1.2f), 4.f, 2.f, FLinearColor(4.f, 2.f, 0.6f), 1.f);
		P.Gravity = 980.f; P.Stretch = 0.02f; P.bLit = false;
		Emit(true, P);
	}
	Flash(Loc + FVector(0, 0, 100.f), FLinearColor(1.f, 0.55f, 0.2f), 400000.f * S, Radius * 5.f, 0.6f);
	FHitResult H;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAScorch), false);
	if (GetWorld()->LineTraceSingleByChannel(H, Loc + FVector(0, 0, 50.f), Loc - FVector(0, 0, 400.f), ECC_WorldStatic, Q))
	{
		BulletHole(H.ImpactPoint, H.ImpactNormal, Radius * 0.6f, FLinearColor(0.015f, 0.013f, 0.012f, 0.85f));
	}
}

void AGTAFX::UpdatePool(int32 Index, UInstancedStaticMeshComponent* Pool, const FVector& Cam, float Ambient)
{
	if (!Pool || Pool->GetInstanceCount() < Capacity) return;
	TArray<FGTAParticle>& A = Parts[Index];
	TArray<FTransform> Ts;
	Ts.SetNumUninitialized(Capacity);
	for (int32 i = 0; i < Capacity; ++i)
	{
		if (i >= A.Num())
		{
			Ts[i] = FTransform(FQuat::Identity, FVector(0, 0, -100000.f), FVector::ZeroVector);
			continue;
		}
		const FGTAParticle& P = A[i];
		const float T = FMath::Clamp(P.Age / FMath::Max(P.Life, 0.001f), 0.f, 1.f);
		const float Size = FMath::Lerp(P.Size0, P.Size1, FMath::Sqrt(T));
		const FVector ToCam = (Cam - P.Pos).GetSafeNormal();
		if (P.Stretch > 0.f && !P.Vel.IsNearlyZero())
		{
			const FVector Dir = P.Vel.GetSafeNormal();
			const float Len = FMath::Max(Size, P.Vel.Size() * P.Stretch * 10.f);
			const FMatrix M = FRotationMatrix::MakeFromXZ(Dir, ToCam);
			Ts[i] = FTransform(M.ToQuat(), P.Pos, FVector(Len / 100.f, Size / 100.f, 1.f));
		}
		else
		{
			Ts[i] = FTransform(FRotationMatrix::MakeFromZ(ToCam).ToQuat(), P.Pos, FVector(Size / 100.f));
		}
		const float Fade = (T < 0.1f ? T / 0.1f : 1.f) * (1.f - T);
		const float L = P.bLit ? Ambient : 1.f;
		const float D[4] = { P.Color.R * L, P.Color.G * L, P.Color.B * L, P.Alpha * Fade };
		Pool->SetCustomData(i, MakeArrayView(D, 4), false);
	}
	Pool->BatchUpdateInstancesTransforms(0, Ts, true, true, true);
}

void AGTAFX::Tick(float Dt)
{
	Super::Tick(Dt);
	for (int32 k = 0; k < 2; ++k)
	{
		TArray<FGTAParticle>& A = Parts[k];
		for (int32 i = A.Num() - 1; i >= 0; --i)
		{
			FGTAParticle& P = A[i];
			P.Age += Dt;
			if (P.Age >= P.Life) { A.RemoveAtSwap(i, 1, EAllowShrinking::No); continue; }
			P.Vel.Z -= P.Gravity * Dt;
			P.Vel *= FMath::Max(0.f, 1.f - P.Drag * Dt);
			P.Pos += P.Vel * Dt;
		}
	}
	FVector Cam = FVector::ZeroVector;
	if (APlayerCameraManager* PCM = UGameplayStatics::GetPlayerCameraManager(this, 0)) Cam = PCM->GetCameraLocation();
	float Ambient = 1.f;
	if (AGTAGameMode* M = GTA::Mode(this)) { if (M->Env) Ambient = M->Env->AmbientFactor(); }
	UpdatePool(0, TransPool, Cam, Ambient);
	UpdatePool(1, AddPool, Cam, 1.f);
	for (int32 i = 0; i < Lights.Num(); ++i)
	{
		if (LightLife[i] <= 0.f) continue;
		LightLife[i] -= Dt;
		if (LightLife[i] <= 0.f) { Lights[i]->SetVisibility(false); continue; }
		Lights[i]->SetIntensity(LightPeak[i] * (LightLife[i] / LightMax[i]));
	}
}

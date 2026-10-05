#include "World/GTAEnvironment.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameInstance.h"
#include "World/GTACity.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/ExponentialHeightFogComponent.h"
#include "Components/VolumetricCloudComponent.h"
#include "Components/PostProcessComponent.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/AudioComponent.h"
#include "Kismet/KismetMaterialLibrary.h"
#include "Kismet/GameplayStatics.h"
#include "Camera/PlayerCameraManager.h"
#include "Materials/MaterialInterface.h"
#include "Sound/SoundWave.h"

extern float GTAWetGripFactor;

static constexpr int32 GTARainCount = 700;
static constexpr float GTARainBox = 2600.f;

AGTAEnvironment::AGTAEnvironment()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickGroup = TG_PrePhysics;
	Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent = Root;

	Sun = CreateDefaultSubobject<UDirectionalLightComponent>(TEXT("Sun"));
	Sun->SetupAttachment(Root);
	Sun->SetMobility(EComponentMobility::Movable);
	Sun->SetAtmosphereSunLight(true);
	Sun->SetAtmosphereSunLightIndex(0);
	Sun->SetIntensity(10.f);
	Sun->SetLightColor(FLinearColor(1.f, 0.96f, 0.9f));
	Sun->DynamicShadowDistanceMovableLight = 25000.f;
	Sun->bCastCloudShadows = true;

	Moon = CreateDefaultSubobject<UDirectionalLightComponent>(TEXT("Moon"));
	Moon->SetupAttachment(Root);
	Moon->SetMobility(EComponentMobility::Movable);
	Moon->SetAtmosphereSunLight(true);
	Moon->SetAtmosphereSunLightIndex(1);
	Moon->SetIntensity(0.25f);
	Moon->SetLightColor(FLinearColor(0.55f, 0.65f, 1.f));
	Moon->DynamicShadowDistanceMovableLight = 12000.f;

	Atmosphere = CreateDefaultSubobject<USkyAtmosphereComponent>(TEXT("Atmosphere"));
	Atmosphere->SetupAttachment(Root);

	SkyLight = CreateDefaultSubobject<USkyLightComponent>(TEXT("SkyLight"));
	SkyLight->SetupAttachment(Root);
	SkyLight->SetMobility(EComponentMobility::Movable);
	SkyLight->bRealTimeCapture = true;
	SkyLight->SourceType = ESkyLightSourceType::SLS_CapturedScene;
	SkyLight->SetIntensity(1.f);

	Fog = CreateDefaultSubobject<UExponentialHeightFogComponent>(TEXT("Fog"));
	Fog->SetupAttachment(Root);
	Fog->SetFogDensity(0.012f);
	Fog->SetFogHeightFalloff(0.12f);
	Fog->SetVolumetricFog(true);

	Clouds = CreateDefaultSubobject<UVolumetricCloudComponent>(TEXT("Clouds"));
	Clouds->SetupAttachment(Root);

	Post = CreateDefaultSubobject<UPostProcessComponent>(TEXT("Post"));
	Post->SetupAttachment(Root);
	Post->bUnbound = true;
	FPostProcessSettings& S = Post->Settings;
	S.bOverride_AutoExposureMinBrightness = true;
	S.AutoExposureMinBrightness = -1.5f;
	S.bOverride_AutoExposureMaxBrightness = true;
	S.AutoExposureMaxBrightness = 11.f;
	S.bOverride_BloomIntensity = true;
	S.BloomIntensity = 0.85f;
	S.bOverride_VignetteIntensity = true;
	S.VignetteIntensity = 0.3f;
	S.bOverride_ColorSaturation = true;
	S.ColorSaturation = FVector4(1.08f, 1.08f, 1.12f, 1.f);
	S.bOverride_SceneColorTint = true;
	S.SceneColorTint = FLinearColor::White;

	RainDrops = CreateDefaultSubobject<UInstancedStaticMeshComponent>(TEXT("RainDrops"));
	RainDrops->SetupAttachment(Root);
	RainDrops->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	RainDrops->SetCastShadow(false);
	RainDrops->NumCustomDataFloats = 4;
	RainDrops->SetMobility(EComponentMobility::Movable);

	RainAudio = CreateDefaultSubobject<UAudioComponent>(TEXT("RainAudio"));
	RainAudio->SetupAttachment(Root);
	RainAudio->bAutoActivate = false;
	RainAudio->bIsUISound = true;
	AmbienceAudio = CreateDefaultSubobject<UAudioComponent>(TEXT("AmbienceAudio"));
	AmbienceAudio->SetupAttachment(Root);
	AmbienceAudio->bAutoActivate = false;
	AmbienceAudio->bIsUISound = true;
}

void AGTAEnvironment::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	if (UMaterialInterface* CM = LoadObject<UMaterialInterface>(nullptr, TEXT("/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst.m_SimpleVolumetricCloud_Inst")))
	{
		Clouds->SetMaterial(CM);
	}
	ApplyLighting(0.f);
}

static USoundBase* GTALoopSound(const TCHAR* Name)
{
	USoundBase* S = FGTAAssets::Sound(Name);
	if (USoundWave* W = Cast<USoundWave>(S)) W->bLooping = true;
	return S;
}

void AGTAEnvironment::BeginPlay()
{
	Super::BeginPlay();
	if (UMaterialInterface* CM = LoadObject<UMaterialInterface>(nullptr, TEXT("/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst.m_SimpleVolumetricCloud_Inst")))
	{
		Clouds->SetMaterial(CM);
	}
	RainDrops->SetStaticMesh(FGTAAssets::Plane());
	if (UMaterialInterface* M = FGTAAssets::Material(TEXT("Particle"))) RainDrops->SetMaterial(0, M);
	TArray<FTransform> Zero;
	Zero.Init(FTransform(FQuat::Identity, FVector(0, 0, -100000.f), FVector::ZeroVector), GTARainCount);
	RainDrops->AddInstances(Zero, false, true);
	RainPos.SetNum(GTARainCount);
	for (FVector& P : RainPos) P = FVector(FMath::FRandRange(-GTARainBox, GTARainBox), FMath::FRandRange(-GTARainBox, GTARainBox), FMath::FRandRange(-1200.f, 1500.f));
	if (USoundBase* RS = GTALoopSound(TEXT("S_Rain"))) { RainAudio->SetSound(RS); }
	if (USoundBase* AS = GTALoopSound(TEXT("S_Amb_City"))) { AmbienceAudio->SetSound(AS); AmbienceAudio->SetVolumeMultiplier(0.35f); AmbienceAudio->Play(); }
	NextWeatherChange = FMath::FRandRange(240.f, 420.f);
	SetWeather(Weather, true);
	ApplyLighting(0.f);
}

void AGTAEnvironment::SetTimeOfDay(float Hours)
{
	TimeOfDay = FMath::Fmod(FMath::Fmod(Hours, 24.f) + 24.f, 24.f);
	ApplyLighting(0.f);
}

void AGTAEnvironment::SetWeather(EGTAWeather W, bool bInstant)
{
	Weather = W;
	if (bInstant)
	{
		Overcast = (W == EGTAWeather::Cloudy) ? 0.6f : (W == EGTAWeather::Rain ? 0.85f : (W == EGTAWeather::Storm ? 1.f : (W == EGTAWeather::Fog ? 0.5f : 0.f)));
		Rain = (W == EGTAWeather::Rain) ? 0.7f : (W == EGTAWeather::Storm ? 1.f : 0.f);
		FogAmount = (W == EGTAWeather::Fog) ? 1.f : (W == EGTAWeather::Storm ? 0.35f : (W == EGTAWeather::Rain ? 0.25f : 0.f));
		Storminess = W == EGTAWeather::Storm ? 1.f : 0.f;
		Wetness = Rain > 0.f ? 1.f : 0.f;
	}
	if (UGTAGameInstance* GI = GTA::Instance(this)) GI->Profile.Weather = (uint8)W;
}

float AGTAEnvironment::VisibilityFactor() const
{
	float V = 1.f;
	V *= FMath::Lerp(1.f, 0.55f, FogAmount);
	V *= FMath::Lerp(1.f, 0.8f, Rain);
	V *= FMath::Lerp(1.f, 0.75f, Night);
	return V;
}

FString AGTAEnvironment::TimeString() const
{
	const int32 H = FMath::FloorToInt(TimeOfDay);
	const int32 M = FMath::FloorToInt((TimeOfDay - H) * 60.f);
	return FString::Printf(TEXT("%02d:%02d"), H, M);
}

void AGTAEnvironment::TickWeatherCycle(float Dt)
{
	if (!bAutoWeather) return;
	NextWeatherChange -= Dt;
	if (NextWeatherChange > 0.f) return;
	NextWeatherChange = FMath::FRandRange(240.f, 480.f);
	const float R = FMath::FRand();
	EGTAWeather W = R < 0.42f ? EGTAWeather::Clear : (R < 0.67f ? EGTAWeather::Cloudy : (R < 0.82f ? EGTAWeather::Rain : (R < 0.92f ? EGTAWeather::Fog : EGTAWeather::Storm)));
	SetWeather(W, false);
}

void AGTAEnvironment::ApplyLighting(float Dt)
{
	// sun path: rises in the east (+Y), sets in the west, max elevation 68 deg
	const float DayT = (TimeOfDay - 6.f) / 12.f;                 // 0 sunrise .. 1 sunset
	const float Elev = FMath::Sin(DayT * PI) * 68.f;              // negative at night
	const float Azimuth = FMath::Lerp(-90.f, 90.f, FMath::Clamp(DayT, -0.5f, 1.5f));
	Sun->SetWorldRotation(FRotator(-Elev, Azimuth + 180.f, 0.f));
	const float MoonElev = -Elev * 0.8f + 10.f;
	Moon->SetWorldRotation(FRotator(-FMath::Max(MoonElev, 5.f), Azimuth, 0.f));
	Night = FMath::Clamp((2.f - Elev) / 12.f, 0.f, 1.f);

	const float Lightning = LightningFlash > 0.f ? LightningFlash * 6.f : 0.f;
	// UDirectionalLightComponent::GetLightUnits() reports Unitless on this engine build, so this is
	// a plain multiplier (the UE template level uses 3.14) rather than a lux value.
	const float SunI = FMath::Clamp(Elev / 8.f, 0.f, 1.f) * FMath::Lerp(10.f, 2.2f, Overcast) + Lightning;
	Sun->SetIntensity(SunI);
	Sun->SetVisibility(Elev > -6.f || Lightning > 0.f);
	Moon->SetIntensity(FMath::Lerp(0.f, 0.35f, Night) * FMath::Lerp(1.f, 0.4f, Overcast));
	Moon->SetVisibility(Night > 0.01f);
	SkyLight->SetIntensity(FMath::Lerp(1.f, 0.7f, Overcast) + Night * 0.6f);
	Fog->SetFogDensity(FMath::Lerp(0.008f, 0.06f, FogAmount) + Rain * 0.01f);
	Fog->SetFogHeightFalloff(FMath::Lerp(0.12f, 0.05f, FogAmount));
	Fog->SetFogInscatteringColor(FMath::Lerp(FLinearColor(0.45f, 0.55f, 0.7f), FLinearColor(0.02f, 0.025f, 0.05f), Night));

	FPostProcessSettings& S = Post->Settings;
	S.SceneColorTint = bUnderwater ? FLinearColor(0.35f, 0.75f, 0.85f) : FLinearColor::White;
	S.ColorSaturation = FVector4(1.08f - Overcast * 0.15f, 1.08f - Overcast * 0.15f, 1.12f - Overcast * 0.1f, 1.f);

	if (UMaterialParameterCollection* MPC = FGTAAssets::WorldMPC())
	{
		UWorld* W = GetWorld();
		if (W && W->IsGameWorld())
		{
			UKismetMaterialLibrary::SetScalarParameterValue(W, MPC, TEXT("NightFactor"), Night);
			UKismetMaterialLibrary::SetScalarParameterValue(W, MPC, TEXT("Wetness"), Wetness);
			UKismetMaterialLibrary::SetScalarParameterValue(W, MPC, TEXT("RainAmount"), Rain);
			UKismetMaterialLibrary::SetScalarParameterValue(W, MPC, TEXT("TimeOfDay"), TimeOfDay);
			UKismetMaterialLibrary::SetScalarParameterValue(W, MPC, TEXT("Underwater"), bUnderwater ? 1.f : 0.f);
		}
	}
	GTAWetGripFactor = 1.f - 0.2f * Wetness;
}

void AGTAEnvironment::TickRain(float Dt)
{
	APlayerCameraManager* PCM = UGameplayStatics::GetPlayerCameraManager(this, 0);
	const FVector Cam = PCM ? PCM->GetCameraLocation() : FVector::ZeroVector;
	if (RainDrops->GetInstanceCount() < GTARainCount) return;
	const bool bShow = Rain > 0.02f && !bUnderwater;
	if (!bShow)
	{
		if (RainDrops->IsVisible()) RainDrops->SetVisibility(false);
		if (RainAudio->IsPlaying()) RainAudio->Stop();
		return;
	}
	RainDrops->SetVisibility(true);
	if (!RainAudio->IsPlaying() && RainAudio->GetSound()) RainAudio->Play();
	RainAudio->SetVolumeMultiplier(0.15f + 0.6f * Rain);
	const FVector Wind(120.f * Storminess, 60.f, 0.f);
	const FVector Fall = FVector(Wind.X, Wind.Y, -1100.f);
	const FVector Dir = Fall.GetSafeNormal();
	const int32 Active = FMath::RoundToInt(GTARainCount * FMath::Clamp(Rain, 0.f, 1.f));
	TArray<FTransform> Ts;
	Ts.SetNumUninitialized(GTARainCount);
	const float Amb = AmbientFactor();
	for (int32 i = 0; i < GTARainCount; ++i)
	{
		FVector& P = RainPos[i];
		P += Fall * Dt;
		if (P.Z < -1200.f) P = FVector(FMath::FRandRange(-GTARainBox, GTARainBox), FMath::FRandRange(-GTARainBox, GTARainBox), 1500.f);
		if (P.X > GTARainBox) P.X -= 2.f * GTARainBox;
		if (P.X < -GTARainBox) P.X += 2.f * GTARainBox;
		if (P.Y > GTARainBox) P.Y -= 2.f * GTARainBox;
		if (P.Y < -GTARainBox) P.Y += 2.f * GTARainBox;
		const FVector W = Cam + P;
		if (i >= Active) { Ts[i] = FTransform(FQuat::Identity, FVector(0, 0, -100000.f), FVector::ZeroVector); continue; }
		const FVector ToCam = (Cam - W).GetSafeNormal();
		Ts[i] = FTransform(FRotationMatrix::MakeFromXZ(Dir, ToCam).ToQuat(), W, FVector(0.85f, 0.012f, 1.f));
		const float D[4] = { 0.55f * Amb + 0.05f, 0.6f * Amb + 0.05f, 0.68f * Amb + 0.06f, 0.32f };
		RainDrops->SetCustomData(i, MakeArrayView(D, 4), false);
	}
	RainDrops->BatchUpdateInstancesTransforms(0, Ts, true, true, true);
}

void AGTAEnvironment::Tick(float Dt)
{
	Super::Tick(Dt);
	if (!bTimeFrozen) TimeOfDay = FMath::Fmod(TimeOfDay + Dt * 24.f / (MinutesPerGameDay * 60.f), 24.f);
	if (UGTAGameInstance* GI = GTA::Instance(this)) GI->Profile.TimeOfDay = TimeOfDay;
	TickWeatherCycle(Dt);
	const float TOvercast = (Weather == EGTAWeather::Cloudy) ? 0.6f : (Weather == EGTAWeather::Rain ? 0.85f : (Weather == EGTAWeather::Storm ? 1.f : (Weather == EGTAWeather::Fog ? 0.5f : 0.f)));
	const float TRain = (Weather == EGTAWeather::Rain) ? 0.7f : (Weather == EGTAWeather::Storm ? 1.f : 0.f);
	const float TFog = (Weather == EGTAWeather::Fog) ? 1.f : (Weather == EGTAWeather::Storm ? 0.35f : (Weather == EGTAWeather::Rain ? 0.25f : 0.f));
	const float TStorm = Weather == EGTAWeather::Storm ? 1.f : 0.f;
	const float K = FMath::Clamp(Dt * 0.08f, 0.f, 1.f);
	Overcast = FMath::Lerp(Overcast, TOvercast, K);
	Rain = FMath::Lerp(Rain, TRain, K * 1.5f);
	FogAmount = FMath::Lerp(FogAmount, TFog, K);
	Storminess = FMath::Lerp(Storminess, TStorm, K);
	Wetness = Rain > 0.15f ? FMath::Min(1.f, Wetness + Dt * 0.06f * Rain) : FMath::Max(0.f, Wetness - Dt * 0.012f);

	if (Storminess > 0.5f)
	{
		LightningTimer -= Dt;
		if (LightningTimer <= 0.f)
		{
			LightningTimer = FMath::FRandRange(6.f, 16.f);
			LightningFlash = 1.f;
			GTA::Play2D(this, TEXT("S_Thunder"), 0.8f, FMath::FRandRange(0.85f, 1.1f));
		}
	}
	LightningFlash = FMath::Max(0.f, LightningFlash - Dt * 5.f);

	APlayerCameraManager* PCM = UGameplayStatics::GetPlayerCameraManager(this, 0);
	if (PCM)
	{
		const FVector C = PCM->GetCameraLocation();
		bUnderwater = AGTACity::IsWaterAt(C.X, C.Y) && C.Z < GTA::SeaLevel() + GTA::WaveHeight(this, C) - 5.f;
	}
	if (AmbienceAudio) AmbienceAudio->SetVolumeMultiplier(bUnderwater ? 0.05f : FMath::Lerp(0.35f, 0.18f, Night));
	ApplyLighting(Dt);
	TickRain(Dt);
}

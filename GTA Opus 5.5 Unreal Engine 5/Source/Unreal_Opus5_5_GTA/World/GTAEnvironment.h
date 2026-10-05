// Day/night cycle, weather, sky, fog, rain and global material parameters.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/GTATypes.h"
#include "GTAEnvironment.generated.h"

class UDirectionalLightComponent;
class USkyAtmosphereComponent;
class USkyLightComponent;
class UExponentialHeightFogComponent;
class UVolumetricCloudComponent;
class UPostProcessComponent;
class UInstancedStaticMeshComponent;
class UStaticMeshComponent;
class UAudioComponent;

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAEnvironment : public AActor
{
	GENERATED_BODY()
public:
	AGTAEnvironment();
	virtual void Tick(float DeltaSeconds) override;
	virtual void OnConstruction(const FTransform& Transform) override;

	UPROPERTY(EditAnywhere, Category = "GTA") float TimeOfDay = 9.5f;        // hours
	UPROPERTY(EditAnywhere, Category = "GTA") float MinutesPerGameDay = 30.f; // real minutes for 24 game hours
	UPROPERTY(EditAnywhere, Category = "GTA") bool bTimeFrozen = false;
	UPROPERTY(EditAnywhere, Category = "GTA") EGTAWeather Weather = EGTAWeather::Clear;
	bool bAutoWeather = true;

	void SetTimeOfDay(float Hours);
	void SetWeather(EGTAWeather W, bool bInstant = false);
	bool IsNight() const { return TimeOfDay < 6.4f || TimeOfDay > 19.6f; }
	float NightFactor() const { return Night; }
	float VisibilityFactor() const;
	float AmbientFactor() const { return FMath::Lerp(1.f, 0.22f, Night) * FMath::Lerp(1.f, 0.7f, Overcast); }
	float WaveAmplitude() const { return 1.f + 1.4f * Storminess; }
	float GetWetness() const { return Wetness; }
	float GetRain() const { return Rain; }
	FString TimeString() const;

	UPROPERTY(VisibleAnywhere) TObjectPtr<USceneComponent> Root;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UDirectionalLightComponent> Sun;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UDirectionalLightComponent> Moon;
	UPROPERTY(VisibleAnywhere) TObjectPtr<USkyAtmosphereComponent> Atmosphere;
	UPROPERTY(VisibleAnywhere) TObjectPtr<USkyLightComponent> SkyLight;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UExponentialHeightFogComponent> Fog;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UVolumetricCloudComponent> Clouds;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UPostProcessComponent> Post;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UInstancedStaticMeshComponent> RainDrops;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UAudioComponent> RainAudio;
	UPROPERTY(VisibleAnywhere) TObjectPtr<UAudioComponent> AmbienceAudio;

protected:
	virtual void BeginPlay() override;

private:
	void ApplyLighting(float Dt);
	void TickRain(float Dt);
	void TickWeatherCycle(float Dt);
	float Night = 0.f;
	float Overcast = 0.f;     // current blended values
	float Rain = 0.f;
	float FogAmount = 0.f;
	float Storminess = 0.f;
	float Wetness = 0.f;
	float NextWeatherChange = 300.f;
	float LightningTimer = 6.f;
	float LightningFlash = 0.f;
	TArray<FVector> RainPos;
	FVector RainCenter = FVector::ZeroVector;
	bool bUnderwater = false;
};

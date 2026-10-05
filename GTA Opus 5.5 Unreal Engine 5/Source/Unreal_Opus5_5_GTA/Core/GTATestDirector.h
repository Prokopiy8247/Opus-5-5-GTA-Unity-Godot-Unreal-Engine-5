// Automated in-game QA run (-gtatest): drives core systems and captures screenshots + log markers.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "GTATestDirector.generated.h"

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTATestDirector : public AActor
{
	GENERATED_BODY()
public:
	AGTATestDirector();
	virtual void Tick(float DeltaSeconds) override;

protected:
	virtual void BeginPlay() override;

private:
	void Shot(const FString& Name);
	void Mark(const FString& Msg);
	void RunStep(int32 Index);
	void DebugCam();
	void Check(bool bPassed, const FString& What);
	int32 ChecksPassed = 0;
	int32 ChecksFailed = 0;
	FString CheckReport;
	FVector WalkStart = FVector::ZeroVector;
	TArray<float> FrameTimes;
	double LastFrameWall = 0.0;
	int32 AmmoBefore = 0;
	bool bEscapeTest = false;
	int32 Step = -1;
	float NextStepTime = 0.f;
	float StepStart = 0.f;
	float WarmupEnd = 0.f;
	FString Only;
	FString OutDir;
	// -gtadebugcam=1 detaches a spectator camera above the city. Diagnostic only: it separates
	// "the renderer draws nothing" from "the player camera is buried in geometry".
	bool bDebugCam = false;
	bool bLightLog = false;
	bool bDiag = false;
	int32 DiagStep = 0;
	float DiagNext = 0.f;
	float LastLightLog = 0.f;
	TWeakObjectPtr<class ASpectatorPawn> CamPawn;
	TWeakObjectPtr<class AGTAVehicle> TestVehicle;
	FVector StartLoc = FVector::ZeroVector;
};

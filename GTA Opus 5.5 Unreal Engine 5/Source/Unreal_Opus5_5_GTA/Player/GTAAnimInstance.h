// Native (graph-less) animation instance: blends Blender-authored clips in a custom proxy.
#pragma once

#include "CoreMinimal.h"
#include "Animation/AnimInstance.h"
#include "Animation/AnimInstanceProxy.h"
#include "Core/GTATypes.h"
#include "GTAAnimInstance.generated.h"

class UAnimSequence;

UENUM()
enum class EGTAClip : uint8
{
	Idle, Walk, Run, Sprint, CrouchIdle, CrouchWalk, Jump, Fall, SwimIdle, Swim,
	Drive, Ride, Passenger, AimPistol, AimPistolUp, AimPistolDown, AimRifle, AimRifleUp, AimRifleDown,
	Punch, Punch2, Kick, Swing, Stab, Block, Throw, Reload, HandsUp, Cower, Climb, Vault,
	CoverHigh, CoverLow, Parachute, Freefall, Dodge, GetUp, Takedown, Phone, Hit, Sit,
	MAX UMETA(Hidden)
};

/** Game-thread snapshot of everything the animation needs. */
struct FGTAAnimState
{
	EGTAPoseMode Mode = EGTAPoseMode::Ground;
	float Speed = 0.f;            // horizontal cm/s
	float VerticalSpeed = 0.f;
	bool bCrouch = false;
	bool bAiming = false;
	bool bHoldingWeapon = false;
	bool bTwoHanded = false;
	float AimPitch = 0.f;         // degrees, + up
	float ClimbRate = 0.f;        // -1..1
	EGTAClip Action = EGTAClip::MAX;
	bool bActionUpper = true;
	float ActionRate = 1.f;
	int32 ActionSerial = 0;
	float AnimScale = 1.f;        // stride scale (character scale)
};

USTRUCT()
struct FGTAAnimProxy : public FAnimInstanceProxy
{
	GENERATED_BODY()

	FGTAAnimProxy() {}
	FGTAAnimProxy(UAnimInstance* Inst) : FAnimInstanceProxy(Inst) {}

	virtual void PreUpdate(UAnimInstance* InAnimInstance, float DeltaSeconds) override;
	virtual void Update(float DeltaSeconds) override;
	virtual bool Evaluate(FPoseContext& Output) override;

	TArray<UAnimSequence*> Clips;
	FGTAAnimState State;

private:
	float LocoPhase = 0.f;
	float ModeTime = 0.f;
	float AuxTime = 0.f;
	float ActionTime = 0.f;
	float ClimbTime = 0.f;
	int32 LastSerial = 0;
	bool bActionActive = false;
	float AimWeight = 0.f;
	float CrouchWeight = 0.f;
	EGTAPoseMode LastMode = EGTAPoseMode::Ground;
	float ModeBlend = 1.f;
	EGTAPoseMode PrevMode = EGTAPoseMode::Ground;

	void Sample(EGTAClip Clip, float Time, bool bLoop, FPoseContext& Out) const;
	void EvalBase(EGTAPoseMode Mode, FPoseContext& Out);
	float ClipLen(EGTAClip Clip) const;
};

UCLASS(Transient, NotBlueprintable)
class UNREAL_OPUS5_5_GTA_API UGTAAnimInstance : public UAnimInstance
{
	GENERATED_BODY()
public:
	FGTAAnimState State;

	/** One-shot clip (punch, throw, reload, ...). */
	void PlayAction(EGTAClip Clip, bool bUpperBody = true, float Rate = 1.f);
	float GetClipLength(EGTAClip Clip) const;
	static FString ClipName(EGTAClip Clip);

	UPROPERTY(Transient)
	TArray<TObjectPtr<UAnimSequence>> LoadedClips;

protected:
	virtual FAnimInstanceProxy* CreateAnimInstanceProxy() override;
	virtual void DestroyAnimInstanceProxy(FAnimInstanceProxy* InProxy) override;
	virtual void NativeInitializeAnimation() override;
	friend struct FGTAAnimProxy;
};

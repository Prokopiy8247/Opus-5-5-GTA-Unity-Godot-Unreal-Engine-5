#include "Player/GTAAnimInstance.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimNodeBase.h"
#include "Animation/AnimationPoseData.h"
#include "BonePose.h"

namespace
{
	bool IsUpperBone(const FName& N)
	{
		static const TSet<FName> S = {
			FName("spine_01"), FName("spine_02"), FName("spine_03"), FName("neck_01"), FName("head"),
			FName("clavicle_l"), FName("upperarm_l"), FName("lowerarm_l"), FName("hand_l"),
			FName("clavicle_r"), FName("upperarm_r"), FName("lowerarm_r"), FName("hand_r") };
		return S.Contains(N);
	}

	bool IsArmBone(const FName& N)
	{
		static const TSet<FName> S = {
			FName("spine_03"), FName("clavicle_l"), FName("upperarm_l"), FName("lowerarm_l"), FName("hand_l"),
			FName("clavicle_r"), FName("upperarm_r"), FName("lowerarm_r"), FName("hand_r"), FName("neck_01"), FName("head") };
		return S.Contains(N);
	}

	/** A = lerp(A, B, Alpha) for bones accepted by Mask (0 = all, 1 = upper, 2 = arms, 3 = all but root). */
	void BlendPose(FCompactPose& A, const FCompactPose& B, float Alpha, int32 Mask)
	{
		if (Alpha <= 0.001f) return;
		const FBoneContainer& BC = A.GetBoneContainer();
		const FReferenceSkeleton& Ref = BC.GetReferenceSkeleton();
		for (FCompactPoseBoneIndex I : A.ForEachBoneIndex())
		{
			if (Mask != 0)
			{
				const int32 MeshIdx = BC.MakeMeshPoseIndex(I).GetInt();
				const FName Name = Ref.GetBoneName(MeshIdx);
				if (Mask == 1 && !IsUpperBone(Name)) continue;
				if (Mask == 2 && !IsArmBone(Name)) continue;
				if (Mask == 3 && Name == FName("root")) continue;
			}
			if (Alpha >= 0.999f) { A[I] = B[I]; }
			else { A[I].BlendWith(B[I], Alpha); }
		}
	}

	struct FLocoClip { EGTAClip Clip; float Speed; };
}

FString UGTAAnimInstance::ClipName(EGTAClip Clip)
{
	const UEnum* E = StaticEnum<EGTAClip>();
	return TEXT("A_") + E->GetNameStringByValue((int64)Clip);
}

FAnimInstanceProxy* UGTAAnimInstance::CreateAnimInstanceProxy()
{
	return new FGTAAnimProxy(this);
}

void UGTAAnimInstance::DestroyAnimInstanceProxy(FAnimInstanceProxy* InProxy)
{
	delete InProxy;
}

void UGTAAnimInstance::NativeInitializeAnimation()
{
	Super::NativeInitializeAnimation();
	LoadedClips.SetNum((int32)EGTAClip::MAX);
	for (int32 i = 0; i < (int32)EGTAClip::MAX; ++i)
	{
		LoadedClips[i] = FGTAAssets::Anim(ClipName((EGTAClip)i));
	}
}

void UGTAAnimInstance::PlayAction(EGTAClip Clip, bool bUpperBody, float Rate)
{
	State.Action = Clip;
	State.bActionUpper = bUpperBody;
	State.ActionRate = Rate;
	State.ActionSerial++;
}

float UGTAAnimInstance::GetClipLength(EGTAClip Clip) const
{
	const int32 I = (int32)Clip;
	if (LoadedClips.IsValidIndex(I) && LoadedClips[I]) return LoadedClips[I]->GetPlayLength();
	return 0.5f;
}

// ------------------------------------------------------------------------------------------------- proxy

void FGTAAnimProxy::PreUpdate(UAnimInstance* InAnimInstance, float DeltaSeconds)
{
	FAnimInstanceProxy::PreUpdate(InAnimInstance, DeltaSeconds);
	if (UGTAAnimInstance* I = Cast<UGTAAnimInstance>(InAnimInstance))
	{
		State = I->State;
		Clips.SetNum(I->LoadedClips.Num());
		for (int32 i = 0; i < I->LoadedClips.Num(); ++i) Clips[i] = I->LoadedClips[i];
	}
}

float FGTAAnimProxy::ClipLen(EGTAClip Clip) const
{
	const int32 I = (int32)Clip;
	if (Clips.IsValidIndex(I) && Clips[I]) return FMath::Max(0.05f, Clips[I]->GetPlayLength());
	return 1.f;
}

void FGTAAnimProxy::Update(float Dt)
{
	if (State.Mode != LastMode)
	{
		PrevMode = LastMode;
		LastMode = State.Mode;
		ModeTime = 0.f;
		ModeBlend = 0.f;
	}
	ModeTime += Dt;
	AuxTime += Dt;
	ClimbTime = FMath::Max(0.f, ClimbTime + Dt * State.ClimbRate);
	ModeBlend = FMath::Min(1.f, ModeBlend + Dt / 0.22f);

	// locomotion phase (shared by walk/run/sprint/crouch/swim so cycles stay in sync)
	const float S = State.Speed / FMath::Max(0.5f, State.AnimScale);
	float CycleDur;
	if (State.Mode == EGTAPoseMode::Swim)
	{
		CycleDur = ClipLen(EGTAClip::Swim) * FMath::Clamp(250.f / FMath::Max(S, 60.f), 0.5f, 2.5f);
	}
	else if (State.bCrouch)
	{
		CycleDur = ClipLen(EGTAClip::CrouchWalk) * FMath::Clamp(150.f / FMath::Max(S, 30.f), 0.5f, 4.f);
	}
	else if (S < 145.f)
	{
		CycleDur = ClipLen(EGTAClip::Walk) * (145.f / FMath::Max(S, 30.f));
	}
	else if (S < 420.f)
	{
		const float A = (S - 145.f) / 275.f;
		CycleDur = FMath::Lerp(ClipLen(EGTAClip::Walk), ClipLen(EGTAClip::Run), A);
	}
	else if (S < 680.f)
	{
		const float A = (S - 420.f) / 260.f;
		CycleDur = FMath::Lerp(ClipLen(EGTAClip::Run), ClipLen(EGTAClip::Sprint), A);
	}
	else
	{
		CycleDur = ClipLen(EGTAClip::Sprint) * (680.f / S);
	}
	LocoPhase = FMath::Fmod(LocoPhase + Dt / FMath::Max(0.1f, CycleDur), 1.f);

	const bool bWantAim = State.bAiming || (State.bHoldingWeapon && State.bTwoHanded);
	AimWeight = FMath::FInterpConstantTo(AimWeight, bWantAim ? 1.f : 0.f, Dt, 8.f);
	CrouchWeight = FMath::FInterpConstantTo(CrouchWeight, State.bCrouch ? 1.f : 0.f, Dt, 6.f);

	if (State.ActionSerial != LastSerial)
	{
		LastSerial = State.ActionSerial;
		ActionTime = 0.f;
		bActionActive = State.Action != EGTAClip::MAX;
	}
	if (bActionActive)
	{
		ActionTime += Dt * State.ActionRate;
		if (ActionTime > ClipLen(State.Action)) bActionActive = false;
	}
}

void FGTAAnimProxy::Sample(EGTAClip Clip, float Time, bool bLoop, FPoseContext& Out) const
{
	const int32 I = (int32)Clip;
	UAnimSequence* Seq = Clips.IsValidIndex(I) ? Clips[I] : nullptr;
	if (!Seq)
	{
		Out.ResetToRefPose();
		return;
	}
	const float Len = FMath::Max(0.01f, Seq->GetPlayLength());
	const float T = bLoop ? FMath::Fmod(FMath::Max(0.f, Time), Len) : FMath::Clamp(Time, 0.f, Len);
	FAnimationPoseData PD(Out);
	Seq->GetAnimationPose(PD, FAnimExtractContext((double)T, false, FDeltaTimeRecord(), bLoop));
	// FBX animation tracks can contain unit root scale even when the imported skeleton uses
	// a centimetre conversion on its root. Preserve the bind-pose unit conversion while animating.
	for (FCompactPoseBoneIndex Bone : Out.Pose.ForEachBoneIndex())
	{
		Out.Pose[Bone].SetScale3D(Out.Pose.GetBoneContainer().GetRefPoseTransform(Bone).GetScale3D());
	}
}

void FGTAAnimProxy::EvalBase(EGTAPoseMode Mode, FPoseContext& Out)
{
	switch (Mode)
	{
	case EGTAPoseMode::Ground:
	case EGTAPoseMode::Cover:
	{
		const float S = State.Speed / FMath::Max(0.5f, State.AnimScale);
		static const FLocoClip Loco[] = { {EGTAClip::Idle, 0.f}, {EGTAClip::Walk, 145.f}, {EGTAClip::Run, 420.f}, {EGTAClip::Sprint, 680.f} };
		int32 Lo = 0;
		while (Lo < 3 && S > Loco[Lo + 1].Speed) ++Lo;
		auto ClipTime = [this](EGTAClip C) { return C == EGTAClip::Idle ? AuxTime : LocoPhase * ClipLen(C); };
		Sample(Loco[Lo].Clip, ClipTime(Loco[Lo].Clip), true, Out);
		if (Lo < 3)
		{
			const float A = FMath::Clamp((S - Loco[Lo].Speed) / (Loco[Lo + 1].Speed - Loco[Lo].Speed), 0.f, 1.f);
			if (A > 0.01f)
			{
				FPoseContext B(Out);
				Sample(Loco[Lo + 1].Clip, ClipTime(Loco[Lo + 1].Clip), true, B);
				BlendPose(Out.Pose, B.Pose, A, 0);
			}
		}
		if (CrouchWeight > 0.01f)
		{
			FPoseContext C(Out);
			Sample(EGTAClip::CrouchIdle, AuxTime, true, C);
			const float A = FMath::Clamp(S / 150.f, 0.f, 1.f);
			if (A > 0.01f)
			{
				FPoseContext D(Out);
				Sample(EGTAClip::CrouchWalk, LocoPhase * ClipLen(EGTAClip::CrouchWalk), true, D);
				BlendPose(C.Pose, D.Pose, A, 0);
			}
			BlendPose(Out.Pose, C.Pose, CrouchWeight, 0);
		}
		if (Mode == EGTAPoseMode::Cover)
		{
			FPoseContext C(Out);
			Sample(State.bCrouch ? EGTAClip::CoverLow : EGTAClip::CoverHigh, AuxTime, true, C);
			BlendPose(Out.Pose, C.Pose, S < 40.f ? 1.f : 0.5f, 0);
		}
		break;
	}
	case EGTAPoseMode::Air:
		if (State.VerticalSpeed > 50.f && ModeTime < ClipLen(EGTAClip::Jump)) Sample(EGTAClip::Jump, ModeTime, false, Out);
		else Sample(EGTAClip::Fall, ModeTime, true, Out);
		break;
	case EGTAPoseMode::Swim:
	{
		Sample(EGTAClip::SwimIdle, AuxTime, true, Out);
		const float A = FMath::Clamp(State.Speed / 200.f, 0.f, 1.f);
		if (A > 0.01f)
		{
			FPoseContext B(Out);
			Sample(EGTAClip::Swim, LocoPhase * ClipLen(EGTAClip::Swim), true, B);
			BlendPose(Out.Pose, B.Pose, A, 0);
		}
		break;
	}
	case EGTAPoseMode::SeatCar: Sample(EGTAClip::Drive, AuxTime, true, Out); break;
	case EGTAPoseMode::SeatBike: Sample(EGTAClip::Ride, AuxTime, true, Out); break;
	case EGTAPoseMode::SeatPassenger: Sample(EGTAClip::Passenger, AuxTime, true, Out); break;
	case EGTAPoseMode::Climb:
	{
		Sample(EGTAClip::Climb, ClimbTime, true, Out);
		break;
	}
	case EGTAPoseMode::Parachute: Sample(EGTAClip::Parachute, AuxTime, true, Out); break;
	case EGTAPoseMode::Freefall: Sample(EGTAClip::Freefall, AuxTime, true, Out); break;
	case EGTAPoseMode::HandsUp: Sample(EGTAClip::HandsUp, ModeTime, false, Out); break;
	case EGTAPoseMode::Cower: Sample(EGTAClip::Cower, AuxTime, true, Out); break;
	case EGTAPoseMode::Ragdoll:
	default:
		Sample(EGTAClip::Idle, AuxTime, true, Out);
		break;
	}
}

bool FGTAAnimProxy::Evaluate(FPoseContext& Output)
{
	EvalBase(State.Mode, Output);
	if (ModeBlend < 1.f && PrevMode != State.Mode)
	{
		FPoseContext Prev(Output);
		EvalBase(PrevMode, Prev);
		BlendPose(Prev.Pose, Output.Pose, ModeBlend, 0);
		Output.Pose.CopyBonesFrom(Prev.Pose);
	}

	// upper-body aim / weapon carry overlay
	const bool bSeated = State.Mode == EGTAPoseMode::SeatCar || State.Mode == EGTAPoseMode::SeatBike || State.Mode == EGTAPoseMode::SeatPassenger;
	const bool bCanOverlay = State.Mode == EGTAPoseMode::Ground || State.Mode == EGTAPoseMode::Cover || State.Mode == EGTAPoseMode::Air || (bSeated && State.bAiming);
	if (AimWeight > 0.01f && bCanOverlay && State.bHoldingWeapon)
	{
		const bool bRifle = State.bTwoHanded;
		const EGTAClip Mid = bRifle ? EGTAClip::AimRifle : EGTAClip::AimPistol;
		const EGTAClip Up = bRifle ? EGTAClip::AimRifleUp : EGTAClip::AimPistolUp;
		const EGTAClip Down = bRifle ? EGTAClip::AimRifleDown : EGTAClip::AimPistolDown;
		FPoseContext Aim(Output);
		if (State.bAiming)
		{
			Sample(Mid, 0.f, false, Aim);
			const float P = FMath::Clamp(State.AimPitch / 60.f, -1.f, 1.f);
			if (FMath::Abs(P) > 0.01f)
			{
				FPoseContext Ext(Output);
				Sample(P > 0.f ? Up : Down, 0.f, false, Ext);
				BlendPose(Aim.Pose, Ext.Pose, FMath::Abs(P), 0);
			}
		}
		else
		{
			Sample(Down, 0.f, false, Aim);
		}
		BlendPose(Output.Pose, Aim.Pose, AimWeight, bSeated ? 2 : 1);
	}

	// one-shot actions
	if (bActionActive && State.Action != EGTAClip::MAX)
	{
		const float Len = ClipLen(State.Action);
		const float In = FMath::Clamp(ActionTime / 0.08f, 0.f, 1.f);
		const float Out = FMath::Clamp((Len - ActionTime) / 0.15f, 0.f, 1.f);
		const float Wt = FMath::Min(In, Out);
		FPoseContext Act(Output);
		Sample(State.Action, ActionTime, false, Act);
		BlendPose(Output.Pose, Act.Pose, Wt, State.bActionUpper ? (bSeated ? 2 : 1) : 3);
	}
	return true;
}

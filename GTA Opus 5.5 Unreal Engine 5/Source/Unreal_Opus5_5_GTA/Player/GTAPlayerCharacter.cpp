#include "Player/GTAPlayerCharacter.h"
#include "Player/GTAPlayerController.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameInstance.h"
#include "AI/GTANPCController.h"
#include "Vehicles/GTAVehicle.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "NavigationInvokerComponent.h"
#include "Engine/DamageEvents.h"
#include "EngineUtils.h"

AGTAPlayerCharacter::AGTAPlayerCharacter(const FObjectInitializer& OI) : Super(OI)
{
	PedRole = EGTAPedRole::Player;
	AutoPossessAI = EAutoPossessAI::Disabled;
	AIControllerClass = nullptr;

	CamBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CamBoom"));
	CamBoom->SetupAttachment(GetCapsuleComponent());
	CamBoom->SetRelativeLocation(FVector(0.f, 0.f, 55.f));
	CamBoom->TargetArmLength = BaseArm;
	CamBoom->bUsePawnControlRotation = true;
	CamBoom->bDoCollisionTest = true;
	CamBoom->ProbeSize = 14.f;
	CamBoom->ProbeChannel = ECC_Camera;
	CamBoom->bEnableCameraLag = true;
	CamBoom->CameraLagSpeed = 14.f;
	CamBoom->SocketOffset = FVector(0.f, 45.f, 25.f);

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(CamBoom, USpringArmComponent::SocketName);
	Camera->SetFieldOfView(80.f);
	Camera->bUsePawnControlRotation = false;

	NavInvoker = CreateDefaultSubobject<UNavigationInvokerComponent>(TEXT("NavInvoker"));
	NavInvoker->SetGenerationRadii(7000.f, 9000.f);

	ParachuteCanopy = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ParachuteCanopy"));
	ParachuteCanopy->SetupAttachment(GetCapsuleComponent());
	// The authored canopy includes suspension lines down to the character's feet origin.
	ParachuteCanopy->SetRelativeLocation(FVector(0.f, 0.f, -92.f));
	ParachuteCanopy->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	ParachuteCanopy->SetVisibility(false);

	UCharacterMovementComponent* CM = GetCharacterMovement();
	CM->MaxAcceleration = 2400.f;
	CM->BrakingFrictionFactor = 1.5f;
	CM->AirControl = 0.35f;
	BreathCapacity = 25.f;
}

void AGTAPlayerCharacter::BeginPlay()
{
	Super::BeginPlay();
	if (UStaticMesh* C = FGTAAssets::GenMesh(TEXT("Characters/Acc"), TEXT("SM_Parachute_Canopy"))) ParachuteCanopy->SetStaticMesh(C);
}

// ------------------------------------------------------------------------------------------------ profile

void AGTAPlayerCharacter::LoadFromProfile()
{
	UGTAGameInstance* GI = GTA::Instance(this);
	if (!GI) return;
	Appearance = GI->Profile.Appearance;
	ApplyAppearance();
	if (GI->Profile.Weapons.Num() > 0) Weapons = GI->Profile.Weapons;
	CurrentSlot = 0;
	Health = FMath::Clamp(GI->Profile.Health, 30.f, MaxHealth);
	Armor = GI->Profile.Armor;
	SetHasParachute(GI->Profile.bHasParachute);
	UpdateWeaponVisual();
	if (GI->Profile.bHasPlayerTransform)
	{
		if (AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetController()))
		{
			if (IsInVehicle()) PC->ExitVehicle(true);
			PC->SetControlRotation(GI->Profile.PlayerTransform.Rotator());
		}
		SetActorTransform(GI->Profile.PlayerTransform, false, nullptr, ETeleportType::TeleportPhysics);
	}
}

void AGTAPlayerCharacter::SaveToProfile()
{
	UGTAGameInstance* GI = GTA::Instance(this);
	if (!GI) return;
	GI->Profile.Appearance = Appearance;
	GI->Profile.Weapons = Weapons;
	GI->Profile.Health = Health;
	GI->Profile.Armor = Armor;
	GI->Profile.bHasParachute = bHasParachute;
	GI->Profile.PlayerTransform = GetActorTransform();
	if (Vehicle) GI->Profile.PlayerTransform.SetLocation(Vehicle->GetDoorLocation(0) + FVector(0,0,110.f));
	GI->Profile.bHasPlayerTransform = true;
}

void AGTAPlayerCharacter::SetHasParachute(bool b)
{
	bHasParachute = b;
	if (BackMesh)
	{
		UStaticMesh* M = b ? FGTAAssets::GenMesh(TEXT("Characters/Acc"), TEXT("SM_Parachute_Pack")) : (bScuba ? FGTAAssets::GenMesh(TEXT("Characters/Acc"), TEXT("SM_Scuba_Tank")) : nullptr);
		BackMesh->SetStaticMesh(M);
		BackMesh->SetVisibility(M != nullptr);
	}
}

void AGTAPlayerCharacter::SetScuba(bool b)
{
	bScuba = b;
	if (BackMesh && !bHasParachute)
	{
		UStaticMesh* M = b ? FGTAAssets::GenMesh(TEXT("Characters/Acc"), TEXT("SM_Scuba_Tank")) : nullptr;
		BackMesh->SetStaticMesh(M);
		BackMesh->SetVisibility(M != nullptr);
	}
	if (b) Breath = 1.f;
}

// ------------------------------------------------------------------------------------------------ damage

float AGTAPlayerCharacter::TakeDamage(float Damage, FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser)
{
	UGTAGameInstance* GI = GTA::Instance(this);
	if (bInvulnerable || (GI && GI->bInvulnerable)) return 0.f;
	if (bBlocking && !IsInVehicle() && DamageEvent.DamageTypeClass == UGTADamage_Melee::StaticClass()) Damage *= 0.35f;
	LastAttackedTime = GetWorld()->GetTimeSeconds();
	// player is a little tougher than NPCs (difficulty tuning)
	return Super::TakeDamage(Damage * 0.7f, DamageEvent, EventInstigator, DamageCauser);
}

void AGTAPlayerCharacter::Landed(const FHitResult& Hit)
{
	if (bParachuteOpen)
	{
		bParachuteOpen = false;
		ParachuteCanopy->SetVisibility(false);
		SetHasParachute(false);
		bForcePose = false;
		FallStartZ = GetActorLocation().Z;
		GetCharacterMovement()->GravityScale = 1.f;
		PlayAction(EGTAClip::GetUp, false, 1.6f);
	}
	if (bForcePose && ForcedPose == EGTAPoseMode::Freefall) bForcePose = false;
	Super::Landed(Hit);
}

// ------------------------------------------------------------------------------------------------ aim

FVector AGTAPlayerCharacter::GetAimOrigin() const
{
	return Camera ? Camera->GetComponentLocation() : Super::GetAimOrigin();
}

FVector AGTAPlayerCharacter::GetAimTarget() const
{
	return CachedAimPoint.IsZero() ? Super::GetAimTarget() : CachedAimPoint;
}

void AGTAPlayerCharacter::UpdateAimTrace()
{
	const APlayerController* PC = Cast<APlayerController>(GetController());
	FVector From;
	FRotator Rot;
	if (PC && PC->PlayerCameraManager)
	{
		From = PC->PlayerCameraManager->GetCameraLocation();
		Rot = PC->PlayerCameraManager->GetCameraRotation();
	}
	else if (Vehicle && Vehicle->Camera)
	{
		From = Vehicle->Camera->GetComponentLocation();
		Rot = Vehicle->Camera->GetComponentRotation();
	}
	else return;
	const FVector Dir = Rot.Vector();
	// start the trace beyond the character so walls behind the camera are ignored
	const float Skip = FMath::Max(0.f, FVector::DotProduct(GetActorLocation() - From, Dir));
	const FVector Start = From + Dir * Skip;
	const FVector End = From + Dir * 12000.f;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAPlayerAim), true, this);
	if (Vehicle) Q.AddIgnoredActor(Vehicle);
	FHitResult H;
	if (GetWorld()->LineTraceSingleByChannel(H, Start, End, GTA_ECC_WEAPON, Q))
	{
		CachedAimPoint = H.ImpactPoint;
		CachedAimActor = H.GetActor();
	}
	else
	{
		CachedAimPoint = End;
		CachedAimActor = nullptr;
	}
	const FVector MuzzleDir = CachedAimPoint - (GetActorLocation() + FVector(0, 0, 60.f));
	AimPitch = FMath::RadiansToDegrees(FMath::Atan2(MuzzleDir.Z, MuzzleDir.Size2D()));
	// NPCs react to a gun pointed at them (hands up, robbery, police aggression)
	AimNotifyTimer -= GetWorld()->GetDeltaSeconds();
	if (bAiming && AimNotifyTimer <= 0.f && CurrentDef().Cat != EGTAWeaponCat::Melee)
	{
		AimNotifyTimer = 0.4f;
		if (AGTACharacter* C = Cast<AGTACharacter>(CachedAimActor))
		{
			if (!C->bDead && FVector::Dist(C->GetActorLocation(), GetActorLocation()) < 2500.f)
			{
				if (AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController())) AIC->OnAimedAt(this);
			}
		}
	}
}

// ------------------------------------------------------------------------------------------------ input

void AGTAPlayerCharacter::InputMove(const FVector2D& Axis)
{
	MoveInput = Axis;
	if (bDead || IsInVehicle() || bRagdoll || VaultUntil > 0.f) return;
	const FRotator Yaw(0.f, GetControlRotation().Yaw, 0.f);
	const FVector Fwd = Yaw.Vector();
	const FVector Right = FRotationMatrix(Yaw).GetScaledAxis(EAxis::Y);
	if (bInCover) return;   // handled in UpdateCover
	if (bParachuteOpen) return;
	AddMovementInput(Fwd, Axis.Y);
	AddMovementInput(Right, Axis.X);
}

void AGTAPlayerCharacter::InputLook(const FVector2D& Axis)
{
	UGTAGameInstance* GI = GTA::Instance(this);
	const float Sens = (GI ? GI->MouseSensitivity : 1.f) * (IsScoped() ? ScopeZoom / 80.f : (bAiming ? 0.7f : 1.f));
	const float Inv = (GI && GI->bInvertY) ? -1.f : 1.f;
	AddControllerYawInput(Axis.X * Sens);
	AddControllerPitchInput(-Axis.Y * Sens * Inv);
}

void AGTAPlayerCharacter::InputJump()
{
	if (bDead || IsInVehicle() || bRagdoll) return;
	if (bInCover)
	{
		if (bCoverLow) { LeaveCover(); TryVault(); }
		return;
	}
	if (IsSwimming()) { LaunchCharacter(FVector(0, 0, 420.f), false, true); return; }
	if (GetCharacterMovement()->IsFalling()) { InputParachute(); return; }
	if (!TryVault()) Jump();
}

void AGTAPlayerCharacter::InputCrouch()
{
	if (IsInVehicle() || bDead) return;
	SetStealth(!bStealth);
}

void AGTAPlayerCharacter::InputCover()
{
	if (bInCover) LeaveCover();
	else EnterCover();
}

void AGTAPlayerCharacter::InputDodge()
{
	if (bDead || IsInVehicle() || GetCharacterMovement()->IsFalling()) return;
	FVector Dir = GetLastMovementInputVector().GetSafeNormal2D();
	if (Dir.IsNearlyZero()) Dir = -GetActorForwardVector();
	LaunchCharacter(Dir * 650.f + FVector(0, 0, 120.f), true, false);
	PlayAction(EGTAClip::Dodge, false, 1.3f);
	GTA::Play3D(this, TEXT("S_Swish"), GetActorLocation(), 0.4f, 0.8f);
}

bool AGTAPlayerCharacter::InputParachute()
{
	if (bDead || bRagdoll) return false;
	if (!GetCharacterMovement()->IsFalling() || IsInVehicle()) return false;
	if (bParachuteOpen)
	{
		bParachuteOpen = false;
		ParachuteCanopy->SetVisibility(false);
		GetCharacterMovement()->GravityScale = 1.f;
		SetHasParachute(false);
		bForcePose = false;
		return true;
	}
	if (!bHasParachute) return false;
	FHitResult H;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAChuteAGL), false, this);
	const bool bGround = GetWorld()->LineTraceSingleByChannel(H, GetActorLocation(), GetActorLocation() - FVector(0, 0, 1500.f), ECC_Visibility, Q);
	if (bGround) return false;   // too low to deploy
	bParachuteOpen = true;
	ParachuteCanopy->SetVisibility(ParachuteCanopy->GetStaticMesh() != nullptr);
	bForcePose = true;
	ForcedPose = EGTAPoseMode::Parachute;
	GetCharacterMovement()->Velocity *= 0.3f;
	GTA::Play3D(this, TEXT("S_ChuteOpen"), GetActorLocation(), 0.9f);
	return true;
}

bool AGTAPlayerCharacter::IsFreefalling() const
{
	return GetCharacterMovement()->IsFalling() && !bParachuteOpen && GetVelocity().Z < -1400.f;
}

// ------------------------------------------------------------------------------------------------ traversal

bool AGTAPlayerCharacter::TryVault()
{
	const FVector Fwd = GetActorForwardVector();
	const FVector Feet = GetActorLocation() - FVector(0, 0, 92.f);
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAVault), false, this);
	FHitResult Wall;
	if (!GetWorld()->LineTraceSingleByChannel(Wall, Feet + FVector(0, 0, 45.f), Feet + FVector(0, 0, 45.f) + Fwd * 110.f, ECC_Visibility, Q)) return false;
	if (FMath::Abs(Wall.ImpactNormal.Z) > 0.4f) return false;
	FHitResult Top;
	const FVector Probe = Wall.ImpactPoint - Wall.ImpactNormal * 35.f;
	if (!GetWorld()->LineTraceSingleByChannel(Top, Probe + FVector(0, 0, 230.f), FVector(Probe.X, Probe.Y, Feet.Z + 25.f), ECC_Visibility, Q)) return false;
	const float H = Top.ImpactPoint.Z - Feet.Z;
	if (H < 40.f || H > 200.f || Top.ImpactNormal.Z < 0.7f) return false;
	// land beyond a thin obstacle (vault) or on top of a wide one (climb)
	FHitResult Beyond;
	const FVector Far = Probe - Wall.ImpactNormal * 80.f;
	const bool bThin = !GetWorld()->LineTraceSingleByChannel(Beyond, Far + FVector(0, 0, H + 20.f), Far - FVector(0, 0, 10.f) + FVector(0, 0, H - 30.f), ECC_Visibility, Q);
	FVector Dest = bThin ? Far + FVector(0, 0, 0.f) : Top.ImpactPoint;
	if (bThin)
	{
		FHitResult Down;
		if (GetWorld()->LineTraceSingleByChannel(Down, FVector(Far.X, Far.Y, Top.ImpactPoint.Z + 20.f), FVector(Far.X, Far.Y, Feet.Z - 300.f), ECC_Visibility, Q)) Dest = Down.ImpactPoint;
	}
	Dest += FVector(0, 0, 95.f);
	if (GetWorld()->OverlapAnyTestByChannel(Dest, FQuat::Identity, ECC_Pawn, FCollisionShape::MakeCapsule(30.f, 85.f), Q)) return false;
	VaultStart = GetActorLocation();
	VaultTarget = Dest;
	VaultDuration = H > 120.f ? 0.75f : 0.45f;
	VaultT = 0.f;
	VaultUntil = 1.f;
	GetCharacterMovement()->SetMovementMode(MOVE_Flying);
	GetCharacterMovement()->StopMovementImmediately();
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	PlayAction(H > 120.f ? EGTAClip::Climb : EGTAClip::Vault, false, H > 120.f ? 1.4f : 1.6f);
	return true;
}

// ------------------------------------------------------------------------------------------------ cover

void AGTAPlayerCharacter::EnterCover()
{
	if (IsInVehicle() || bDead || GetCharacterMovement()->IsFalling()) return;
	const FVector Base = GetActorLocation();
	FVector Dir = FRotator(0.f, GetControlRotation().Yaw, 0.f).Vector();
	if (!GetLastMovementInputVector().IsNearlyZero()) Dir = GetLastMovementInputVector().GetSafeNormal2D();
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTACover), false, this);
	FHitResult H;
	bool bHit = false;
	for (float Ang : { 0.f, -35.f, 35.f, -70.f, 70.f })
	{
		const FVector D = Dir.RotateAngleAxis(Ang, FVector::UpVector);
		if (GetWorld()->LineTraceSingleByChannel(H, Base - FVector(0, 0, 30.f), Base - FVector(0, 0, 30.f) + D * 220.f, ECC_Visibility, Q) && FMath::Abs(H.ImpactNormal.Z) < 0.35f)
		{
			bHit = true;
			break;
		}
	}
	if (!bHit) { GTA::Notify(this, TEXT("No cover nearby"), 1.2f); return; }
	CoverNormal = FVector(H.ImpactNormal.X, H.ImpactNormal.Y, 0.f).GetSafeNormal();
	CoverPoint = H.ImpactPoint;
	FHitResult High;
	bCoverLow = !GetWorld()->LineTraceSingleByChannel(High, Base + FVector(0, 0, 55.f), Base + FVector(0, 0, 55.f) - CoverNormal * 260.f, ECC_Visibility, Q);
	bInCover = true;
	const FVector Snap = FVector(CoverPoint.X, CoverPoint.Y, Base.Z) + CoverNormal * 45.f;
	SetActorLocation(Snap, true);
	SetActorRotation(FRotator(0.f, (-CoverNormal).Rotation().Yaw, 0.f));
	GetCharacterMovement()->bOrientRotationToMovement = false;
	if (bCoverLow) Crouch();
	GTA::Play3D(this, TEXT("S_Cloth"), GetActorLocation(), 0.4f);
}

void AGTAPlayerCharacter::LeaveCover()
{
	if (!bInCover) return;
	bInCover = false;
	bBlindFire = false;
	AccuracyMult = 1.f;
	GetCharacterMovement()->bOrientRotationToMovement = !bAiming;
	if (!bStealth) UnCrouch();
}

void AGTAPlayerCharacter::UpdateCover(float Dt)
{
	if (!bInCover) return;
	if (IsInVehicle() || bDead || bRagdoll) { LeaveCover(); return; }
	const FRotator Yaw(0.f, GetControlRotation().Yaw, 0.f);
	const FVector Want = Yaw.Vector() * MoveInput.Y + FRotationMatrix(Yaw).GetScaledAxis(EAxis::Y) * MoveInput.X;
	if (FVector::DotProduct(Want, CoverNormal) > 0.75f) { LeaveCover(); return; }
	const FVector Tangent = FVector::CrossProduct(FVector::UpVector, CoverNormal);
	const float Side = FVector::DotProduct(Want, Tangent);
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTACoverSlide), false, this);
	if (FMath::Abs(Side) > 0.2f && !bAiming)
	{
		// only slide while there is still cover in that direction (stop at corners)
		const FVector Ahead = GetActorLocation() + Tangent * FMath::Sign(Side) * 45.f - FVector(0, 0, 30.f);
		FHitResult H;
		if (GetWorld()->LineTraceSingleByChannel(H, Ahead, Ahead - CoverNormal * 120.f, ECC_Visibility, Q))
		{
			AddMovementInput(Tangent * FMath::Sign(Side), 0.55f);
			CoverNormal = FMath::Lerp(CoverNormal, FVector(H.ImpactNormal.X, H.ImpactNormal.Y, 0.f).GetSafeNormal(), 0.2f).GetSafeNormal();
		}
	}
	// pop out: stand up over low cover while aiming, blind fire otherwise
	if (bCoverLow)
	{
		if (bAiming && bIsCrouched) UnCrouch();
		else if (!bAiming && !bIsCrouched) Crouch();
	}
	bBlindFire = IsTriggerHeld() && !bAiming;
	AccuracyMult = bBlindFire ? 3.f : 1.f;
	if (!bAiming) SetActorRotation(FMath::RInterpTo(GetActorRotation(), FRotator(0.f, (-CoverNormal).Rotation().Yaw, 0.f), Dt, 10.f));
}

// ------------------------------------------------------------------------------------------------ parachute

void AGTAPlayerCharacter::UpdateParachute(float Dt)
{
	UCharacterMovementComponent* CM = GetCharacterMovement();
	if (bParachuteOpen)
	{
		if (!CM->IsFalling()) return;
		const float Turn = MoveInput.X * 70.f * Dt;
		AddActorWorldRotation(FRotator(0.f, Turn, 0.f));
		const float Glide = FMath::Lerp(650.f, 1300.f, (MoveInput.Y + 1.f) * 0.5f);
		const float Sink = FMath::Lerp(600.f, 300.f, (MoveInput.Y + 1.f) * 0.5f);
		const FVector V = GetActorForwardVector() * Glide;
		CM->Velocity = FVector(V.X, V.Y, FMath::Max(CM->Velocity.Z, -Sink));
		CM->Velocity.Z = FMath::FInterpTo(CM->Velocity.Z, -Sink, Dt, 2.f);
		return;
	}
	if (IsFreefalling())
	{
		FHitResult H;
		FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAFreefall), false, this);
		const bool bNear = GetWorld()->LineTraceSingleByChannel(H, GetActorLocation(), GetActorLocation() - FVector(0, 0, 2500.f), ECC_Visibility, Q);
		if (!bNear && !bForcePose) { bForcePose = true; ForcedPose = EGTAPoseMode::Freefall; }
		if (bForcePose && ForcedPose == EGTAPoseMode::Freefall)
		{
			const FRotator Yaw(0.f, GetControlRotation().Yaw, 0.f);
			CM->Velocity += (Yaw.Vector() * MoveInput.Y + FRotationMatrix(Yaw).GetScaledAxis(EAxis::Y) * MoveInput.X) * 900.f * Dt;
			SetActorRotation(FMath::RInterpTo(GetActorRotation(), Yaw, Dt, 3.f));
		}
	}
}

// ------------------------------------------------------------------------------------------------ vehicles

AGTAVehicle* AGTAPlayerCharacter::FindVehicleToEnter(int32& OutSeat) const
{
	AGTAVehicle* Best = nullptr;
	float BestD = 450.f;
	OutSeat = 0;
	for (TActorIterator<AGTAVehicle> It(GetWorld()); It; ++It)
	{
		AGTAVehicle* V = *It;
		if (V->bDestroyed) continue;
		if (FVector::Dist(V->GetActorLocation(), GetActorLocation()) > 1500.f) continue;
		for (int32 s = 0; s < V->NumSeats(); ++s)
		{
			// called cabs: the passenger uses the rear seats instead of jacking the driver
			const AGTACharacter* Dr = V->GetDriver();
			if (s == 0 && V->GetDef().bTaxi && Dr && !Dr->bDead && !Dr->IsPlayerCharacter() && V->NumSeats() > 1) continue;
			const float D = FVector::Dist2D(V->GetDoorLocation(s), GetActorLocation());
			const float Bias = s == 0 ? 0.f : 60.f;   // prefer the driver seat
			if (D + Bias < BestD)
			{
				BestD = D + Bias;
				Best = V;
				OutSeat = s;
			}
		}
	}
	return Best;
}

// ------------------------------------------------------------------------------------------------ camera

void AGTAPlayerCharacter::ToggleFirstPerson()
{
	bFirstPersonView = !bFirstPersonView;
	GetMesh()->SetOwnerNoSee(bFirstPersonView);
	for (UStaticMeshComponent* C : { HairMesh.Get(), HatMesh.Get(), GlassesMesh.Get(), BeardMesh.Get() }) if (C) C->SetOwnerNoSee(bFirstPersonView);
}

void AGTAPlayerCharacter::UpdateCamera(float Dt)
{
	float Arm = BaseArm, Fov = 80.f;
	FVector Offset(0.f, 45.f * ShoulderSide, 25.f);
	ScopeZoom = 0.f;
	if (bAiming)
	{
		const FGTAWeaponDef& D = CurrentDef();
		const FGTAWeaponSlot* S = Weapons.IsValidIndex(CurrentSlot) ? &Weapons[CurrentSlot] : nullptr;
		Arm = 150.f;
		Offset = FVector(0.f, 62.f * ShoulderSide, 52.f);
		Fov = 62.f;
		if (D.ScopeFOV > 0.f) ScopeZoom = D.ScopeFOV;
		else if (S && S->HasMod(EGTAWeaponMod::Scope)) ScopeZoom = 35.f;
		if (ScopeZoom > 0.f) { Fov = ScopeZoom; Arm = 60.f; }
	}
	else if (bInCover) { Arm = 260.f; Offset = FVector(0.f, 70.f * ShoulderSide, bCoverLow ? 10.f : 35.f); }
	else if (bSprinting && GetVelocity().Size2D() > 500.f) { Arm = 370.f; Fov = 86.f; }
	if (bParachuteOpen || IsFreefalling()) { Arm = 520.f; Fov = 88.f; Offset = FVector(0.f, 0.f, 80.f); }
	if (IsSwimming()) { Arm = 380.f; Offset.Z = 60.f; }
	if (bFirstPersonView)
	{
		Arm = 0.f;
		Offset = FVector(18.f, 0.f, 72.f - 55.f);
		CamBoom->bDoCollisionTest = false;
	}
	else CamBoom->bDoCollisionTest = true;
	const float K = FMath::Clamp(Dt * 10.f, 0.f, 1.f);
	CamBoom->TargetArmLength = FMath::Lerp(CamBoom->TargetArmLength, Arm, K);
	CamBoom->SocketOffset = FMath::Lerp(CamBoom->SocketOffset, Offset, K);
	CamBoom->bEnableCameraLag = !bAiming && !bFirstPersonView;
	Camera->SetFieldOfView(FMath::Lerp(Camera->FieldOfView, Fov, K));
	// shake
	CameraShake = FMath::FInterpTo(CameraShake, 0.f, Dt, 4.f);
	const float S = CameraShake * 6.f;
	Camera->SetRelativeLocation(FVector(0.f, FMath::FRandRange(-S, S), FMath::FRandRange(-S, S)));
}

// ------------------------------------------------------------------------------------------------ tick

void AGTAPlayerCharacter::TickRegen(float Dt)
{
	if (bDead) return;
	if (GetWorld()->GetTimeSeconds() - LastAttackedTime > 8.f && Health < MaxHealth * 0.5f) Health = FMath::Min(MaxHealth * 0.5f, Health + 2.5f * Dt);
	if (bSprinting && GetVelocity().Size2D() > 400.f) GTA::AddSkill(this, EGTASkill::Stamina, Dt * 0.0012f);
	if (IsSwimming()) GTA::AddSkill(this, EGTASkill::Lung, Dt * 0.0005f);
}

void AGTAPlayerCharacter::Tick(float Dt)
{
	Super::Tick(Dt);
	if (VaultUntil > 0.f)
	{
		VaultT += Dt / VaultDuration;
		const float T = FMath::Clamp(VaultT, 0.f, 1.f);
		const float Arc = FMath::Sin(T * PI) * 40.f;
		const FVector P = FMath::Lerp(VaultStart, VaultTarget, FMath::SmoothStep(0.f, 1.f, T)) + FVector(0, 0, Arc + FMath::Max(0.f, (VaultTarget.Z - VaultStart.Z)) * (T < 0.5f ? T : 0.f));
		SetActorLocation(P);
		if (T >= 1.f)
		{
			VaultUntil = 0.f;
			GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
			GetCharacterMovement()->SetMovementMode(MOVE_Walking);
			FallStartZ = GetActorLocation().Z;
		}
	}
	if (!IsInVehicle()) UpdateAimTrace();
	else UpdateAimTrace();
	UpdateCover(Dt);
	UpdateParachute(Dt);
	UpdateCamera(Dt);
	TickRegen(Dt);
	// swimming: dive down while crouch/stealth is held
	if (IsSwimming())
	{
		if (bStealth) AddMovementInput(FVector::DownVector, 0.8f);
		if (bIsCrouched) UnCrouch();
	}
	// contextual prompt
	InteractPrompt.Reset();
	if (!IsInVehicle() && !bDead)
	{
		int32 Seat = 0;
		if (AGTAVehicle* V = FindVehicleToEnter(Seat))
		{
			const AGTACharacter* Dr = V->GetDriver();
			InteractPrompt = FString::Printf(TEXT("F  %s %s"), (Seat == 0 && Dr && !Dr->bDead) ? TEXT("Carjack") : TEXT("Enter"), *V->GetDef().Name);
		}
	}
}

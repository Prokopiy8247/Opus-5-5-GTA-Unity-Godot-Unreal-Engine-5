#include "Player/GTACharacter.h"
#include "Core/GTAGame.h"
#include "Vehicles/GTAVehicle.h"
#include "AI/GTANPCController.h"
#include "Weapons/GTAProjectile.h"
#include "World/GTAPickup.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/AudioComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PhysicsVolume.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/DamageEvents.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"

AGTACharacter::AGTACharacter(const FObjectInitializer& OI) : Super(OI)
{
	PrimaryActorTick.bCanEverTick = true;
	GetCapsuleComponent()->InitCapsuleSize(34.f, 92.f);
	GetCapsuleComponent()->SetCollisionResponseToChannel(GTA_ECC_WEAPON, ECR_Ignore);

	USkeletalMeshComponent* M = GetMesh();
	static ConstructorHelpers::FObjectFinder<USkeletalMesh> DefaultBody(TEXT("/Game/GTA/Generated/Characters/Centimetres/SK_Human_M.SK_Human_M"));
	if (DefaultBody.Succeeded()) M->SetSkeletalMesh(DefaultBody.Object);
	M->SetRelativeLocation(FVector(0.f, 0.f, -92.f));
	M->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	M->SetCollisionObjectType(ECC_Pawn);
	M->SetCollisionResponseToAllChannels(ECR_Ignore);
	M->SetCollisionResponseToChannel(GTA_ECC_WEAPON, ECR_Block);
	M->SetGenerateOverlapEvents(false);
	M->SetAnimationMode(EAnimationMode::AnimationBlueprint);
	M->AnimClass = UGTAAnimInstance::StaticClass();
	M->VisibilityBasedAnimTickOption = EVisibilityBasedAnimTickOption::OnlyTickPoseWhenRendered;

	UCharacterMovementComponent* CM = GetCharacterMovement();
	CM->bOrientRotationToMovement = true;
	CM->RotationRate = FRotator(0.f, 600.f, 0.f);
	CM->MaxWalkSpeed = 420.f;
	CM->MaxWalkSpeedCrouched = 160.f;
	CM->JumpZVelocity = 470.f;
	CM->AirControl = 0.3f;
	CM->MaxSwimSpeed = 330.f;
	CM->Buoyancy = 1.08f;
	CM->BrakingDecelerationWalking = 1500.f;
	CM->GetNavAgentPropertiesRef().bCanCrouch = true;
	CM->GetNavAgentPropertiesRef().bCanSwim = true;
	CM->bCanWalkOffLedgesWhenCrouching = true;
	CM->SetCrouchedHalfHeight(62.f);
	bUseControllerRotationYaw = false;

	WeaponMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("WeaponMesh"));
	WeaponMesh->SetupAttachment(M, TEXT("hand_r"));
	WeaponMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	ModSuppressor = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ModSuppressor"));
	ModSuppressor->SetupAttachment(WeaponMesh);
	ModScope = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ModScope"));
	ModScope->SetupAttachment(WeaponMesh);
	ModLight = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ModLight"));
	ModLight->SetupAttachment(WeaponMesh);
	for (UStaticMeshComponent* C : { ModSuppressor.Get(), ModScope.Get(), ModLight.Get() })
	{
		C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		C->SetVisibility(false);
	}
	Flashlight = CreateDefaultSubobject<USpotLightComponent>(TEXT("Flashlight"));
	Flashlight->SetupAttachment(WeaponMesh);
	Flashlight->SetVisibility(false);
	Flashlight->Intensity = 60000.f;
	Flashlight->AttenuationRadius = 3500.f;
	Flashlight->OuterConeAngle = 22.f;
	Flashlight->InnerConeAngle = 10.f;
	Flashlight->SetCastShadows(false);

	auto MakeAcc = [this, M](const TCHAR* Name, FName Bone)
	{
		UStaticMeshComponent* C = CreateDefaultSubobject<UStaticMeshComponent>(Name);
		C->SetupAttachment(M, Bone);
		C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		C->SetVisibility(false);
		return C;
	};
	HairMesh = MakeAcc(TEXT("Hair"), TEXT("head"));
	HatMesh = MakeAcc(TEXT("Hat"), TEXT("head"));
	GlassesMesh = MakeAcc(TEXT("Glasses"), TEXT("head"));
	BeardMesh = MakeAcc(TEXT("Beard"), TEXT("head"));
	VestMesh = MakeAcc(TEXT("Vest"), TEXT("spine_03"));
	BackMesh = MakeAcc(TEXT("Back"), TEXT("spine_03"));

	VoiceAudio = CreateDefaultSubobject<UAudioComponent>(TEXT("Voice"));
	VoiceAudio->SetupAttachment(GetCapsuleComponent());
	VoiceAudio->bAutoActivate = false;

	AIControllerClass = AGTANPCController::StaticClass();
	AutoPossessAI = EAutoPossessAI::PlacedInWorldOrSpawned;

	Weapons.Add(FGTAWeaponSlot());
}

bool AGTACharacter::IsPlayerCharacter() const
{
	return PedRole == EGTAPedRole::Player;
}

void AGTACharacter::BeginPlay()
{
	Super::BeginPlay();
	SpawnTime = GetWorld()->GetTimeSeconds();
	ApplyAppearance();
	UpdateWeaponVisual();
	FallStartZ = GetActorLocation().Z;
}

// ------------------------------------------------------------------------------------------------ appearance

FTransform AGTACharacter::RefBoneCS(FName Bone) const
{
	const USkeletalMesh* SK = GetMesh()->GetSkeletalMeshAsset();
	if (!SK) return FTransform::Identity;
	const FReferenceSkeleton& Ref = SK->GetRefSkeleton();
	int32 Idx = Ref.FindBoneIndex(Bone);
	FTransform T = FTransform::Identity;
	while (Idx != INDEX_NONE)
	{
		T = T * Ref.GetRefBonePose()[Idx];
		Idx = Ref.GetParentIndex(Idx);
	}
	return T;
}

void AGTACharacter::AttachToBoneRest(UStaticMeshComponent* C, FName Bone)
{
	if (!C) return;
	C->AttachToComponent(GetMesh(), FAttachmentTransformRules::KeepRelativeTransform, Bone);
	C->SetRelativeTransform(RefBoneCS(Bone).Inverse());
}

void AGTACharacter::ApplyAppearance()
{
	static const TCHAR* Bodies[] = { TEXT("SK_Human_M"), TEXT("SK_Human_M_Jacket"), TEXT("SK_Human_F"), TEXT("SK_Human_F_Skirt") };
	const int32 B = FMath::Clamp(Appearance.Body, 0, 3);
	USkeletalMesh* SK = FGTAAssets::SkelMesh(FString(TEXT("/Game/GTA/Generated/Characters/Centimetres/")) + Bodies[B]);
	USkeletalMeshComponent* M = GetMesh();
	if (SK && M->GetSkeletalMeshAsset() != SK)
	{
		M->SetSkeletalMesh(SK);
		M->SetAnimInstanceClass(UGTAAnimInstance::StaticClass());
	}
	M->SetRelativeScale3D(FVector(Appearance.Scale));

	auto Tint = [M](FName Slot, const FLinearColor& Color)
	{
		const int32 Idx = M->GetMaterialIndex(Slot);
		if (Idx == INDEX_NONE) return;
		UMaterialInstanceDynamic* MID = Cast<UMaterialInstanceDynamic>(M->GetMaterial(Idx));
		if (!MID) MID = M->CreateDynamicMaterialInstance(Idx);
		if (MID) MID->SetVectorParameterValue(TEXT("Color"), Color);
	};
	Tint(TEXT("C_Skin"), Appearance.Skin);
	Tint(TEXT("C_Lips"), Appearance.Skin * 0.7f + FLinearColor(0.08f, 0.0f, 0.0f));
	Tint(TEXT("C_Shirt"), Appearance.Shirt);
	Tint(TEXT("C_Pants"), Appearance.Pants);
	Tint(TEXT("C_Shoes"), Appearance.Shoes);
	Tint(TEXT("C_Jacket"), Appearance.Jacket);
	Tint(TEXT("C_Detail"), Appearance.Hair * 0.8f);

	auto SetAcc = [this](UStaticMeshComponent* C, const TCHAR* MeshName, FName Bone, const FLinearColor* Color)
	{
		if (!C) return;
		UStaticMesh* SM = MeshName ? FGTAAssets::GenMesh(TEXT("Characters/Acc"), MeshName) : nullptr;
		C->SetStaticMesh(SM);
		C->SetVisibility(SM != nullptr);
		if (SM)
		{
			AttachToBoneRest(C, Bone);
			if (Color)
			{
				UMaterialInstanceDynamic* MID = C->CreateDynamicMaterialInstance(0);
				if (MID) MID->SetVectorParameterValue(TEXT("Color"), *Color);
			}
		}
	};
	static const TCHAR* Hair[] = { nullptr, TEXT("SM_Hair_Short"), TEXT("SM_Hair_Long"), TEXT("SM_Hair_Ponytail"), TEXT("SM_Hair_Mohawk"), TEXT("SM_Hair_Bun") };
	static const TCHAR* Hats[] = { nullptr, TEXT("SM_Hat_Cap"), TEXT("SM_Hat_Beanie"), TEXT("SM_Hat_Police"), TEXT("SM_Hat_Helmet") };
	static const TCHAR* Glasses[] = { nullptr, TEXT("SM_Glasses_Sun"), TEXT("SM_Glasses_Round") };
	const bool bHat = Appearance.Hat > 0;
	int32 HairStyle = FMath::Clamp(Appearance.HairStyle, 0, 5);
	if (bHat && (HairStyle == 4 || HairStyle == 5)) HairStyle = 1;
	SetAcc(HairMesh, Hair[HairStyle], TEXT("head"), &Appearance.Hair);
	FLinearColor HatColor = Appearance.Hat == 3 ? FLinearColor(0.02f, 0.03f, 0.08f) : (Appearance.Hat == 4 ? FLinearColor(0.03f, 0.035f, 0.04f) : Appearance.Jacket);
	SetAcc(HatMesh, Hats[FMath::Clamp(Appearance.Hat, 0, 4)], TEXT("head"), &HatColor);
	SetAcc(GlassesMesh, Glasses[FMath::Clamp(Appearance.Glasses, 0, 2)], TEXT("head"), nullptr);
	SetAcc(BeardMesh, Appearance.Beard > 0 ? TEXT("SM_Beard") : nullptr, TEXT("head"), &Appearance.Hair);
	SetAcc(VestMesh, Appearance.Vest == 1 ? TEXT("SM_Vest_Police") : (Appearance.Vest == 2 ? TEXT("SM_Vest_Tactical") : nullptr), TEXT("spine_03"), nullptr);
	const TCHAR* Back = bScuba ? TEXT("SM_Scuba_Tank") : (bHasParachute && IsPlayerCharacter() ? TEXT("SM_Parachute_Pack") : nullptr);
	SetAcc(BackMesh, Back, TEXT("spine_03"), nullptr);
	UpdateWeaponVisual();
}

void AGTACharacter::RandomizeAppearance(int32 Seed, EGTAPedRole ForRole)
{
	FRandomStream R(Seed);
	PedRole = ForRole;
	FGTAAppearance A;
	const bool bFemale = R.FRand() < 0.45f;
	A.Body = bFemale ? (R.FRand() < 0.45f ? 3 : 2) : (R.FRand() < 0.4f ? 1 : 0);
	static const FLinearColor Skins[] = { FLinearColor(0.80f, 0.58f, 0.44f), FLinearColor(0.62f, 0.40f, 0.28f), FLinearColor(0.42f, 0.25f, 0.15f), FLinearColor(0.24f, 0.13f, 0.07f), FLinearColor(0.70f, 0.50f, 0.34f) };
	static const FLinearColor Hairs[] = { FLinearColor(0.02f, 0.015f, 0.01f), FLinearColor(0.10f, 0.05f, 0.02f), FLinearColor(0.55f, 0.38f, 0.15f), FLinearColor(0.35f, 0.08f, 0.03f), FLinearColor(0.5f, 0.5f, 0.52f), FLinearColor(0.6f, 0.05f, 0.4f) };
	A.Skin = Skins[R.RandRange(0, 4)];
	A.Hair = Hairs[R.RandRange(0, 5)];
	A.Shirt = FGTAData::ClothColor(R.RandRange(0, 15));
	A.Pants = FGTAData::ClothColor(R.RandRange(0, 15)) * 0.6f;
	A.Shoes = FGTAData::ClothColor(R.RandRange(0, 15));
	A.Jacket = FGTAData::ClothColor(R.RandRange(0, 15));
	A.HairStyle = bFemale ? R.RandRange(2, 5) : R.RandRange(0, 4);
	if (!bFemale && A.HairStyle == 2) A.HairStyle = 1;
	A.Beard = (!bFemale && R.FRand() < 0.3f) ? 1 : 0;
	A.Hat = R.FRand() < 0.2f ? R.RandRange(1, 2) : 0;
	A.Glasses = R.FRand() < 0.25f ? R.RandRange(1, 2) : 0;
	A.Scale = bFemale ? R.FRandRange(0.92f, 0.98f) : R.FRandRange(0.96f, 1.05f);
	if (ForRole == EGTAPedRole::Police)
	{
		A.Body = bFemale ? 2 : 0;
		A.Shirt = FLinearColor(0.03f, 0.06f, 0.18f);
		A.Pants = FLinearColor(0.02f, 0.025f, 0.05f);
		A.Shoes = FLinearColor(0.02f, 0.02f, 0.02f);
		A.Hat = 3; A.Vest = 1; A.Glasses = R.FRand() < 0.3f ? 1 : 0;
	}
	else if (ForRole == EGTAPedRole::Swat)
	{
		A.Body = 1;
		A.Jacket = FLinearColor(0.03f, 0.035f, 0.04f);
		A.Pants = FLinearColor(0.03f, 0.035f, 0.04f);
		A.Shoes = FLinearColor(0.02f, 0.02f, 0.02f);
		A.Hat = 4; A.Vest = 2; A.Glasses = 1; A.Beard = 0;
	}
	else if (ForRole == EGTAPedRole::Gang)
	{
		A.Body = 1;
		A.Jacket = FLinearColor(0.45f, 0.02f, 0.25f);
		A.Hat = R.FRand() < 0.5f ? 2 : 0;
	}
	else if (ForRole == EGTAPedRole::Shopkeeper)
	{
		A.Shirt = FLinearColor(0.02f, 0.35f, 0.38f);
	}
	else if (ForRole == EGTAPedRole::Medic)
	{
		A.Body = bFemale ? 2 : 0;
		A.Shirt = FLinearColor(0.85f, 0.85f, 0.85f);
		A.Pants = FLinearColor(0.1f, 0.25f, 0.45f);
		A.Hat = 0;
	}
	else if (ForRole == EGTAPedRole::Firefighter)
	{
		A.Body = 1;
		A.Jacket = FLinearColor(0.35f, 0.25f, 0.02f);
		A.Pants = FLinearColor(0.3f, 0.22f, 0.02f);
		A.Hat = 4;
	}
	Appearance = A;
	Cash = ForRole == EGTAPedRole::Civilian ? R.RandRange(5, 120) : R.RandRange(20, 60);
}

// ------------------------------------------------------------------------------------------------ weapons

int32 AGTACharacter::EffectiveClip(const FGTAWeaponSlot& S) const
{
	const FGTAWeaponDef& D = FGTAData::Weapon(S.Id);
	return S.HasMod(EGTAWeaponMod::ExtMag) ? FMath::RoundToInt(D.Clip * 1.6f) : D.Clip;
}

FGTAWeaponSlot* AGTACharacter::FindSlot(EGTAWeapon Id)
{
	for (FGTAWeaponSlot& S : Weapons) if (S.Id == Id) return &S;
	return nullptr;
}

bool AGTACharacter::HasWeapon(EGTAWeapon Id) const
{
	for (const FGTAWeaponSlot& S : Weapons) if (S.Id == Id) return true;
	return false;
}

void AGTACharacter::GiveWeapon(EGTAWeapon Id, int32 Ammo, bool bEquip)
{
	const FGTAWeaponDef& D = FGTAData::Weapon(Id);
	FGTAWeaponSlot* S = FindSlot(Id);
	if (!S)
	{
		FGTAWeaponSlot N;
		N.Id = Id;
		Weapons.Add(N);
		Weapons.Sort([](const FGTAWeaponSlot& A, const FGTAWeaponSlot& B) { return (uint8)A.Id < (uint8)B.Id; });
		S = FindSlot(Id);
	}
	if (D.Clip > 0)
	{
		S->Reserve = FMath::Min(D.MaxAmmo, S->Reserve + Ammo);
		const int32 Need = EffectiveClip(*S) - S->InClip;
		const int32 Take = FMath::Min(Need, S->Reserve);
		S->InClip += Take;
		S->Reserve -= Take;
	}
	if (bEquip) EquipWeapon(Id);
}

void AGTACharacter::RefillAllAmmo()
{
	for (FGTAWeaponSlot& S : Weapons)
	{
		const FGTAWeaponDef& D = FGTAData::Weapon(S.Id);
		if (D.Clip > 0)
		{
			S.InClip = EffectiveClip(S);
			S.Reserve = D.MaxAmmo;
		}
	}
}

void AGTACharacter::EquipWeapon(EGTAWeapon Id)
{
	for (int32 i = 0; i < Weapons.Num(); ++i)
	{
		if (Weapons[i].Id == Id)
		{
			if (CurrentSlot != i)
			{
				CurrentSlot = i;
				bReloading = false;
				GTA::Play3D(this, TEXT("S_Equip"), GetActorLocation(), 0.6f);
			}
			break;
		}
	}
	UpdateWeaponVisual();
}

void AGTACharacter::CycleWeapon(int32 Dir)
{
	if (Weapons.Num() == 0) return;
	CurrentSlot = (CurrentSlot + Dir + Weapons.Num()) % Weapons.Num();
	bReloading = false;
	UpdateWeaponVisual();
	GTA::Play3D(this, TEXT("S_Equip"), GetActorLocation(), 0.6f);
}

bool AGTACharacter::IsTwoHanded() const
{
	const FGTAWeaponDef& D = CurrentDef();
	return !D.bOneHanded && D.Cat != EGTAWeaponCat::Melee;
}

void AGTACharacter::UpdateWeaponVisual()
{
	if (!WeaponMesh) return;
	const FGTAWeaponDef& D = CurrentDef();
	UStaticMesh* SM = D.Mesh.IsEmpty() ? nullptr : FGTAAssets::GenMesh(TEXT("Weapons"), D.Mesh);
	const bool bShow = SM != nullptr && !(IsInVehicle() && !bAiming);
	WeaponMesh->SetStaticMesh(SM);
	WeaponMesh->SetVisibility(bShow, false);

	if (GetMesh()->GetSkeletalMeshAsset())
	{
		const FTransform Hand = RefBoneCS(TEXT("hand_r"));
		FVector Dir = Hand.GetUnitAxis(EAxis::Y);
		if (Dir.Z > 0.f) Dir = -Dir;
		const FVector Grip = Hand.GetLocation() + Dir * 7.5f + FVector(1.0f, -1.0f, 0.f);
		FVector Fwd = FVector::ForwardVector - Dir * FVector::DotProduct(FVector::ForwardVector, Dir);
		Fwd.Normalize();
		const FTransform WeaponCS(FRotationMatrix::MakeFromXZ(Dir, Fwd).Rotator(), Grip);
		WeaponMesh->SetRelativeTransform(WeaponCS.GetRelativeTransform(Hand));
	}

	const FGTAWeaponSlot* S = Weapons.IsValidIndex(CurrentSlot) ? &Weapons[CurrentSlot] : nullptr;
	auto SetMod = [&](UStaticMeshComponent* C, EGTAWeaponMod Mod, const TCHAR* MeshName, const FVector& Offset)
	{
		const bool bOn = bShow && S && S->HasMod(Mod);
		UStaticMesh* MM = bOn ? FGTAAssets::GenMesh(TEXT("Weapons"), MeshName) : nullptr;
		C->SetStaticMesh(MM);
		C->SetVisibility(bOn && MM != nullptr);
		C->SetRelativeLocation(Offset);
	};
	SetMod(ModSuppressor, EGTAWeaponMod::Suppressor, TEXT("SM_Mod_Suppressor"), FVector(D.MuzzleX * 100.f, 0.f, 0.f));
	SetMod(ModScope, EGTAWeaponMod::Scope, TEXT("SM_Mod_Scope"), FVector(D.MuzzleX * 25.f, 0.f, D.RailZ * 100.f));
	SetMod(ModLight, EGTAWeaponMod::Flashlight, TEXT("SM_Mod_Light"), FVector(D.MuzzleX * 55.f, 0.f, -4.f));
	const bool bLight = bShow && S && S->HasMod(EGTAWeaponMod::Flashlight) && bAiming;
	Flashlight->SetVisibility(bLight);
	Flashlight->SetRelativeLocation(FVector(D.MuzzleX * 70.f, 0.f, -4.f));
	if (S && WeaponMesh->GetStaticMesh() && S->Tint > 0)
	{
		static const FLinearColor Tints[] = { FLinearColor::Black, FLinearColor(0.6f, 0.45f, 0.1f), FLinearColor(0.12f, 0.13f, 0.07f), FLinearColor(0.7f, 0.1f, 0.4f), FLinearColor(0.05f, 0.5f, 0.55f) };
		UMaterialInstanceDynamic* MID = WeaponMesh->CreateDynamicMaterialInstance(0);
		if (MID) MID->SetVectorParameterValue(TEXT("Color"), Tints[FMath::Clamp((int32)S->Tint, 0, 4)]);
	}
}

FVector AGTACharacter::GetAimOrigin() const
{
	return GetActorLocation() + FVector(0.f, 0.f, 60.f);
}

FVector AGTACharacter::GetAimTarget() const
{
	if (bUseAimPoint) return AimPoint;
	return GetAimOrigin() + GetActorForwardVector() * 3000.f;
}

FVector AGTACharacter::GetMuzzleLocation() const
{
	if (WeaponMesh && WeaponMesh->GetStaticMesh())
	{
		const FGTAWeaponDef& D = CurrentDef();
		return WeaponMesh->GetComponentTransform().TransformPosition(FVector(D.MuzzleX * 100.f, 0.f, 3.f));
	}
	return GetAimOrigin() + GetActorForwardVector() * 40.f;
}

void AGTACharacter::SetTriggerHeld(bool bHeld)
{
	bTriggerHeld = bHeld;
	if (!bHeld) ConsecutiveShots = 0.f;
}

void AGTACharacter::Reload()
{
	FGTAWeaponSlot* S = CurrentSlotPtr();
	if (!S || bReloading || bDead) return;
	const FGTAWeaponDef& D = FGTAData::Weapon(S->Id);
	if (D.Clip <= 0 || S->Reserve <= 0 || S->InClip >= EffectiveClip(*S)) return;
	bReloading = true;
	const float SkillMult = 1.f - 0.25f * GTA::Skill(this, EGTASkill::Shooting) * (IsPlayerCharacter() ? 1.f : 0.f);
	ReloadEnd = GetWorld()->GetTimeSeconds() + D.ReloadTime * SkillMult;
	PlayAction(EGTAClip::Reload, true, 1.f / FMath::Max(0.3f, D.ReloadTime * SkillMult / 1.2f));
	GTA::Play3D(this, TEXT("S_Reload"), GetActorLocation(), 0.8f);
}

void AGTACharacter::FinishReload()
{
	bReloading = false;
	FGTAWeaponSlot* S = CurrentSlotPtr();
	if (!S) return;
	const int32 Need = EffectiveClip(*S) - S->InClip;
	const int32 Take = FMath::Min(Need, S->Reserve);
	S->InClip += Take;
	S->Reserve -= Take;
}

void AGTACharacter::TickWeapon(float Dt)
{
	const float Now = GetWorld()->GetTimeSeconds();
	if (bReloading && Now >= ReloadEnd) FinishReload();
	RecoilKick = FMath::FInterpTo(RecoilKick, 0.f, Dt, 8.f);
	MeleeCooldown -= Dt;
	if (!bTriggerHeld || bDead || bRagdoll || bReloading) return;
	const FGTAWeaponDef& D = CurrentDef();
	if (D.Cat == EGTAWeaponCat::Melee)
	{
		if (Now >= NextFireTime)
		{
			Melee(false);
			bTriggerHeld = false;
		}
		return;
	}
	if (Now < NextFireTime) return;
	FGTAWeaponSlot* S = CurrentSlotPtr();
	if (!S) return;
	if (S->InClip <= 0)
	{
		if (S->Reserve > 0) Reload();
		else GTA::Play3D(this, TEXT("S_DryFire"), GetActorLocation(), 0.6f);
		NextFireTime = Now + 0.35f;
		bTriggerHeld = false;
		return;
	}
	NextFireTime = Now + D.FireInterval;
	if (D.bProjectile) FireProjectile(D);
	else FireShot();
	if (!D.bAuto) bTriggerHeld = false;
}

void AGTACharacter::FireShot()
{
	FGTAWeaponSlot* S = CurrentSlotPtr();
	const FGTAWeaponDef& D = CurrentDef();
	S->InClip--;
	const bool bSuppressed = S->HasMod(EGTAWeaponMod::Suppressor);
	const FVector Muzzle = GetMuzzleLocation();
	const FVector Target = GetAimTarget();
	const FVector Dir = (Target - Muzzle).GetSafeNormal();
	float Spread = D.SpreadDeg * AccuracyMult * (bAiming ? 0.55f : 1.5f) * (1.f + FMath::Min(ConsecutiveShots, 10.f) * 0.07f);
	if (S->HasMod(EGTAWeaponMod::Grip)) Spread *= 0.72f;
	if (GetVelocity().Size2D() > 250.f) Spread *= 1.5f;
	if (IsPlayerCharacter()) Spread *= 1.f - 0.3f * GTA::Skill(this, EGTASkill::Shooting);
	ConsecutiveShots += 1.f;

	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAShot), true, this);
	if (Vehicle) Q.AddIgnoredActor(Vehicle);
	FVector LastEnd = Muzzle + Dir * D.RangeM * 100.f;
	for (int32 P = 0; P < D.Pellets; ++P)
	{
		const FVector ShotDir = FMath::VRandCone(Dir, FMath::DegreesToRadians(Spread) * 0.5f);
		const FVector End = Muzzle + ShotDir * D.RangeM * 100.f;
		FHitResult Hit;
		if (GetWorld()->LineTraceSingleByChannel(Hit, Muzzle, End, GTA_ECC_WEAPON, Q))
		{
			AActor* HitActor = Hit.GetActor();
			float Dmg = D.Damage * DamageMult;
			const float DistM = Hit.Distance / 100.f;
			if (DistM > D.RangeM * 0.5f) Dmg *= FMath::GetMappedRangeValueClamped(FVector2D(D.RangeM * 0.5f, D.RangeM), FVector2D(1.f, 0.5f), DistM);
			if (Hit.BoneName == FName("head") || Hit.BoneName == FName("neck_01")) Dmg *= (D.Cat == EGTAWeaponCat::Sniper ? 4.f : 2.6f);
			if (bSuppressed) Dmg *= 0.92f;
			int32 FXKind = 0;
			if (Cast<AGTACharacter>(HitActor)) FXKind = 2;
			else if (Cast<AGTAVehicle>(HitActor)) FXKind = 1;
			else if (Hit.Component.IsValid() && Hit.Component->Mobility == EComponentMobility::Movable) FXKind = 1;
			if (HitActor)
			{
				UGameplayStatics::ApplyPointDamage(HitActor, Dmg, ShotDir, Hit, GetController(), this, UGTADamage_Bullet::StaticClass());
			}
			if (Hit.Component.IsValid() && Hit.Component->IsSimulatingPhysics())
			{
				Hit.Component->AddImpulseAtLocation(ShotDir * Dmg * 120.f, Hit.ImpactPoint, Hit.BoneName);
			}
			GTA::SpawnImpactFX(this, Hit.ImpactPoint, Hit.ImpactNormal, FXKind);
			LastEnd = Hit.ImpactPoint;
		}
		else
		{
			LastEnd = End;
		}
		if (P == 0 || P == D.Pellets - 1) GTA::SpawnTracer(this, Muzzle, LastEnd);
	}
	GTA::SpawnMuzzleFX(this, Muzzle, Dir, bSuppressed);
	const FString Snd = bSuppressed ? TEXT("S_Gun_Suppressed") : (D.Cat == EGTAWeaponCat::Shotgun ? TEXT("S_Gun_Shotgun") : (D.Cat == EGTAWeaponCat::Rifle || D.Cat == EGTAWeaponCat::Sniper ? TEXT("S_Gun_Rifle") : TEXT("S_Gun_Pistol")));
	GTA::Play3D(this, Snd, Muzzle, bSuppressed ? 0.5f : 1.f, FMath::FRandRange(0.94f, 1.06f));
	GTA::MakeNoise(this, Muzzle, bSuppressed ? 1800.f : 9000.f * D.Noise, this, true);
	if (IsPlayerCharacter())
	{
		GTA::ReportCrime(this, this, EGTACrime::Gunfire, Muzzle, nullptr);
		GTA::AddSkill(this, EGTASkill::Shooting, 0.0015f);
	}
	RecoilKick += D.Recoil * (S->HasMod(EGTAWeaponMod::Grip) ? 0.6f : 1.f);
	PlayAction(EGTAClip::Hit, true, 3.f);
}

void AGTACharacter::FireProjectile(const FGTAWeaponDef& D)
{
	FGTAWeaponSlot* S = CurrentSlotPtr();
	S->InClip--;
	const FVector Target = GetAimTarget();
	FVector Start = GetMuzzleLocation();
	if (D.Id == EGTAWeapon::Grenade)
	{
		Start = GetActorLocation() + GetActorForwardVector() * 40.f + FVector(0, 0, 70.f);
		PlayAction(EGTAClip::Throw, true, 1.2f);
	}
	FVector Dir = (Target - Start).GetSafeNormal();
	FActorSpawnParameters P;
	P.Owner = this;
	P.Instigator = this;
	P.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	AGTAProjectile* Proj = GetWorld()->SpawnActor<AGTAProjectile>(AGTAProjectile::StaticClass(), Start, Dir.Rotation(), P);
	if (Proj) Proj->Init(D.Id, Dir, this);
	if (D.Id != EGTAWeapon::Grenade)
	{
		GTA::SpawnMuzzleFX(this, Start, Dir, false);
		GTA::Play3D(this, TEXT("S_Launcher"), Start, 1.f);
	}
	GTA::MakeNoise(this, Start, 6000.f, this, true);
	if (IsPlayerCharacter()) GTA::ReportCrime(this, this, EGTACrime::Gunfire, Start, nullptr);
	if (S->InClip <= 0 && S->Reserve <= 0 && D.Id == EGTAWeapon::Grenade)
	{
		// thrown the last grenade: switch back to fists
		Weapons.RemoveAt(CurrentSlot);
		CurrentSlot = 0;
		UpdateWeaponVisual();
	}
}

void AGTACharacter::Melee(bool bHeavy)
{
	if (bDead || bRagdoll || MeleeCooldown > 0.f || IsInVehicle()) return;
	const FGTAWeaponDef& D = CurrentDef();
	const EGTAWeapon W = CurrentWeapon();
	EGTAClip Clip = bHeavy ? EGTAClip::Kick : (FMath::RandBool() ? EGTAClip::Punch : EGTAClip::Punch2);
	if (W == EGTAWeapon::Bat) Clip = EGTAClip::Swing;
	else if (W == EGTAWeapon::Knife) Clip = EGTAClip::Stab;
	else if (D.Cat != EGTAWeaponCat::Melee) Clip = EGTAClip::Punch; // pistol whip
	PlayAction(Clip, !bHeavy, bHeavy ? 1.0f : 1.25f);
	MeleeCooldown = bHeavy ? 0.9f : FMath::Max(0.4f, D.Cat == EGTAWeaponCat::Melee ? D.FireInterval : 0.6f);
	NextFireTime = GetWorld()->GetTimeSeconds() + MeleeCooldown;
	bPendingHeavy = bHeavy;
	GetWorldTimerManager().SetTimer(MeleeTimer, FTimerDelegate::CreateWeakLambda(this, [this]() { ApplyMeleeHit(bPendingHeavy); }), bHeavy ? 0.32f : 0.2f, false);
	GTA::Play3D(this, TEXT("S_Swish"), GetActorLocation(), 0.5f, FMath::FRandRange(0.9f, 1.15f));
}

void AGTACharacter::ApplyMeleeHit(bool bHeavy)
{
	if (bDead || bRagdoll) return;
	const FGTAWeaponDef& D = CurrentDef();
	const FVector Start = GetActorLocation() + FVector(0, 0, 30.f);
	const FVector End = Start + GetActorForwardVector() * (D.Cat == EGTAWeaponCat::Melee ? D.RangeM * 100.f : 120.f);
	TArray<FHitResult> Hits;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAMelee), false, this);
	GetWorld()->SweepMultiByChannel(Hits, Start, End, FQuat::Identity, ECC_Pawn, FCollisionShape::MakeSphere(42.f), Q);
	TSet<AActor*> Done;
	for (const FHitResult& H : Hits)
	{
		AActor* A = H.GetActor();
		if (!A || A == this || Done.Contains(A)) continue;
		Done.Add(A);
		float Dmg = (D.Cat == EGTAWeaponCat::Melee ? D.Damage : 15.f) * (bHeavy ? 1.8f : 1.f);
		if (IsPlayerCharacter()) Dmg *= 1.f + 0.6f * GTA::Skill(this, EGTASkill::Strength);
		if (AGTACharacter* C = Cast<AGTACharacter>(A))
		{
			if (C->bDead) continue;
			const FVector ToMe = (GetActorLocation() - C->GetActorLocation()).GetSafeNormal2D();
			const bool bBehind = FVector::DotProduct(C->GetActorForwardVector(), ToMe) < -0.35f;
			AGTANPCController* AIC = Cast<AGTANPCController>(C->GetController());
			const bool bUnaware = AIC ? !AIC->IsAlerted() : false;
			if (bStealth && bBehind && bUnaware)
			{
				PlayAction(EGTAClip::Takedown, false);
				Dmg = 1000.f;
				if (IsPlayerCharacter()) GTA::AddSkill(this, EGTASkill::Stealth, 0.02f);
			}
			UGameplayStatics::ApplyPointDamage(C, Dmg, GetActorForwardVector(), H, GetController(), this, UGTADamage_Melee::StaticClass());
			if (!C->bDead && (bHeavy || CurrentWeapon() == EGTAWeapon::Bat))
			{
				C->Knockdown(GetActorForwardVector() * 450.f + FVector(0, 0, 150.f), 2.2f);
			}
			else if (!C->bDead)
			{
				C->PlayAction(EGTAClip::Hit, true, 1.f);
			}
			GTA::Play3D(this, TEXT("S_Punch"), H.ImpactPoint, 0.9f, FMath::FRandRange(0.85f, 1.1f));
			GTA::SpawnImpactFX(this, H.ImpactPoint, -GetActorForwardVector(), CurrentWeapon() == EGTAWeapon::Knife ? 2 : 4);
			if (IsPlayerCharacter()) GTA::AddSkill(this, EGTASkill::Strength, 0.004f);
		}
		else
		{
			UGameplayStatics::ApplyPointDamage(A, Dmg * 0.5f, GetActorForwardVector(), H, GetController(), this, UGTADamage_Melee::StaticClass());
			GTA::Play3D(this, TEXT("S_ImpactMetal"), H.ImpactPoint, 0.6f);
		}
	}
	GTA::MakeNoise(this, GetActorLocation(), 800.f, this, Done.Num() > 0);
}

// ------------------------------------------------------------------------------------------------ stance

void AGTACharacter::SetAiming(bool b)
{
	if (bAiming == b) return;
	bAiming = b;
	GetCharacterMovement()->bOrientRotationToMovement = !b;
	bUseControllerRotationYaw = b && !IsInVehicle();
	UpdateWeaponVisual();
}

void AGTACharacter::SetStealth(bool b)
{
	bStealth = b;
	if (b) Crouch();
	else UnCrouch();
}

void AGTACharacter::SetHandsUp(bool b)
{
	bForcePose = b;
	ForcedPose = EGTAPoseMode::HandsUp;
	if (b) { SetAiming(false); bTriggerHeld = false; GetCharacterMovement()->StopMovementImmediately(); }
}

void AGTACharacter::SetCower(bool b)
{
	bForcePose = b;
	ForcedPose = EGTAPoseMode::Cower;
}

float AGTACharacter::GetNoiseRadius() const
{
	const float Speed = GetVelocity().Size2D();
	float R = Speed < 10.f ? 0.f : (Speed < 200.f ? 350.f : (Speed < 500.f ? 900.f : 1500.f));
	if (bIsCrouched || bStealth) R *= 0.35f;
	if (IsPlayerCharacter()) R *= 1.f - 0.4f * GTA::Skill(this, EGTASkill::Stealth);
	return R;
}

// ------------------------------------------------------------------------------------------------ water

bool AGTACharacter::IsSwimming() const
{
	return GetCharacterMovement() && GetCharacterMovement()->IsSwimming();
}

bool AGTACharacter::IsUnderwater() const
{
	if (!IsSwimming()) return false;
	return GetMesh()->GetSocketLocation(TEXT("head")).Z < GTA::SeaLevel() - 8.f;
}

void AGTACharacter::TickWater(float Dt)
{
	if (bDead) return;
	const float Cap = BreathCapacity * (IsPlayerCharacter() ? (1.f + 1.5f * GTA::Skill(this, EGTASkill::Lung)) : 1.f);
	if (IsUnderwater() && !bScuba)
	{
		Breath = FMath::Max(0.f, Breath - Dt / Cap);
		if (IsPlayerCharacter()) GTA::AddSkill(this, EGTASkill::Lung, Dt * 0.0008f);
		if (Breath <= 0.f)
		{
			DrownTick += Dt;
			if (DrownTick > 1.f)
			{
				DrownTick = 0.f;
				UGameplayStatics::ApplyDamage(this, 12.f, nullptr, nullptr, UGTADamage_Drown::StaticClass());
			}
		}
	}
	else
	{
		Breath = FMath::Min(1.f, Breath + Dt * 0.35f);
		DrownTick = 0.f;
	}
	if (IsSwimming() && IsPlayerCharacter() && GetVelocity().Size() > 100.f) GTA::AddSkill(this, EGTASkill::Stamina, Dt * 0.0006f);
}

// ------------------------------------------------------------------------------------------------ damage / death

float AGTACharacter::TakeDamage(float Damage, FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser)
{
	if (bDead || bInvulnerable || Damage <= 0.f) return 0.f;
	const UClass* DT = DamageEvent.DamageTypeClass ? DamageEvent.DamageTypeClass.Get() : nullptr;
	const bool bBullet = DT && DT->IsChildOf(UGTADamage_Bullet::StaticClass());
	const bool bExplosion = DT && DT->IsChildOf(UGTADamage_Explosion::StaticClass());
	float Dmg = Damage;
	if (IsPlayerCharacter()) Dmg *= 1.f - 0.25f * GTA::Skill(this, EGTASkill::Strength);
	if (Armor > 0.f && (bBullet || bExplosion || (DT && DT->IsChildOf(UGTADamage_Melee::StaticClass()))))
	{
		const float Absorb = FMath::Min(Armor, Dmg * 0.75f);
		Armor -= Absorb;
		Dmg -= Absorb;
	}
	Health -= Dmg;
	LastDamageTime = GetWorld()->GetTimeSeconds();
	APawn* InstPawn = EventInstigator ? EventInstigator->GetPawn().Get() : Cast<APawn>(DamageCauser);
	if (!InstPawn && DamageCauser) InstPawn = DamageCauser->GetInstigator();
	LastAttacker = InstPawn ? (AActor*)InstPawn : DamageCauser;

	FName Bone = NAME_None;
	FVector ImpulseDir = FVector::ZeroVector;
	if (DamageEvent.IsOfType(FPointDamageEvent::ClassID))
	{
		const FPointDamageEvent* P = static_cast<const FPointDamageEvent*>(&DamageEvent);
		Bone = P->HitInfo.BoneName;
		ImpulseDir = P->ShotDirection;
	}
	else if (DamageEvent.IsOfType(FRadialDamageEvent::ClassID))
	{
		const FRadialDamageEvent* R = static_cast<const FRadialDamageEvent*>(&DamageEvent);
		ImpulseDir = (GetActorLocation() - R->Origin).GetSafeNormal() + FVector(0, 0, 0.6f);
	}

	AGTACharacter* Attacker = Cast<AGTACharacter>(InstPawn);
	if (!Attacker)
	{
		if (AGTAVehicle* V = Cast<AGTAVehicle>(InstPawn)) Attacker = V->GetDriver();
	}
	if (Attacker && Attacker->IsPlayerCharacter() && Attacker != this)
	{
		GTA::ReportCrime(this, Attacker, IsPolice() ? EGTACrime::AttackCop : EGTACrime::Assault, GetActorLocation(), this);
	}
	if (AGTANPCController* AIC = Cast<AGTANPCController>(GetController()))
	{
		AIC->OnDamaged(Attacker ? (AActor*)Attacker : DamageCauser, Dmg);
	}
	if (IsPlayerCharacter()) GTA::CameraShake(this, GetActorLocation(), FMath::Clamp(Dmg / 40.f, 0.1f, 1.f), 300.f);

	if (Health <= 0.f)
	{
		const float Strength = bExplosion ? 900.f : (bBullet ? 250.f : 350.f);
		Die(EventInstigator, ImpulseDir * Strength, Bone);
	}
	else if (bExplosion && Dmg > 25.f)
	{
		Knockdown(ImpulseDir * 700.f, 2.5f);
	}
	else if (!bRagdoll)
	{
		PlayAction(EGTAClip::Hit, true, 1.4f);
	}
	return Dmg;
}

void AGTACharacter::Die(AController* Killer, const FVector& Impulse, FName Bone)
{
	if (bDead) return;
	bDead = true;
	Health = 0.f;
	bTriggerHeld = false;
	SetAiming(false);
	if (Vehicle) { Vehicle->RemoveOccupant(this); }

	APawn* KillerPawn = Killer ? Killer->GetPawn() : nullptr;
	AGTACharacter* KillerChar = Cast<AGTACharacter>(KillerPawn);
	if (!KillerChar)
	{
		if (AGTAVehicle* V = Cast<AGTAVehicle>(KillerPawn)) KillerChar = V->GetDriver();
		if (!KillerChar && LastAttacker.IsValid()) KillerChar = Cast<AGTACharacter>(LastAttacker.Get());
	}
	if (KillerChar && KillerChar->IsPlayerCharacter() && KillerChar != this)
	{
		GTA::ReportCrime(this, KillerChar, IsPolice() ? EGTACrime::KillCop : EGTACrime::Murder, GetActorLocation(), this);
	}
	GTA::MakeNoise(this, GetActorLocation(), 2500.f, this, true);
	GTA::Play3D(this, TEXT("S_Grunt"), GetActorLocation(), 0.8f, FMath::FRandRange(0.8f, 1.1f));

	if (!IsPlayerCharacter())
	{
		// drop loot: cash + current firearm
		if (Cash > 0) AGTAPickup::SpawnCash(GetWorld(), GetActorLocation() + FVector(30, 0, -60), Cash);
		const FGTAWeaponDef& D = CurrentDef();
		if (D.Cat != EGTAWeaponCat::Melee && D.Clip > 0) AGTAPickup::SpawnWeapon(GetWorld(), GetActorLocation() + FVector(-30, 20, -60), D.Id, D.Clip * 2);
		WeaponMesh->SetVisibility(false);
		GTA::OnPedKilled(this, this);
	}
	StartRagdoll(Impulse, Bone);
	if (AGTANPCController* AIC = Cast<AGTANPCController>(GetController())) AIC->OnPawnDied();
	GTA::OnCharacterDied(this, this);
}

void AGTACharacter::Revive()
{
	bDead = false;
	Health = MaxHealth;
	Breath = 1.f;
	if (bRagdoll) EndKnockdown();
}

void AGTACharacter::StartRagdoll(const FVector& Impulse, FName Bone)
{
	USkeletalMeshComponent* M = GetMesh();
	if (!M->GetSkeletalMeshAsset() || !M->GetPhysicsAsset()) return;
	bRagdoll = true;
	SetHandsUp(false);
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	GetCharacterMovement()->StopMovementImmediately();
	GetCharacterMovement()->DisableMovement();
	M->SetCollisionProfileName(TEXT("Ragdoll"));
	M->SetCollisionResponseToChannel(GTA_ECC_WEAPON, ECR_Block);
	M->SetCollisionResponseToChannel(ECC_Camera, ECR_Ignore);
	M->SetAllBodiesSimulatePhysics(true);
	M->SetSimulatePhysics(true);
	M->WakeAllRigidBodies();
	M->bBlendPhysics = true;
	const FVector Vel = GetVelocity();
	M->SetAllPhysicsLinearVelocity(Vel);
	if (!Impulse.IsNearlyZero()) M->AddImpulse(Impulse, Bone != NAME_None ? Bone : FName("spine_02"), true);
	GetGTAAnim() ? (void)0 : (void)0;
}

void AGTACharacter::Knockdown(const FVector& Impulse, float Duration)
{
	if (bDead || IsInVehicle()) return;
	StartRagdoll(Impulse, TEXT("pelvis"));
	KnockdownEnd = GetWorld()->GetTimeSeconds() + Duration;
}

void AGTACharacter::EndKnockdown()
{
	KnockdownEnd = 0.f;
	USkeletalMeshComponent* M = GetMesh();
	FVector Pelvis = M->GetSocketLocation(TEXT("pelvis"));
	// Keep recovery local if a collision/constraint explosion launched the detached ragdoll.
	if (Pelvis.ContainsNaN() || FVector::DistSquared(Pelvis, GetActorLocation()) > FMath::Square(5000.f))
		Pelvis = GetActorLocation();
	M->SetSimulatePhysics(false);
	M->SetAllBodiesSimulatePhysics(false);
	M->bBlendPhysics = false;
	M->AttachToComponent(GetCapsuleComponent(), FAttachmentTransformRules::KeepWorldTransform);
	M->SetRelativeLocationAndRotation(FVector(0.f, 0.f, -92.f), FRotator::ZeroRotator);
	M->SetCollisionProfileName(TEXT("NoCollision"));
	M->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	M->SetCollisionObjectType(ECC_Pawn);
	M->SetCollisionResponseToAllChannels(ECR_Ignore);
	M->SetCollisionResponseToChannel(GTA_ECC_WEAPON, ECR_Block);
	FHitResult Ground;
	FVector Loc = Pelvis + FVector(0, 0, 40.f);
	if (GetWorld()->LineTraceSingleByChannel(Ground, Pelvis + FVector(0, 0, 100.f), Pelvis - FVector(0, 0, 300.f), ECC_Visibility, FCollisionQueryParams(SCENE_QUERY_STAT(GTAGetUp), false, this)))
	{
		Loc = Ground.ImpactPoint + FVector(0, 0, 94.f);
	}
	SetActorLocation(Loc, false, nullptr, ETeleportType::TeleportPhysics);
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	GetCharacterMovement()->SetMovementMode(MOVE_Walking);
	bRagdoll = false;
	PlayAction(EGTAClip::GetUp, false, 1.2f);
}

void AGTACharacter::Landed(const FHitResult& Hit)
{
	Super::Landed(Hit);
	const float FallM = (FallStartZ - GetActorLocation().Z) / 100.f;
	bWasFalling = false;
	if (FallM > 7.f && !bDead)
	{
		const float Dmg = FMath::Square(FallM - 7.f) * 2.2f;
		UGameplayStatics::ApplyDamage(this, Dmg, nullptr, nullptr, UGTADamage_Fall::StaticClass());
		if (!bDead && FallM > 10.f) Knockdown(GetVelocity() * 0.2f, 1.5f);
		GTA::Play3D(this, TEXT("S_Thud"), GetActorLocation(), 0.9f);
	}
}

void AGTACharacter::FellOutOfWorld(const UDamageType& DmgType)
{
	if (IsPlayerCharacter())
	{
		SetActorLocation(FVector(0, 0, 500.f));
		return;
	}
	Super::FellOutOfWorld(DmgType);
}

// ------------------------------------------------------------------------------------------------ vehicle seats

void AGTACharacter::SitInVehicle(AGTAVehicle* V, int32 Seat)
{
	if (bRagdoll && !bDead) EndKnockdown();
	Vehicle = V;
	SeatIndex = Seat;
	SetAiming(false);
	bTriggerHeld = false;
	GetCharacterMovement()->StopMovementImmediately();
	GetCharacterMovement()->DisableMovement();
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	AttachToComponent(V->BodyMesh ? (USceneComponent*)V->BodyMesh : V->GetRootComponent(), FAttachmentTransformRules::KeepWorldTransform);
	SetActorRelativeTransform(V->GetSeatTransform(Seat));
	if (Seat > 0 || V->GetDef().Kind == EGTAVehicleKind::Car || V->IsAircraft()) GetMesh()->SetVisibility(true);
	UpdateWeaponVisual();
}

void AGTACharacter::LeaveVehicleTo(const FVector& Location, float Yaw)
{
	DetachFromActor(FDetachmentTransformRules::KeepWorldTransform);
	Vehicle = nullptr;
	SeatIndex = -1;
	SetActorLocationAndRotation(Location, FRotator(0.f, Yaw, 0.f), false, nullptr, ETeleportType::TeleportPhysics);
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	GetCharacterMovement()->SetMovementMode(MOVE_Walking);
	UpdateWeaponVisual();
}

// ------------------------------------------------------------------------------------------------ animation / tick

UGTAAnimInstance* AGTACharacter::GetGTAAnim() const
{
	return Cast<UGTAAnimInstance>(GetMesh()->GetAnimInstance());
}

void AGTACharacter::PlayAction(EGTAClip Clip, bool bUpper, float Rate)
{
	if (UGTAAnimInstance* A = GetGTAAnim()) A->PlayAction(Clip, bUpper, Rate);
}

void AGTACharacter::SetSimTier(int32 Tier)
{
	if (SimTier == Tier) return;
	SimTier = Tier;
	const float Interval = Tier == 0 ? 0.f : (Tier == 1 ? 0.1f : 0.35f);
	SetActorTickInterval(Interval);
	GetCharacterMovement()->SetComponentTickInterval(Tier == 2 ? 0.1f : 0.f);
	GetMesh()->SetComponentTickInterval(Interval);
}

void AGTACharacter::TickAnimState(float Dt)
{
	UGTAAnimInstance* A = GetGTAAnim();
	if (!A) return;
	FGTAAnimState& S = A->State;
	const UCharacterMovementComponent* CM = GetCharacterMovement();
	S.Speed = GetVelocity().Size2D();
	S.VerticalSpeed = GetVelocity().Z;
	S.bCrouch = bIsCrouched;
	S.bAiming = bAiming;
	const FGTAWeaponDef& D = CurrentDef();
	S.bHoldingWeapon = D.Cat != EGTAWeaponCat::Melee && D.Cat != EGTAWeaponCat::Throwable;
	S.bTwoHanded = IsTwoHanded();
	S.AimPitch = AimPitch;
	S.AnimScale = Appearance.Scale;
	if (bRagdoll) S.Mode = EGTAPoseMode::Ragdoll;
	else if (bForcePose) S.Mode = ForcedPose;
	else if (Vehicle)
	{
		const EGTAVehicleKind K = Vehicle->GetDef().Kind;
		if (SeatIndex > 0) S.Mode = EGTAPoseMode::SeatPassenger;
		else S.Mode = (K == EGTAVehicleKind::Motorcycle || K == EGTAVehicleKind::Bicycle) ? EGTAPoseMode::SeatBike : EGTAPoseMode::SeatCar;
	}
	else if (CM->IsSwimming()) S.Mode = EGTAPoseMode::Swim;
	else if (bInCover) S.Mode = EGTAPoseMode::Cover;
	else if (CM->IsFalling()) S.Mode = EGTAPoseMode::Air;
	else S.Mode = EGTAPoseMode::Ground;
}

void AGTACharacter::Tick(float Dt)
{
	Super::Tick(Dt);
	if (bRagdoll && !bDead && KnockdownEnd > 0.f && GetWorld()->GetTimeSeconds() > KnockdownEnd)
	{
		KnockdownEnd = 0.f;
		EndKnockdown();
	}
	if (!bDead)
	{
		TickWeapon(Dt);
		TickWater(Dt);
		const bool bFalling = GetCharacterMovement()->IsFalling();
		if (bFalling && !bWasFalling) FallStartZ = GetActorLocation().Z;
		if (bFalling) FallStartZ = FMath::Max(FallStartZ, GetActorLocation().Z);
		bWasFalling = bFalling;
		if (!bFalling) FallStartZ = GetActorLocation().Z;
		const float Base = IsPolice() ? 470.f : 420.f;
		float Speed = bSprinting ? Base * 1.62f : (bAiming ? 230.f : Base);
		if (bStealth) Speed = 150.f;
		if (bForcePose) Speed = ForcedPose == EGTAPoseMode::HandsUp ? 0.f : 60.f;
		if (IsPlayerCharacter() && bSprinting) Speed *= 1.f + 0.1f * GTA::Skill(this, EGTASkill::Stamina);
		if (!bSprinting && !bForcePose) Speed *= MoveSpeedScale;
		GetCharacterMovement()->MaxWalkSpeed = Speed;
	}
	TickAnimState(Dt);
	if (Vehicle && !bRagdoll)
	{
		// Seated clips may include a pelvis offset. Anchor the actual animated pelvis to the
		// physical seat instead of assuming every pose has the same root-to-pelvis translation.
		const FVector PelvisLocal = GetActorTransform().InverseTransformPosition(GetMesh()->GetBoneLocation(TEXT("pelvis")));
		const FVector TargetPelvis = Vehicle->GetSeatTransform(SeatIndex).GetLocation() + FVector(0,0,6.f);
		SetActorRelativeLocation(TargetPelvis - PelvisLocal);
	}
}

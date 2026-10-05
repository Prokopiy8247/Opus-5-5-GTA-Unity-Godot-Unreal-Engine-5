#include "World/GTAPickup.h"
#include "Core/GTAGame.h"
#include "Player/GTAPlayerCharacter.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/PointLightComponent.h"
#include "Engine/StaticMesh.h"

AGTAPickup::AGTAPickup()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickInterval = 0.f;
	Trigger = CreateDefaultSubobject<USphereComponent>(TEXT("Trigger"));
	RootComponent = Trigger;
	Trigger->InitSphereRadius(70.f);
	Trigger->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
	Trigger->SetGenerateOverlapEvents(true);
	Mesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
	Mesh->SetupAttachment(Trigger);
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Mesh->SetCastShadow(true);
	Glow = CreateDefaultSubobject<UPointLightComponent>(TEXT("Glow"));
	Glow->SetupAttachment(Trigger);
	Glow->SetIntensity(900.f);
	Glow->SetAttenuationRadius(220.f);
	Glow->SetCastShadows(false);
	Glow->SetRelativeLocation(FVector(0, 0, 30.f));
}

AGTAPickup* AGTAPickup::SpawnPickup(UWorld* World, const FVector& Loc, EGTAPickupKind Kind, int32 Amount, EGTAWeapon Weapon, bool bTemporary)
{
	if (!World) return nullptr;
	FVector L = Loc;
	FHitResult H;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAPickupGround), false);
	if (World->LineTraceSingleByChannel(H, Loc + FVector(0, 0, 150.f), Loc - FVector(0, 0, 400.f), ECC_WorldStatic, Q)) L = H.ImpactPoint + FVector(0, 0, 35.f);
	FActorSpawnParameters P;
	P.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	AGTAPickup* A = World->SpawnActor<AGTAPickup>(AGTAPickup::StaticClass(), FTransform(L), P);
	if (A) A->Setup(Kind, Amount, Weapon, bTemporary);
	return A;
}

void AGTAPickup::SpawnCash(UWorld* World, const FVector& Loc, int32 Amount)
{
	if (Amount > 0) SpawnPickup(World, Loc, EGTAPickupKind::Cash, Amount);
}

void AGTAPickup::SpawnWeapon(UWorld* World, const FVector& Loc, EGTAWeapon InWeapon, int32 Ammo)
{
	SpawnPickup(World, Loc, EGTAPickupKind::Weapon, Ammo, InWeapon);
}

void AGTAPickup::Setup(EGTAPickupKind InKind, int32 InAmount, EGTAWeapon InWeapon, bool bTemporary)
{
	Kind = InKind;
	Amount = InAmount;
	Weapon = InWeapon;
	BaseZ = GetActorLocation().Z;
	if (bTemporary) SetLifeSpan(90.f);
	UStaticMesh* M = nullptr;
	FLinearColor C(0.3f, 1.f, 0.4f);
	switch (Kind)
	{
	case EGTAPickupKind::Cash: M = FGTAAssets::GenMesh(TEXT("Props"), TEXT("SM_Pickup_Cash")); C = FLinearColor(0.3f, 1.f, 0.35f); break;
	case EGTAPickupKind::Weapon: M = FGTAAssets::GenMesh(TEXT("Weapons"), FGTAData::Weapon(Weapon).Mesh); C = FLinearColor(0.4f, 0.75f, 1.f); break;
	case EGTAPickupKind::Health: M = FGTAAssets::GenMesh(TEXT("Props"), TEXT("SM_Pickup_Health")); C = FLinearColor(1.f, 0.25f, 0.25f); break;
	case EGTAPickupKind::Armor: M = FGTAAssets::GenMesh(TEXT("Props"), TEXT("SM_Pickup_Armor")); C = FLinearColor(0.35f, 0.55f, 1.f); break;
	case EGTAPickupKind::Parachute: M = FGTAAssets::GenMesh(TEXT("Characters/Acc"), TEXT("SM_Parachute_Pack")); C = FLinearColor(1.f, 0.6f, 0.2f); break;
	case EGTAPickupKind::Ammo: M = FGTAAssets::GenMesh(TEXT("Props"), TEXT("SM_Pickup_Ammo")); C = FLinearColor(1.f, 0.85f, 0.3f); break;
	case EGTAPickupKind::Scuba: M = FGTAAssets::GenMesh(TEXT("Characters/Acc"), TEXT("SM_Scuba_Tank")); C = FLinearColor(0.3f, 0.9f, 1.f); break;
	}
	if (!M) M = FGTAAssets::Cube();
	Mesh->SetStaticMesh(M);
	if (M == FGTAAssets::Cube()) Mesh->SetRelativeScale3D(FVector(0.25f));
	Glow->SetLightColor(C);
	Trigger->OnComponentBeginOverlap.AddDynamic(this, &AGTAPickup::OnOverlap);
}

void AGTAPickup::Tick(float Dt)
{
	Super::Tick(Dt);
	const float Now = GetWorld()->GetTimeSeconds();
	if (bCollected)
	{
		if (RespawnDelay > 0.f && Now >= HiddenUntil)
		{
			bCollected = false;
			SetActorHiddenInGame(false);
			Trigger->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
		}
		return;
	}
	Spin += Dt * 90.f;
	Mesh->SetRelativeRotation(FRotator(0.f, Spin, 0.f));
	Mesh->SetRelativeLocation(FVector(0, 0, 8.f * FMath::Sin(Now * 2.5f)));
}

void AGTAPickup::OnOverlap(UPrimitiveComponent* OverlappedComp, AActor* Other, UPrimitiveComponent* OtherComp, int32 BodyIndex, bool bFromSweep, const FHitResult& Sweep)
{
	AGTAPlayerCharacter* P = Cast<AGTAPlayerCharacter>(Other);
	if (!P || P->bDead || bCollected) return;
	FString Msg;
	switch (Kind)
	{
	case EGTAPickupKind::Cash: GTA::AddMoney(this, Amount); Msg = FString::Printf(TEXT("+$%d"), Amount); GTA::Play2D(this, TEXT("S_Pickup_Cash"), 0.8f); break;
	case EGTAPickupKind::Weapon:
		P->GiveWeapon(Weapon, Amount, false);
		Msg = FString::Printf(TEXT("Picked up %s"), *FGTAData::Weapon(Weapon).Name);
		GTA::Play2D(this, TEXT("S_Pickup"), 0.8f);
		break;
	case EGTAPickupKind::Health:
		if (P->Health >= P->MaxHealth) return;
		P->Heal(FMath::Max(Amount, 50));
		Msg = TEXT("Health restored");
		GTA::Play2D(this, TEXT("S_Pickup"), 0.8f);
		break;
	case EGTAPickupKind::Armor:
		if (P->Armor >= 100.f) return;
		P->Armor = FMath::Min(100.f, P->Armor + FMath::Max(Amount, 50));
		Msg = TEXT("Body armor");
		GTA::Play2D(this, TEXT("S_Pickup"), 0.8f);
		break;
	case EGTAPickupKind::Parachute:
		if (P->bHasParachute) return;
		P->SetHasParachute(true);
		Msg = TEXT("Parachute equipped");
		GTA::Play2D(this, TEXT("S_Pickup"), 0.8f);
		break;
	case EGTAPickupKind::Ammo:
		P->RefillAllAmmo();
		Msg = TEXT("Ammo refilled");
		GTA::Play2D(this, TEXT("S_Pickup"), 0.8f);
		break;
	case EGTAPickupKind::Scuba:
		P->SetScuba(!P->bScuba);
		Msg = P->bScuba ? TEXT("Scuba gear on") : TEXT("Scuba gear off");
		GTA::Play2D(this, TEXT("S_Pickup"), 0.8f);
		break;
	}
	GTA::Notify(this, Msg, 2.f);
	if (RespawnDelay > 0.f)
	{
		bCollected = true;
		HiddenUntil = GetWorld()->GetTimeSeconds() + RespawnDelay;
		SetActorHiddenInGame(true);
		Trigger->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}
	else
	{
		Destroy();
	}
}

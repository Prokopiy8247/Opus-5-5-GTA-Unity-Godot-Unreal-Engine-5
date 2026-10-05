#include "Weapons/GTAProjectile.h"
#include "Core/GTAGame.h"
#include "Player/GTACharacter.h"
#include "Vehicles/GTAVehicle.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/PointLightComponent.h"
#include "GameFramework/ProjectileMovementComponent.h"

AGTAProjectile::AGTAProjectile()
{
	PrimaryActorTick.bCanEverTick = true;
	Sphere = CreateDefaultSubobject<USphereComponent>(TEXT("Sphere"));
	RootComponent = Sphere;
	Sphere->InitSphereRadius(9.f);
	Sphere->SetCollisionProfileName(TEXT("BlockAllDynamic"));
	Sphere->SetCollisionResponseToChannel(ECC_Pawn, ECR_Block);
	Sphere->SetNotifyRigidBodyCollision(true);
	Mesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
	Mesh->SetupAttachment(Sphere);
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Move = CreateDefaultSubobject<UProjectileMovementComponent>(TEXT("Move"));
	Move->UpdatedComponent = Sphere;
	Move->bRotationFollowsVelocity = true;
	Glow = CreateDefaultSubobject<UPointLightComponent>(TEXT("Glow"));
	Glow->SetupAttachment(Sphere);
	Glow->SetIntensity(0.f);
	Glow->SetAttenuationRadius(600.f);
	Glow->LightColor = FColor(255, 150, 60);
	Glow->SetCastShadows(false);
	InitialLifeSpan = 12.f;
}

void AGTAProjectile::Init(EGTAWeapon InWeapon, const FVector& Dir, AActor* InShooter)
{
	Weapon = InWeapon;
	Shooter = InShooter;
	Sphere->IgnoreActorWhenMoving(InShooter, true);
	if (AGTACharacter* C = Cast<AGTACharacter>(InShooter))
	{
		if (C->Vehicle) Sphere->IgnoreActorWhenMoving(C->Vehicle.Get(), true);
	}
	Sphere->OnComponentHit.AddDynamic(this, &AGTAProjectile::OnHit);
	if (Weapon == EGTAWeapon::RocketLauncher)
	{
		Mesh->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Weapons"), TEXT("SM_Proj_Rocket")));
		Move->InitialSpeed = 4200.f;
		Move->MaxSpeed = 4200.f;
		Move->ProjectileGravityScale = 0.f;
		Glow->SetIntensity(30000.f);
		Fuse = 8.f;
	}
	else if (Weapon == EGTAWeapon::GrenadeLauncher)
	{
		Mesh->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Weapons"), TEXT("SM_Proj_Shell")));
		Move->InitialSpeed = 3000.f;
		Move->MaxSpeed = 3200.f;
		Move->ProjectileGravityScale = 1.f;
		Fuse = 6.f;
	}
	else
	{
		Mesh->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Weapons"), TEXT("SM_Wpn_Grenade")));
		Move->InitialSpeed = 1700.f;
		Move->MaxSpeed = 2500.f;
		Move->ProjectileGravityScale = 1.f;
		Move->bShouldBounce = true;
		Move->Bounciness = 0.35f;
		Move->Friction = 0.4f;
		Move->bRotationFollowsVelocity = false;
		Fuse = 3.0f;
	}
	Move->Velocity = (Dir + FVector(0, 0, Weapon == EGTAWeapon::Grenade ? 0.25f : 0.f)).GetSafeNormal() * Move->InitialSpeed;
}

void AGTAProjectile::Tick(float Dt)
{
	Super::Tick(Dt);
	if (bDone) return;
	Fuse -= Dt;
	TrailTimer -= Dt;
	if (Weapon == EGTAWeapon::RocketLauncher && TrailTimer <= 0.f)
	{
		TrailTimer = 0.03f;
		GTA::SpawnImpactFX(this, GetActorLocation() - GetActorForwardVector() * 30.f, -GetActorForwardVector(), 8);
	}
	if (GTA::IsOverSea(GetActorLocation()) && GetActorLocation().Z < GTA::SeaLevel())
	{
		GTA::SpawnImpactFX(this, GetActorLocation(), FVector::UpVector, 3);
		if (Weapon == EGTAWeapon::Grenade) { Destroy(); return; }
		Detonate();
		return;
	}
	if (Fuse <= 0.f) Detonate();
}

void AGTAProjectile::OnHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit)
{
	if (Weapon == EGTAWeapon::Grenade)
	{
		GTA::Play3D(this, TEXT("S_Clink"), GetActorLocation(), 0.5f);
		return;
	}
	Detonate();
}

void AGTAProjectile::Detonate()
{
	if (bDone) return;
	bDone = true;
	const FGTAWeaponDef& D = FGTAData::Weapon(Weapon);
	APawn* Inst = Cast<APawn>(Shooter.Get());
	GTA::Explode(this, GetActorLocation(), D.ExplosionRadiusM * 100.f, D.Damage, this, Inst ? Inst->GetController() : nullptr);
	AGTACharacter* C = Cast<AGTACharacter>(Shooter.Get());
	if (C && C->IsPlayerCharacter()) GTA::ReportCrime(this, C, EGTACrime::Explosion, GetActorLocation(), nullptr);
	Destroy();
}

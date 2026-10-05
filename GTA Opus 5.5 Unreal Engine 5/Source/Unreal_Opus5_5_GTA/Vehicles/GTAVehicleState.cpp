// Vehicle tick dispatch, damage model, collisions, lights, audio and camera.
#include "Vehicles/GTAVehicle.h"
#include "Core/GTAGame.h"
#include "Player/GTACharacter.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SpotLightComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/AudioComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/PlayerController.h"
#include "Camera/CameraComponent.h"
#include "Engine/DamageEvents.h"
#include "Engine/OverlapResult.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInstanceDynamic.h"

void AGTAVehicle::Tick(float Dt)
{
	Super::Tick(Dt);
	Dt = FMath::Min(Dt, 1.f / 20.f);
	if (bKinematicAI)
	{
		// scripted flight for AI aircraft: smooth pursuit of a target point with banking
		const FVector P = GetActorLocation();
		const FVector To = AIFlyTarget - P;
		const FVector Vel = To.GetClampedToMaxSize(AIFlySpeed);
		const FVector NewP = P + Vel * Dt;
		FRotator R = GetActorRotation();
		if (To.Size2D() > 300.f) R.Yaw = FMath::FixedTurn(R.Yaw, To.Rotation().Yaw, 60.f * Dt);
		R.Pitch = FMath::FInterpTo(R.Pitch, -FMath::Clamp(Vel.Size2D() / 120.f, 0.f, 14.f), Dt, 2.f);
		R.Roll = FMath::FInterpTo(R.Roll, FMath::Clamp(FMath::FindDeltaAngleDegrees(GetActorRotation().Yaw, To.Rotation().Yaw) * 0.4f, -25.f, 25.f), Dt, 2.f);
		SetActorLocationAndRotation(NewP, R);
		RotorSpeed = 1.f;
		if (RotorMesh) RotorMesh->AddLocalRotation(FRotator(0.f, 1400.f * Dt, 0.f));
		if (TailRotorMesh) TailRotorMesh->AddLocalRotation(FRotator(2200.f * Dt, 0.f, 0.f));
	}
	else
	{
		switch (Kind())
		{
		case EGTAVehicleKind::Boat: TickBoat(Dt); break;
		case EGTAVehicleKind::Helicopter: TickHeli(Dt); break;
		case EGTAVehicleKind::Plane: TickPlane(Dt); break;
		default: TickGround(Dt); break;
		}
		TickPedestrianImpacts(Dt);
	}
	TickEffects(Dt);
	TickAudio(Dt);
	TickCamera(Dt);
	// sinking cars / water death
	if (!IsBoat() && GTA::IsOverSea(GetActorLocation()) && GetActorLocation().Z < GTA::SeaLevel() - 80.f && !bDestroyed)
	{
		bEngineOn = false;
		Health = FMath::Max(0.f, Health - Dt * 80.f);
	}
	if (!GetDriver() && IsGrounded() && GetVelocity().Size() < 30.f) Body->PutRigidBodyToSleep();
}

float AGTAVehicle::TakeDamage(float Damage, FDamageEvent const& DamageEvent, AController* EventInstigator, AActor* DamageCauser)
{
	if (bDestroyed || Damage <= 0.f) return 0.f;
	float Dmg = Damage * GetArmorMult();
	const UClass* DT = DamageEvent.DamageTypeClass ? DamageEvent.DamageTypeClass.Get() : nullptr;
	if (DT && DT->IsChildOf(UGTADamage_Explosion::StaticClass())) Dmg *= 4.f;
	if (DamageEvent.IsOfType(FPointDamageEvent::ClassID))
	{
		const FPointDamageEvent* P = static_cast<const FPointDamageEvent*>(&DamageEvent);
		const FVector HitLocal = GetActorTransform().InverseTransformPosition(P->HitInfo.ImpactPoint);
		for (FGTAWheel& W : Wheels)
		{
			if (W.Mesh && !W.bPopped && !Mods.bBulletproofTires && FVector::Dist(HitLocal, W.Local) < W.Radius * 1.05f)
			{
				W.bPopped = true;
				GTA::Play3D(this, TEXT("S_TirePop"), P->HitInfo.ImpactPoint, 1.f);
			}
		}
		Dmg *= 0.6f;
	}
	Health -= Dmg;
	APawn* InstPawn = EventInstigator ? EventInstigator->GetPawn() : nullptr;
	AGTACharacter* Attacker = Cast<AGTACharacter>(InstPawn);
	if (!Attacker && InstPawn) if (AGTAVehicle* AV = Cast<AGTAVehicle>(InstPawn)) Attacker = AV->GetDriver();
	if (Attacker && Attacker->IsPlayerCharacter() && GetDef().bPolice && Attacker->Vehicle != this)
	{
		GTA::ReportCrime(this, Attacker, EGTACrime::AttackCop, GetActorLocation(), this);
	}
	for (AGTACharacter* Occ : Occupants)
	{
		if (Occ && !Occ->IsPlayerCharacter() && Attacker) Occ->LastAttacker = Attacker;
	}
	if (Health <= 0.f && !bOnFire)
	{
		bOnFire = true;
		ExplodeAt = GetWorld()->GetTimeSeconds() + FMath::FRandRange(3.5f, 6.f);
	}
	if (Health < -GetDef().Health * 0.6f) Explode(EventInstigator);
	return Dmg;
}

void AGTAVehicle::Explode(AController* Killer)
{
	if (bDestroyed) return;
	bDestroyed = true;
	bOnFire = false;
	Health = 0.f;
	bEngineOn = false;
	bSirenOn = false;
	SirenAudio->Stop();
	EngineAudio->Stop();
	RadioAudio->Stop();
	const FVector L = GetActorLocation();
	AGTACharacter* Drv = GetDriver();
	GTA::Explode(this, L, 750.f, 220.f, this, Killer);
	Body->AddImpulse(FVector(FMath::FRandRange(-200.f, 200.f), FMath::FRandRange(-200.f, 200.f), 600.f), NAME_None, true);
	Body->AddAngularImpulseInRadians(FMath::VRand() * 1.5f, NAME_None, true);
	for (UMaterialInstanceDynamic* MID : BodyMIDs)
	{
		if (MID) { MID->SetVectorParameterValue(TEXT("Color"), FLinearColor(0.025f, 0.022f, 0.02f)); MID->SetScalarParameterValue(TEXT("Metallic"), 0.f); MID->SetScalarParameterValue(TEXT("EmissiveStrength"), 0.f); }
	}
	for (AGTACharacter* Occ : Occupants)
	{
		if (!Occ) continue;
		UGameplayStatics::ApplyDamage(Occ, 500.f, Killer, this, UGTADamage_Explosion::StaticClass());
	}
	APawn* InstPawn = Killer ? Killer->GetPawn() : nullptr;
	AGTACharacter* Attacker = Cast<AGTACharacter>(InstPawn);
	if (!Attacker && InstPawn) if (AGTAVehicle* AV = Cast<AGTAVehicle>(InstPawn)) Attacker = AV->GetDriver();
	if (Attacker && Attacker->IsPlayerCharacter() && GetDef().bPolice) GTA::ReportCrime(this, Attacker, EGTACrime::DestroyCopCar, L, this);
	if (HeadL) HeadL->SetVisibility(false);
	if (HeadR) HeadR->SetVisibility(false);
	SetLifeSpan(90.f);
	(void)Drv;
}

void AGTAVehicle::OnBodyHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit)
{
	if (Cast<AGTACharacter>(OtherActor)) return;
	const float Now = GetWorld()->GetTimeSeconds();
	const float DV = NormalImpulse.Size() / FMath::Max(1.f, Body->GetMass()) / 100.f;
	if (DV < 2.5f || Now - LastCollisionTime < 0.15f) return;
	LastCollisionTime = Now;
	float Dmg = (DV - 2.5f) * 55.f * GetArmorMult();
	if (IsAircraft() && DV > 8.f) Dmg *= 4.f;
	Health -= Dmg;
	if (Health <= 0.f && !bOnFire && !bDestroyed)
	{
		bOnFire = true;
		ExplodeAt = Now + (IsAircraft() ? 0.2f : FMath::FRandRange(3.f, 6.f));
	}
	GTA::Play3D(this, DV > 9.f ? TEXT("S_CrashBig") : TEXT("S_Crash"), Hit.ImpactPoint, FMath::Clamp(DV / 10.f, 0.3f, 1.2f), FMath::FRandRange(0.9f, 1.1f));
	GTA::SpawnImpactFX(this, Hit.ImpactPoint, Hit.ImpactNormal, 1);
	AGTACharacter* Drv = GetDriver();
	if (Drv && Drv->IsPlayerCharacter())
	{
		GTA::CameraShake(this, Hit.ImpactPoint, FMath::Clamp(DV / 12.f, 0.15f, 1.f), 500.f);
		if (AGTAVehicle* OtherV = Cast<AGTAVehicle>(OtherActor))
		{
			if (DV > 6.f) GTA::ReportCrime(this, Drv, OtherV->GetDef().bPolice ? EGTACrime::AttackCop : EGTACrime::VehicleHit, Hit.ImpactPoint, OtherV);
			for (AGTACharacter* O : OtherV->Occupants) if (O) O->LastAttacker = Drv;
		}
	}
	if (DV > 14.f && !IsAircraft())
	{
		for (AGTACharacter* Occ : Occupants)
		{
			if (Occ) UGameplayStatics::ApplyDamage(Occ, (DV - 14.f) * 3.f, nullptr, this, UGTADamage_Vehicle::StaticClass());
		}
	}
	if (Drv && !Drv->IsPlayerCharacter()) Drv->LastAttacker = OtherActor;
}

void AGTAVehicle::TickPedestrianImpacts(float Dt)
{
	const FVector V = GetVelocity();
	const float Speed = V.Size();
	if (Speed < 300.f) return;
	const FGTAVehicleDef& D = GetDef();
	const FVector Dir = V / Speed;
	const FVector Center = GetActorLocation() + Dir * (D.Length * 50.f + Speed * 0.06f);
	const FVector Extent(Speed * 0.08f + 40.f, D.Width * 50.f + 20.f, 100.f);
	TArray<FOverlapResult> Hits;
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTARunOver), false, this);
	GetWorld()->OverlapMultiByObjectType(Hits, Center, Dir.Rotation().Quaternion(), FCollisionObjectQueryParams(ECC_Pawn), FCollisionShape::MakeBox(Extent), Q);
	for (const FOverlapResult& O : Hits)
	{
		AGTACharacter* C = Cast<AGTACharacter>(O.GetActor());
		if (!C || C->bDead || C->IsRagdoll() || C->Vehicle) continue;
		const float Rel = (V - C->GetVelocity()).Size() / 100.f;
		if (Rel < 3.f) continue;
		AGTACharacter* Drv = GetDriver();
		const float Dmg = (Rel - 3.f) * 7.f;
		C->Knockdown(V * 0.55f + FVector(0.f, 0.f, 250.f + Rel * 15.f), 2.5f);
		AController* Inst = Drv ? Drv->GetController() : nullptr;
		UGameplayStatics::ApplyDamage(C, Dmg, Inst, this, UGTADamage_Vehicle::StaticClass());
		GTA::Play3D(this, TEXT("S_Thud"), C->GetActorLocation(), 1.f);
		if (Drv && Drv->IsPlayerCharacter() && !C->bDead) GTA::ReportCrime(this, Drv, C->IsPolice() ? EGTACrime::AttackCop : EGTACrime::VehicleHit, C->GetActorLocation(), C);
		Health -= 4.f;
	}
}

void AGTAVehicle::TickEffects(float Dt)
{
	const float Now = GetWorld()->GetTimeSeconds();
	const FGTAVehicleDef& D = GetDef();
	const float HealthFrac = Health / FMath::Max(1.f, D.Health);
	const FVector EnginePos = GetActorTransform().TransformPosition(FVector(D.Length * 35.f, 0.f, D.Height * 60.f) + MeshOffset);
	SmokeTimer -= Dt;
	if (!bDestroyed && (HealthFrac < 0.35f || bOnFire) && SmokeTimer <= 0.f)
	{
		SmokeTimer = bOnFire ? 0.06f : 0.18f;
		GTA::SpawnImpactFX(this, EnginePos, FVector::UpVector, bOnFire ? 6 : 5);
	}
	if (bDestroyed && SmokeTimer <= 0.f && GetLifeSpan() > 60.f)
	{
		SmokeTimer = 0.25f;
		GTA::SpawnImpactFX(this, GetActorLocation(), FVector::UpVector, 5);
	}
	if (bOnFire && !bDestroyed && ExplodeAt > 0.f && Now >= ExplodeAt) Explode(nullptr);

	// lights
	const bool bNight = GTA::IsNight(this);
	const bool bHasDriver = GetDriver() != nullptr;
	const bool bHeadOn = !bDestroyed && bEngineOn && (bLightsOn || (bHasDriver && bNight));
	if (HeadL) { HeadL->SetVisibility(bHeadOn); HeadL->SetIntensity(bHighBeams ? 22000.f : 9000.f); }
	if (HeadR) { HeadR->SetVisibility(bHeadOn); HeadR->SetIntensity(bHighBeams ? 22000.f : 9000.f); }
	SetScalarOnSlot(TEXT("V_HeadLight"), TEXT("EmissiveStrength"), bHeadOn ? 25.f : 0.f);
	const float Tail = bDestroyed ? 0.f : (bHeadOn ? 3.f : 0.4f) + BrakeLightLevel * 18.f;
	SetScalarOnSlot(TEXT("V_TailLight"), TEXT("EmissiveStrength"), Tail);
	SetScalarOnSlot(TEXT("V_Reverse"), TEXT("EmissiveStrength"), (!bDestroyed && Throttle < -0.1f && ForwardSpeed() < 50.f) ? 8.f : 0.f);
	if (TailGlow) TailGlow->SetIntensity(Tail * 120.f);

	// sirens
	if (bSirenOn && !bDestroyed)
	{
		SirenPhase += Dt * 7.f;
		const float A = FMath::Sin(SirenPhase) > 0.f ? 1.f : 0.f;
		if (SirenRed) SirenRed->SetIntensity(A * 40000.f);
		if (SirenBlue) SirenBlue->SetIntensity((1.f - A) * 40000.f);
		SetScalarOnSlot(TEXT("V_SirenR"), TEXT("EmissiveStrength"), A * 60.f);
		SetScalarOnSlot(TEXT("V_SirenB"), TEXT("EmissiveStrength"), (1.f - A) * 60.f);
	}
	else
	{
		if (SirenRed) SirenRed->SetIntensity(0.f);
		if (SirenBlue) SirenBlue->SetIntensity(0.f);
		SetScalarOnSlot(TEXT("V_SirenR"), TEXT("EmissiveStrength"), 0.f);
		SetScalarOnSlot(TEXT("V_SirenB"), TEXT("EmissiveStrength"), 0.f);
	}
	if (Searchlight)
	{
		Searchlight->SetVisibility(bSearchlightOn && bNight);
		if (bSearchlightOn && !SearchlightTarget.IsZero())
		{
			const FRotator WorldRot = (SearchlightTarget - Searchlight->GetComponentLocation()).Rotation();
			Searchlight->SetWorldRotation(WorldRot);
		}
	}

	// tire smoke / skid marks
	float MaxSlip = 0.f;
	for (const FGTAWheel& W : Wheels) if (W.bContact) MaxSlip = FMath::Max(MaxSlip, W.SlipLat);
	if (MaxSlip > 4.5f && Now - LastSkidFX > 0.08f && Kind() != EGTAVehicleKind::Plane)
	{
		LastSkidFX = Now;
		for (const FGTAWheel& W : Wheels) if (W.bContact && W.SlipLat > 4.5f) GTA::SpawnImpactFX(this, W.ContactPoint, FVector::UpVector, 7);
	}
	if (SkidAudio)
	{
		const bool bSkid = MaxSlip > 4.f && !IsAircraft();
		if (bSkid && !SkidAudio->IsPlaying()) SkidAudio->Play();
		else if (!bSkid && SkidAudio->IsPlaying()) SkidAudio->Stop();
		if (bSkid) SkidAudio->SetVolumeMultiplier(FMath::Clamp((MaxSlip - 4.f) / 6.f, 0.2f, 1.f));
	}

	// boat wake, helicopter downwash
	if (IsBoat() && FMath::Abs(ForwardSpeed()) > 300.f && Now - LastSkidFX > 0.1f)
	{
		LastSkidFX = Now;
		GTA::SpawnImpactFX(this, GetActorLocation() - GetActorForwardVector() * D.Length * 45.f, FVector::UpVector, 3);
	}
	if (Kind() == EGTAVehicleKind::Helicopter && RotorSpeed > 0.5f && Now - LastSkidFX > 0.12f)
	{
		const float Alt = AltitudeAGL();
		if (Alt < 12.f)
		{
			LastSkidFX = Now;
			FVector G = GetActorLocation() - FVector(0, 0, (Alt * 100.f + BodyCenterZ));
			GTA::SpawnImpactFX(this, G + FMath::VRand() * FVector(400, 400, 0), FVector::UpVector, GTA::IsOverSea(G) ? 3 : 0);
		}
	}
}

void AGTAVehicle::TickAudio(float Dt)
{
	if (!EngineAudio || !EngineAudio->Sound) return;
	const bool bRun = bEngineOn && !bDestroyed && (GetDriver() != nullptr || RotorSpeed > 0.05f);
	if (bRun && !EngineAudio->IsPlaying()) EngineAudio->Play();
	else if (!bRun && EngineAudio->IsPlaying()) EngineAudio->Stop();
	if (!bRun) return;
	float Pitch = 0.6f + EngineRPM / 6500.f * 1.1f;
	float Vol = 0.45f + 0.55f * FMath::Abs(Throttle);
	if (Kind() == EGTAVehicleKind::Helicopter) { Pitch = 0.6f + 0.45f * RotorSpeed; Vol = 0.4f + 0.8f * RotorSpeed; }
	if (Kind() == EGTAVehicleKind::Plane) { Pitch = 0.6f + 0.7f * PlaneThrottle; Vol = 0.5f + 0.6f * PlaneThrottle; }
	if (Mods.bTurbo) Pitch *= 1.04f;
	if (Mods.Exhaust > 0) Vol *= 1.25f;
	EngineAudio->SetPitchMultiplier(Pitch);
	EngineAudio->SetVolumeMultiplier(Vol);
	if (RadioAudio && RadioStation > 0)
	{
		const bool bPlayerIn = GetDriver() && GetDriver()->IsPlayerCharacter();
		RadioAudio->SetVolumeMultiplier(bPlayerIn ? 0.55f : 0.0f);
	}
}

void AGTAVehicle::TickCamera(float Dt)
{
	APlayerController* PC = Cast<APlayerController>(GetController());
	if (!PC) return;
	const float Now = GetWorld()->GetTimeSeconds();
	if (!bFirstPerson && Now - LastLookInputTime > 1.6f && (SpeedKmh() > 6.f || IsAircraft()))
	{
		const FRotator Ctrl = PC->GetControlRotation();
		float Yaw = GetActorRotation().Yaw;
		if (ForwardSpeed() < -150.f && !IsAircraft()) Yaw += 180.f;
		const float Pitch = IsAircraft() ? GetActorRotation().Pitch * 0.6f - 8.f : -11.f;
		PC->SetControlRotation(FMath::RInterpTo(Ctrl, FRotator(Pitch, Yaw, 0.f), Dt, IsAircraft() ? 3.5f : 2.5f));
	}
	const float SpeedFov = FMath::GetMappedRangeValueClamped(FVector2D(60.f, 250.f), FVector2D(85.f, 98.f), SpeedKmh());
	Camera->SetFieldOfView(bFirstPerson ? 90.f : FMath::FInterpTo(Camera->FieldOfView, SpeedFov, Dt, 2.f));
}

void AGTAVehicle::SetFirstPerson(bool b)
{
	bFirstPerson = b;
	if (b)
	{
		const FTransform Seat = GetSeatTransform(0);
		Camera->AttachToComponent(BodyMesh, FAttachmentTransformRules::KeepRelativeTransform);
		Camera->SetRelativeLocationAndRotation(Seat.GetLocation() + FVector(10.f, 0.f, 70.f), FRotator::ZeroRotator);
		Camera->bUsePawnControlRotation = true;
	}
	else
	{
		Camera->AttachToComponent(CamBoom, FAttachmentTransformRules::KeepRelativeTransform, USpringArmComponent::SocketName);
		Camera->SetRelativeLocationAndRotation(FVector::ZeroVector, FRotator::ZeroRotator);
		Camera->bUsePawnControlRotation = false;
	}
}

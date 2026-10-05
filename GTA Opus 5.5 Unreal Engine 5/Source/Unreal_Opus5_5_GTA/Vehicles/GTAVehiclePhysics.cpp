// Vehicle physics models: raycast wheels, buoyancy, helicopter and fixed-wing flight.
#include "Vehicles/GTAVehicle.h"
#include "Core/GTAGame.h"
#include "Player/GTACharacter.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"

namespace
{
	constexpr float GCM = 980.f; // gravity cm/s^2
}

float AGTAVehicle::SpeedKmh() const { return GetVelocity().Size() * 0.036f; }
float AGTAVehicle::ForwardSpeed() const { return FVector::DotProduct(GetVelocity(), GetActorForwardVector()); }

int32 AGTAVehicle::WheelsInContact() const
{
	int32 N = 0;
	for (const FGTAWheel& W : Wheels) if (W.bContact) ++N;
	return N;
}

bool AGTAVehicle::IsGrounded() const { return WheelsInContact() > 0; }
bool AGTAVehicle::IsUpsideDown() const { return GetActorUpVector().Z < 0.25f; }

void AGTAVehicle::FlipUpright()
{
	const float Yaw = GetActorRotation().Yaw;
	SetActorLocationAndRotation(GetActorLocation() + FVector(0, 0, 120.f), FRotator(0.f, Yaw, 0.f), false, nullptr, ETeleportType::TeleportPhysics);
	Body->SetPhysicsLinearVelocity(FVector::ZeroVector);
	Body->SetPhysicsAngularVelocityInRadians(FVector::ZeroVector);
}

float AGTAVehicle::AltitudeAGL() const
{
	FHitResult H;
	const FVector S = GetActorLocation();
	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAAlt), false, this);
	if (GetWorld()->LineTraceSingleByChannel(H, S, S - FVector(0, 0, 200000.f), ECC_Visibility, Q))
	{
		float Z = H.ImpactPoint.Z;
		if (GTA::IsOverSea(S)) Z = FMath::Max(Z, GTA::SeaLevel());
		return (S.Z - Z - BodyCenterZ) / 100.f;
	}
	return (S.Z - GTA::SeaLevel()) / 100.f;
}

void AGTAVehicle::TickWheels(float Dt, float DriveForce, float BrakeForce, float GripMult)
{
	const FGTAVehicleDef& D = GetDef();
	const FTransform T = GetActorTransform();
	const FVector Up = T.GetUnitAxis(EAxis::Z);
	const FVector Fwd = T.GetUnitAxis(EAxis::X);
	const FVector Right = T.GetUnitAxis(EAxis::Y);
	const float Mass = Body->GetMass();
	const int32 NumW = FMath::Max(1, Wheels.Num());
	const bool bTwo = IsTwoWheeler();
	const bool bHeli = Kind() == EGTAVehicleKind::Helicopter;
	const float Travel = bHeli ? 22.f : (bTwo ? 16.f : 26.f);
	const float RestFrac = 0.45f;
	const float WheelLoad = Mass * 9.81f / NumW;
	const float K = WheelLoad / (RestFrac * Travel / 100.f) * D.SuspStiffness * (1.f + 0.15f * Mods.Suspension) * (bHeli ? 2.f : 1.f);
	const float C = 2.f * 0.45f * FMath::Sqrt(K * Mass / NumW);
	int32 NumDrive = 0;
	for (const FGTAWheel& W : Wheels) if (W.bDrive) ++NumDrive;
	NumDrive = FMath::Max(1, NumDrive);
	const float WheelMass = Mass / NumW;
	const float Wet = GTA::Instance(this) ? 1.f : 1.f;

	FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAWheel), false, this);
	for (AGTACharacter* Occ : Occupants) if (Occ) Q.AddIgnoredActor(Occ);
	FCollisionObjectQueryParams Obj;
	Obj.AddObjectTypesToQuery(ECC_WorldStatic);
	Obj.AddObjectTypesToQuery(ECC_WorldDynamic);
	Obj.AddObjectTypesToQuery(ECC_Vehicle);
	Obj.AddObjectTypesToQuery(ECC_PhysicsBody);

	const float SteerTarget = Steer * D.SteerDeg * FMath::Lerp(1.f, 0.32f, FMath::Clamp(FMath::Abs(ForwardSpeed()) / 3000.f, 0.f, 1.f));
	SteerSmoothed = FMath::FInterpTo(SteerSmoothed, SteerTarget, Dt, 7.f);

	for (int32 i = 0; i < Wheels.Num(); ++i)
	{
		FGTAWheel& W = Wheels[i];
		W.SteerDeg = W.bSteer ? SteerSmoothed : 0.f;
		const FVector AttachLocal = W.Local + FVector(0.f, 0.f, Travel * RestFrac);
		const FVector Start = T.TransformPosition(AttachLocal);
		const FVector End = Start - Up * (Travel + W.Radius);
		FHitResult Hit;
		float Comp = 0.f;
		FVector WheelCenter = Start - Up * Travel;
		W.bContact = GetWorld()->LineTraceSingleByObjectType(Hit, Start, End, Obj, Q);
		const bool bFront = W.Local.X > MeshOffset.X;
		if (W.bContact)
		{
			Comp = FMath::Clamp(1.f - (Hit.Distance - W.Radius) / Travel, 0.f, 1.f);
			// Damp the physical point velocity. A finite difference of contact compression spikes
			// on first contact and frame hitches, launching the car as if the spring were preloaded.
			const float CompVel = -FVector::DotProduct(Body->GetPhysicsLinearVelocityAtPoint(Start), Up) / 100.f;
			float Fs = K * Comp * Travel / 100.f + C * CompVel;
			if (Comp > 0.97f) Fs += WheelLoad * 3.f;
			Fs = FMath::Clamp(Fs, 0.f, WheelLoad * 3.f);
			Body->AddForceAtLocation(Up * Fs * 100.f, Start);

			const FQuat SteerQ(Up, FMath::DegreesToRadians(W.SteerDeg));
			FVector WF = SteerQ.RotateVector(Fwd);
			const FVector N = Hit.ImpactNormal;
			WF = (WF - N * FVector::DotProduct(WF, N)).GetSafeNormal();
			const FVector WR = FVector::CrossProduct(N, WF).GetSafeNormal();
			const FVector Vp = Body->GetPhysicsLinearVelocityAtPoint(Hit.ImpactPoint) / 100.f;
			const float VLong = FVector::DotProduct(Vp, WF);
			const float VLat = FVector::DotProduct(Vp, WR);
			float Mu = D.Grip * GripMult * Wet * (W.bPopped ? 0.45f : 1.f);
			if (bHandbrake && !bFront) Mu *= 0.38f;
			if (bHeli) Mu *= 1.5f;
			const float MaxF = Mu * Fs * 1.1f;
			float Flat = -VLat * WheelMass / FMath::Max(Dt, 0.001f) * (bTwo ? 0.7f : 0.5f);
			float Flong = W.bDrive ? DriveForce / NumDrive : 0.f;
			if (BrakeForce > 0.f || (bHandbrake && !bFront) || bHeli)
			{
				const float B = bHeli ? WheelLoad * 0.8f : ((bHandbrake && !bFront) ? WheelLoad * 0.9f : BrakeForce / NumW);
				Flong += -FMath::Sign(VLong) * FMath::Min(B, FMath::Abs(VLong) * WheelMass / FMath::Max(Dt, 0.001f));
			}
			Flong += -VLong * 18.f;
			const float Ftot = FMath::Sqrt(Flat * Flat + Flong * Flong);
			if (Ftot > MaxF && Ftot > 1.f)
			{
				const float S = MaxF / Ftot;
				Flat *= S;
				Flong *= S;
			}
			W.SlipLat = FMath::Abs(VLat);
			const FVector ForcePoint = Hit.ImpactPoint + Up * (W.Radius * 0.7f);
			Body->AddForceAtLocation((WF * Flong + WR * Flat) * 100.f, ForcePoint);
			W.ContactPoint = Hit.ImpactPoint;
			W.ContactNormal = N;
			WheelCenter = Start - Up * (Hit.Distance - W.Radius);
			W.Spin += VLong * 100.f / FMath::Max(1.f, W.Radius) * Dt;
		}
		else
		{
			W.SlipLat = 0.f;
			if (W.bDrive) W.Spin += Throttle * 30.f * Dt;
		}
		W.PrevCompression = Comp;

		if (W.Mesh)
		{
			const FVector LocalCenter = T.InverseTransformPosition(WheelCenter);
			FQuat Q2 = FQuat(FVector::UpVector, FMath::DegreesToRadians(W.SteerDeg));
			if (W.bRight) Q2 = Q2 * FQuat(FVector::UpVector, PI);
			Q2 = Q2 * FQuat(FVector::RightVector, W.bRight ? W.Spin : -W.Spin);
			W.Mesh->SetRelativeLocationAndRotation(LocalCenter, Q2);
			if (W.bPopped) W.Mesh->SetRelativeScale3D(FVector(W.Radius / 50.f) * FVector(0.92f, 1.f, 0.85f));
		}
	}
}

void AGTAVehicle::TickGround(float Dt)
{
	const FGTAVehicleDef& D = GetDef();
	const float SpeedMs = ForwardSpeed() / 100.f;
	const float TopMult = 1.f + 0.04f * Mods.Transmission + 0.03f * Mods.Engine + (Mods.bTurbo ? 0.05f : 0.f);
	const float MaxV = D.MaxSpeedKmh / 3.6f * TopMult;
	static const float GearTop[] = { 0.22f, 0.42f, 0.62f, 0.82f, 1.0f };
	static const float GearForce[] = { 1.0f, 0.8f, 0.66f, 0.55f, 0.46f };
	const float Frac = FMath::Abs(SpeedMs) / FMath::Max(1.f, MaxV);
	Gear = 1;
	while (Gear < 5 && Frac > GearTop[Gear - 1]) ++Gear;
	const float Lo = Gear > 1 ? GearTop[Gear - 2] : 0.f;
	const float InGear = FMath::Clamp((Frac - Lo) / (GearTop[Gear - 1] - Lo), 0.f, 1.f);
	const float TargetRPM = 900.f + InGear * 5600.f + (FMath::Abs(Throttle) > 0.1f && Frac < 0.02f ? 1500.f * FMath::Abs(Throttle) : 0.f);
	EngineRPM = FMath::FInterpTo(EngineRPM, TargetRPM, Dt, 6.f + 2.f * Mods.Transmission);

	const float Mass = Body->GetMass();
	float ThrottleIn = (bDestroyed || !bEngineOn) ? 0.f : Throttle;
	AGTACharacter* Drv = GetDriver();
	if (!Drv) ThrottleIn = 0.f;
	float Drive = 0.f, Brake = 0.f;
	const float EngineN = D.EngineForce * GetPowerMult() * GearForce[Gear - 1];
	if (D.Kind == EGTAVehicleKind::Bicycle && Drv && Drv->IsPlayerCharacter()) ThrottleIn *= 1.f + 0.5f * GTA::Skill(this, EGTASkill::Stamina);
	if (ThrottleIn > 0.f)
	{
		if (SpeedMs < -1.f) Brake = Mass * 9.81f * 0.9f * (1.f + 0.2f * Mods.Brakes) * ThrottleIn;
		else if (SpeedMs < MaxV) Drive = EngineN * ThrottleIn;
	}
	else if (ThrottleIn < 0.f)
	{
		if (SpeedMs > 1.f) Brake = Mass * 9.81f * 0.9f * (1.f + 0.2f * Mods.Brakes) * -ThrottleIn;
		else if (SpeedMs > -MaxV * 0.3f) Drive = EngineN * 0.5f * ThrottleIn;
	}
	else if (!Drv || FMath::Abs(SpeedMs) < 0.5f)
	{
		Brake = Mass * 2.f; // parked / coasting to stop
	}
	BrakeLightLevel = FMath::FInterpTo(BrakeLightLevel, Brake > Mass * 3.f ? 1.f : 0.f, Dt, 15.f);

	float Grip = 1.f + 0.04f * Mods.Suspension + (Mods.Spoiler > 0 ? 0.06f : 0.f);
	if (Drv && Drv->IsPlayerCharacter()) Grip *= 1.f + 0.08f * GTA::Skill(this, EGTASkill::Driving);
	if (GTA::Instance(this)) Grip *= 1.f; // weather grip applied by environment through Wetness below
	extern float GTAWetGripFactor;
	Grip *= GTAWetGripFactor;
	TickWheels(Dt, Drive, Brake, Grip);

	// aerodynamic drag + downforce
	const FVector V = GetVelocity() / 100.f;
	const float DragK = (D.EngineForce * 0.46f) / FMath::Square(FMath::Max(10.f, D.MaxSpeedKmh / 3.6f));
	Body->AddForce(-V * V.Size() * DragK * 0.7f * 100.f);
	const float Down = V.SizeSquared() * Mass * 0.0009f * (Mods.Spoiler > 0 ? 1.8f : 1.f);
	if (IsGrounded()) Body->AddForce(-GetActorUpVector() * Down * 100.f);

	// damaged steering pull
	if (Health < D.Health * 0.35f && IsGrounded() && FMath::Abs(SpeedMs) > 3.f)
	{
		Body->AddTorqueInRadians(GetActorUpVector() * 0.25f * FMath::Sign(SpeedMs), NAME_None, true);
	}

	const FVector AngVel = Body->GetPhysicsAngularVelocityInRadians();
	const FVector Fwd = GetActorForwardVector(), Right = GetActorRightVector(), Up = GetActorUpVector();
	if (!IsGrounded())
	{
		AirTime += Dt;
		// light air control for stunts
		Body->AddTorqueInRadians((-Right * -ThrottleIn * 1.2f + Up * Steer * 1.2f), NAME_None, true);
	}
	else
	{
		AirTime = 0.f;
	}

	if (IsTwoWheeler())
	{
		// keep the bike upright (visual lean is applied to the mesh)
		const float Roll = FMath::Asin(FMath::Clamp(-Right.Z, -1.f, 1.f));
		const float RollRate = FVector::DotProduct(AngVel, -Fwd);
		const float Torque = -Roll * 55.f - RollRate * 9.f;
		Body->AddTorqueInRadians(-Fwd * Torque, NAME_None, true);
		const float Lean = -SteerSmoothed / FMath::Max(1.f, D.SteerDeg) * FMath::Clamp(FMath::Abs(SpeedMs) / 12.f, 0.f, 1.f) * 30.f;
		BodyMesh->SetRelativeRotation(FRotator(0.f, 0.f, Lean));
		if (D.Kind == EGTAVehicleKind::Bicycle && Drv && Drv->IsPlayerCharacter() && ThrottleIn > 0.1f) GTA::AddSkill(this, EGTASkill::Stamina, Dt * 0.0005f);
	}
	if (Drv && Drv->IsPlayerCharacter() && IsGrounded() && FMath::Abs(SpeedMs) > 15.f) GTA::AddSkill(this, EGTASkill::Driving, Dt * 0.0003f);
}

void AGTAVehicle::TickBoat(float Dt)
{
	const FGTAVehicleDef& D = GetDef();
	const FTransform T = GetActorTransform();
	const float Mass = Body->GetMass();
	const float L = D.Length * 100.f, W = D.Width * 100.f;
	const FVector Pts[] = {
		FVector(L * 0.38f, -W * 0.3f, 0.f), FVector(L * 0.38f, W * 0.3f, 0.f),
		FVector(-L * 0.4f, -W * 0.38f, 0.f), FVector(-L * 0.4f, W * 0.38f, 0.f), FVector(0.f, 0.f, 0.f) };
	const float Draft = 35.f;
	const float BuoyK = Mass * 9.81f / (5.f * Draft / 100.f);
	int32 Submerged = 0;
	for (const FVector& PL : Pts)
	{
		const FVector P = T.TransformPosition(PL + FVector(0.f, 0.f, MeshOffset.Z + 10.f));
		const float WaterZ = GTA::SeaLevel() + GTA::WaveHeight(this, P);
		const float Depth = WaterZ - P.Z;
		if (Depth > 0.f && GTA::IsOverSea(P))
		{
			++Submerged;
			const float VZ = Body->GetPhysicsLinearVelocityAtPoint(P).Z / 100.f;
			const float F = FMath::Min(Depth, 150.f) / 100.f * BuoyK - VZ * Mass * 0.9f;
			Body->AddForceAtLocation(FVector(0.f, 0.f, F * 100.f), P);
		}
	}
	const float SpeedMs = ForwardSpeed() / 100.f;
	EngineRPM = FMath::FInterpTo(EngineRPM, 900.f + FMath::Abs(Throttle) * 5000.f, Dt, 3.f);
	if (Submerged > 0)
	{
		const FVector V = GetVelocity() / 100.f;
		const FVector Fwd = GetActorForwardVector(), Right = GetActorRightVector();
		const float VLat = FVector::DotProduct(V, Right);
		Body->AddForce(-Right * VLat * Mass * 1.6f * 100.f);
		Body->AddForce(-Fwd * SpeedMs * FMath::Abs(SpeedMs) * Mass * 0.012f * 100.f);
		if (GetDriver() && bEngineOn && !bDestroyed)
		{
			const FVector Stern = T.TransformPosition(FVector(-L * 0.45f, 0.f, MeshOffset.Z));
			const float Thrust = D.EngineForce * GetPowerMult() * Throttle * (Throttle < 0.f ? 0.4f : 1.f);
			Body->AddForceAtLocation(Fwd * Thrust * 100.f, Stern);
			const float Turn = Steer * FMath::Clamp(FMath::Abs(SpeedMs) / 6.f, 0.25f, 1.f) * (SpeedMs < -0.5f ? -1.f : 1.f);
			Body->AddTorqueInRadians(GetActorUpVector() * Turn * 1.3f, NAME_None, true);
			// planing: lift the bow with speed
			Body->AddTorqueInRadians(GetActorRightVector() * FMath::Clamp(SpeedMs / 25.f, 0.f, 1.f) * -0.4f, NAME_None, true);
			BodyMesh->SetRelativeRotation(FRotator(0.f, 0.f, -Steer * FMath::Clamp(SpeedMs / 15.f, 0.f, 1.f) * 10.f));
		}
	}
}

void AGTAVehicle::TickHeli(float Dt)
{
	const float Mass = Body->GetMass();
	const bool bPowered = bEngineOn && !bDestroyed && GetDriver();
	RotorSpeed = FMath::FInterpConstantTo(RotorSpeed, bPowered ? 1.f : 0.f, Dt, bPowered ? 0.35f : 0.2f);
	EngineRPM = 900.f + RotorSpeed * 5000.f;
	if (RotorMesh) RotorMesh->AddLocalRotation(FRotator(0.f, RotorSpeed * 1400.f * Dt, 0.f));
	if (TailRotorMesh) TailRotorMesh->AddLocalRotation(FRotator(RotorSpeed * 2200.f * Dt, 0.f, 0.f));
	TickWheels(Dt, 0.f, 0.f, 1.f);
	if (RotorSpeed < 0.05f) return;

	const FVector Fwd = GetActorForwardVector(), Right = GetActorRightVector(), Up = GetActorUpVector();
	const FVector AngVel = Body->GetPhysicsAngularVelocityInRadians();
	const float Tilt = FMath::Max(0.6f, Up.Z);
	float FlySkill = 0.f;
	if (GetDriver() && GetDriver()->IsPlayerCharacter()) FlySkill = GTA::Skill(this, EGTASkill::Flying);
	float Lift = Mass * 9.81f / Tilt * (1.f + LiftInput * 0.75f) * RotorSpeed;
	// altitude hold when collective is neutral
	if (FMath::Abs(LiftInput) < 0.05f) Lift -= GetVelocity().Z / 100.f * Mass * 0.8f;
	Body->AddForce(Up * Lift * 100.f);

	const float Pitch = FMath::RadiansToDegrees(FMath::Asin(FMath::Clamp(Fwd.Z, -1.f, 1.f)));
	const float Roll = FMath::RadiansToDegrees(FMath::Asin(FMath::Clamp(-Right.Z, -1.f, 1.f)));
	const float TargetPitch = -PitchInput * 26.f;
	const float TargetRoll = Steer * 26.f;
	const float PitchRate = FVector::DotProduct(AngVel, -Right);
	const float RollRate = FVector::DotProduct(AngVel, -Fwd);
	const float YawRate = FVector::DotProduct(AngVel, Up);
	const float Kp = 0.09f * (1.f + 0.2f * FlySkill), Kd = 3.2f;
	FVector Torque = -Right * ((TargetPitch - Pitch) * Kp - PitchRate * Kd)
		+ -Fwd * ((TargetRoll - Roll) * Kp - RollRate * Kd)
		+ Up * ((YawInput * 1.3f - YawRate) * 3.f);
	Torque += FMath::VRand() * 0.25f * (1.f - FlySkill) * FMath::Clamp(SpeedKmh() / 150.f, 0.1f, 1.f);
	Body->AddTorqueInRadians(Torque, NAME_None, true);
	const FVector V = GetVelocity() / 100.f;
	Body->AddForce(-V * V.Size() * Mass * 0.006f * 100.f);
	Body->AddForce(-FVector(V.X, V.Y, 0.f) * Mass * 0.12f * 100.f);
	if (GetDriver() && GetDriver()->IsPlayerCharacter() && !IsGrounded()) GTA::AddSkill(this, EGTASkill::Flying, Dt * 0.0006f);
}

void AGTAVehicle::TickPlane(float Dt)
{
	const FGTAVehicleDef& D = GetDef();
	const float Mass = Body->GetMass();
	const bool bPowered = bEngineOn && !bDestroyed && GetDriver();
	PlaneThrottle = FMath::Clamp(PlaneThrottle + Throttle * Dt * 0.7f, 0.f, 1.f);
	if (!bPowered) PlaneThrottle = FMath::Max(0.f, PlaneThrottle - Dt);
	RotorSpeed = FMath::FInterpTo(RotorSpeed, bPowered ? 0.3f + PlaneThrottle * 0.7f : 0.f, Dt, 2.f);
	EngineRPM = 900.f + RotorSpeed * 5500.f;
	if (RotorMesh) RotorMesh->AddLocalRotation(FRotator(0.f, 0.f, RotorSpeed * 2600.f * Dt));

	const FVector Fwd = GetActorForwardVector(), Right = GetActorRightVector(), Up = GetActorUpVector();
	const FVector V = GetVelocity() / 100.f;
	const float Vf = FVector::DotProduct(V, Fwd);
	const bool bJet = VehicleId == EGTAVehicle::Jet;
	const float VLift = bJet ? 62.f : 32.f;
	const float VMax = D.MaxSpeedKmh / 3.6f;

	// landing gear: steer with yaw/steer, brake when throttle is pulled back while slow
	const bool bBrake = Throttle < -0.1f && PlaneThrottle < 0.05f;
	SteerSmoothed = 0.f;
	const float SavedSteer = Steer;
	Steer = FMath::Clamp(YawInput + SavedSteer * 0.5f, -1.f, 1.f) * FMath::Clamp(1.f - Vf / VLift, 0.f, 1.f);
	TickWheels(Dt, 0.f, bBrake ? Mass * 6.f : 0.f, 1.f);
	Steer = SavedSteer;

	Body->AddForce(Fwd * D.EngineForce * PlaneThrottle * (bPowered ? 1.f : 0.f) * 100.f);
	const float LiftRatio = FMath::Clamp(FMath::Square(FMath::Max(0.f, Vf) / VLift), 0.f, 2.5f);
	const float LiftN = Mass * 9.81f * LiftRatio * (1.f + PitchInput * -0.15f);
	Body->AddForce(Up * LiftN * 100.f);
	const float DragK = D.EngineForce / FMath::Square(VMax);
	Body->AddForce(-V * V.Size() * DragK * 100.f);
	// sideslip damping and directional stability
	const float VLat = FVector::DotProduct(V, Right);
	const float VUp = FVector::DotProduct(V, Up);
	const float Air = FMath::Clamp(Vf / VLift, 0.f, 1.5f);
	Body->AddForce(-Right * VLat * Mass * 1.2f * Air * 100.f);
	Body->AddForce(-Up * VUp * Mass * 0.8f * Air * 100.f);
	StallWarn = (!IsGrounded() && Vf < VLift * 0.75f) ? 1.f : 0.f;

	const FVector AngVel = Body->GetPhysicsAngularVelocityInRadians();
	const float PitchRate = FVector::DotProduct(AngVel, -Right);
	const float RollRate = FVector::DotProduct(AngVel, -Fwd);
	const float YawRate = FVector::DotProduct(AngVel, Up);
	float Skill = (GetDriver() && GetDriver()->IsPlayerCharacter()) ? GTA::Skill(this, EGTASkill::Flying) : 0.5f;
	const float Auth = FMath::Clamp(Vf / VLift, 0.12f, 1.4f) * (1.f + 0.15f * Skill);
	const float TPitch = -PitchInput * (bJet ? 1.6f : 1.1f);
	const float TRoll = Steer * (bJet ? 3.2f : 2.1f);
	const float TYaw = YawInput * 0.45f;
	FVector Torque = -Right * (TPitch - PitchRate) * 4.f * Auth + -Fwd * (TRoll - RollRate) * 4.f * Auth + Up * (TYaw - YawRate) * 3.f * Auth;
	// weathervane toward the velocity vector when flying
	if (!IsGrounded() && V.Size() > 10.f)
	{
		const FVector VD = V.GetSafeNormal();
		Torque += FVector::CrossProduct(Fwd, VD) * 2.5f * Air;
	}
	if (StallWarn > 0.f) Torque += -Right * -0.6f;
	Body->AddTorqueInRadians(Torque, NAME_None, true);
	if (GetDriver() && GetDriver()->IsPlayerCharacter() && !IsGrounded()) GTA::AddSkill(this, EGTASkill::Flying, Dt * 0.0006f);
}

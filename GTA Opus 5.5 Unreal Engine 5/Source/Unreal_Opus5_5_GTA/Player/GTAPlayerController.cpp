#include "Player/GTAPlayerController.h"
#include "Player/GTAPlayerCharacter.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Core/GTAGameInstance.h"
#include "AI/GTANPCController.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "InputMappingContext.h"
#include "InputAction.h"
#include "InputModifiers.h"
#include "GameFramework/WorldSettings.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"

AGTAPlayerController::AGTAPlayerController()
{
	PrimaryActorTick.bCanEverTick = true;
	bShowMouseCursor = false;
}

AGTAVehicle* AGTAPlayerController::CurrentVehicle() const
{
	return PlayerChar ? PlayerChar->Vehicle.Get() : nullptr;
}

void AGTAPlayerController::BeginPlay()
{
	Super::BeginPlay();
	FInputModeGameOnly Mode;
	SetInputMode(Mode);
	if (UGTAGameInstance* GI = GTA::Instance(this))
	{
		bShowFPS = GI->bShowFPS;
		bShowCoords = GI->bShowCoords;
	}
}

void AGTAPlayerController::OnPossess(APawn* InPawn)
{
	Super::OnPossess(InPawn);
	if (AGTAPlayerCharacter* P = Cast<AGTAPlayerCharacter>(InPawn)) PlayerChar = P;
}

void AGTAPlayerController::AddCameraShake(float Strength)
{
	if (PlayerChar) PlayerChar->CameraShake = FMath::Min(1.5f, PlayerChar->CameraShake + Strength);
}

// ------------------------------------------------------------------------------------------------ input setup

UInputAction* AGTAPlayerController::MakeAction(const TCHAR* Name, bool bAxis2D, bool bAxis1D)
{
	UInputAction* A = NewObject<UInputAction>(this, FName(Name));
	A->ValueType = bAxis2D ? EInputActionValueType::Axis2D : (bAxis1D ? EInputActionValueType::Axis1D : EInputActionValueType::Boolean);
	Actions.Add(A);
	return A;
}

void AGTAPlayerController::MapKey(UInputAction* A, const FKey& K, bool bNegate, bool bSwizzle)
{
	FEnhancedActionKeyMapping& M = Mapping->MapKey(A, K);
	if (bSwizzle)
	{
		UInputModifierSwizzleAxis* S = NewObject<UInputModifierSwizzleAxis>(Mapping);
		S->Order = EInputAxisSwizzle::YXZ;
		M.Modifiers.Add(S);
	}
	if (bNegate) M.Modifiers.Add(NewObject<UInputModifierNegate>(Mapping));
}

void AGTAPlayerController::SetupInputComponent()
{
	Super::SetupInputComponent();
	Mapping = NewObject<UInputMappingContext>(this, TEXT("IMC_PortHalcyon"));
	UEnhancedInputComponent* EIC = Cast<UEnhancedInputComponent>(InputComponent);
	if (!EIC) { UE_LOG(LogGTA, Error, TEXT("EnhancedInputComponent missing - check DefaultInput.ini")); return; }

	UInputAction* Move = MakeAction(TEXT("IA_Move"), true);
	MapKey(Move, EKeys::W, false, true);
	MapKey(Move, EKeys::S, true, true);
	MapKey(Move, EKeys::D);
	MapKey(Move, EKeys::A, true);
	MapKey(Move, EKeys::Gamepad_Left2D);
	EIC->BindAction(Move, ETriggerEvent::Triggered, this, &AGTAPlayerController::OnMove);
	EIC->BindAction(Move, ETriggerEvent::Completed, this, &AGTAPlayerController::OnMoveDone);

	UInputAction* Look = MakeAction(TEXT("IA_Look"), true);
	MapKey(Look, EKeys::Mouse2D);
	EIC->BindAction(Look, ETriggerEvent::Triggered, this, &AGTAPlayerController::OnLook);

	auto Bool = [&](const TCHAR* Name, const FKey& K, void (AGTAPlayerController::*Start)(const FInputActionValue&), void (AGTAPlayerController::*End)(const FInputActionValue&) = nullptr, const FKey& K2 = EKeys::Invalid)
	{
		UInputAction* A = MakeAction(Name, false);
		const FString ActionName(Name);
		A->bTriggerWhenPaused = ActionName.StartsWith(TEXT("IA_Menu")) || ActionName == TEXT("IA_Pause") || ActionName == TEXT("IA_Admin");
		MapKey(A, K);
		if (K2.IsValid()) MapKey(A, K2);
		EIC->BindAction(A, ETriggerEvent::Started, this, Start);
		if (End) EIC->BindAction(A, ETriggerEvent::Completed, this, End);
		return A;
	};
	Bool(TEXT("IA_Jump"), EKeys::SpaceBar, &AGTAPlayerController::OnJumpStart, &AGTAPlayerController::OnJumpEnd);
	Bool(TEXT("IA_Sprint"), EKeys::LeftShift, &AGTAPlayerController::OnSprintStart, &AGTAPlayerController::OnSprintEnd);
	Bool(TEXT("IA_Crouch"), EKeys::LeftControl, &AGTAPlayerController::OnCrouch, nullptr, EKeys::C);
	Bool(TEXT("IA_Fire"), EKeys::LeftMouseButton, &AGTAPlayerController::OnFireStart, &AGTAPlayerController::OnFireEnd);
	Bool(TEXT("IA_Aim"), EKeys::RightMouseButton, &AGTAPlayerController::OnAimStart, &AGTAPlayerController::OnAimEnd);
	Bool(TEXT("IA_Reload"), EKeys::R, &AGTAPlayerController::OnReload);
	Bool(TEXT("IA_EnterExit"), EKeys::F, &AGTAPlayerController::OnEnter);
	Bool(TEXT("IA_Interact"), EKeys::E, &AGTAPlayerController::OnInteract);
	Bool(TEXT("IA_WeaponWheel"), EKeys::Tab, &AGTAPlayerController::OnWheelStart, &AGTAPlayerController::OnWheelEnd);
	Bool(TEXT("IA_NextWeapon"), EKeys::MouseScrollUp, &AGTAPlayerController::OnNextWeapon);
	Bool(TEXT("IA_PrevWeapon"), EKeys::MouseScrollDown, &AGTAPlayerController::OnPrevWeapon);
	Bool(TEXT("IA_Map"), EKeys::M, &AGTAPlayerController::OnMap);
	Bool(TEXT("IA_Pause"), EKeys::Escape, &AGTAPlayerController::OnPause, nullptr, EKeys::P);
	Bool(TEXT("IA_Admin"), EKeys::F1, &AGTAPlayerController::OnAdmin, nullptr, EKeys::F10);
	Bool(TEXT("IA_Cover"), EKeys::Q, &AGTAPlayerController::OnCover);
	Bool(TEXT("IA_Camera"), EKeys::V, &AGTAPlayerController::OnCamera);
	Bool(TEXT("IA_Horn"), EKeys::H, &AGTAPlayerController::OnHornStart, &AGTAPlayerController::OnHornEnd);
	Bool(TEXT("IA_Lights"), EKeys::L, &AGTAPlayerController::OnLights);
	Bool(TEXT("IA_Dodge"), EKeys::X, &AGTAPlayerController::OnDodge);
	Bool(TEXT("IA_Block"), EKeys::B, &AGTAPlayerController::OnBlockStart, &AGTAPlayerController::OnBlockEnd);
	Bool(TEXT("IA_Shoulder"), EKeys::MiddleMouseButton, &AGTAPlayerController::OnShoulder);
	Bool(TEXT("IA_Roof"), EKeys::T, &AGTAPlayerController::OnRoof);
	Bool(TEXT("IA_MenuUp"), EKeys::Up, &AGTAPlayerController::OnMenuUp);
	Bool(TEXT("IA_MenuDown"), EKeys::Down, &AGTAPlayerController::OnMenuDown);
	Bool(TEXT("IA_MenuLeft"), EKeys::Left, &AGTAPlayerController::OnMenuLeft);
	Bool(TEXT("IA_MenuRight"), EKeys::Right, &AGTAPlayerController::OnMenuRight);
	Bool(TEXT("IA_MenuAccept"), EKeys::Enter, &AGTAPlayerController::OnMenuAccept);
	Bool(TEXT("IA_MenuBack"), EKeys::BackSpace, &AGTAPlayerController::OnMenuBack);
	const FKey Numbers[] = { EKeys::One, EKeys::Two, EKeys::Three, EKeys::Four, EKeys::Five, EKeys::Six, EKeys::Seven, EKeys::Eight, EKeys::Nine };
	for (int32 i = 0; i < 9; ++i)
	{
		UInputAction* A = MakeAction(*FString::Printf(TEXT("IA_Slot%d"), i + 1), false);
		MapKey(A, Numbers[i]);
		EIC->BindActionInstanceLambda(A, ETriggerEvent::Started, [this, i](const FInputActionInstance&) { OnNumber(i + 1); });
	}
	if (ULocalPlayer* LP = GetLocalPlayer())
	{
		if (UEnhancedInputLocalPlayerSubsystem* Sub = LP->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>())
		{
			Sub->ClearAllMappings();
			Sub->AddMappingContext(Mapping, 0);
		}
	}
}

// ------------------------------------------------------------------------------------------------ on-foot handlers

void AGTAPlayerController::OnMove(const FInputActionValue& V)
{
	MoveAxis = V.Get<FVector2D>();
	if (IsMenuOpen() || bWheelOpen) return;
	if (PlayerChar && !PlayerChar->IsInVehicle()) PlayerChar->InputMove(MoveAxis);
}

void AGTAPlayerController::OnMoveDone(const FInputActionValue& V)
{
	MoveAxis = FVector2D::ZeroVector;
	if (PlayerChar) PlayerChar->InputMove(FVector2D::ZeroVector);
}

void AGTAPlayerController::OnLook(const FInputActionValue& V)
{
	const FVector2D L = V.Get<FVector2D>();
	if (bWheelOpen) { WheelCursor += FVector2D(L.X, -L.Y) * 6.f; WheelCursor = WheelCursor.GetClampedToMaxSize(120.f); return; }
	if (IsMenuOpen() && MenuStack.Last().bPauseGame) return;
	if (bMapOpen) return;
	if (AGTAVehicle* Veh = CurrentVehicle())
	{
		UGTAGameInstance* GI = GTA::Instance(this);
		const float S = GI ? GI->MouseSensitivity : 1.f;
		AddYawInput(L.X * S);
		AddPitchInput(-L.Y * S * ((GI && GI->bInvertY) ? -1.f : 1.f));
		if (!L.IsNearlyZero()) Veh->LastLookInputTime = GetWorld()->GetTimeSeconds();
		return;
	}
	if (PlayerChar) PlayerChar->InputLook(L);
}

void AGTAPlayerController::OnJumpStart(const FInputActionValue& V)
{
	bJumpHeld = true;
	if (IsMenuOpen() || !PlayerChar || PlayerChar->IsInVehicle()) return;
	PlayerChar->InputJump();
}

void AGTAPlayerController::OnJumpEnd(const FInputActionValue& V) { bJumpHeld = false; if (PlayerChar) PlayerChar->StopJumping(); }

void AGTAPlayerController::OnSprintStart(const FInputActionValue& V)
{
	bSprintHeld = true;
	if (PlayerChar && !PlayerChar->IsInVehicle()) PlayerChar->SetSprinting(true);
}

void AGTAPlayerController::OnSprintEnd(const FInputActionValue& V)
{
	bSprintHeld = false;
	if (PlayerChar) PlayerChar->SetSprinting(false);
}

void AGTAPlayerController::OnCrouch(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar || PlayerChar->IsInVehicle()) return;
	PlayerChar->InputCrouch();
}

void AGTAPlayerController::OnFireStart(const FInputActionValue& V)
{
	bFireHeld = true;
	if (IsMenuOpen() || bWheelOpen || bMapOpen || !PlayerChar || PlayerChar->bDead) return;
	if (AGTAVehicle* Veh = CurrentVehicle())
	{
		// drive-by: only one-handed weapons from the driver seat, any firearm from passenger seats
		const FGTAWeaponDef& D = PlayerChar->CurrentDef();
		const bool bAllowed = D.Cat != EGTAWeaponCat::Melee && D.Cat != EGTAWeaponCat::Throwable && !D.bProjectile && (PlayerChar->SeatIndex > 0 || D.bOneHanded) && !Veh->IsAircraft();
		if (!bAllowed) return;
		PlayerChar->SetAiming(true);
		PlayerChar->SetTriggerHeld(true);
		return;
	}
	const FGTAWeaponDef& D = PlayerChar->CurrentDef();
	if (D.Cat == EGTAWeaponCat::Melee) { PlayerChar->Melee(bSprintHeld); return; }
	PlayerChar->SetTriggerHeld(true);
}

void AGTAPlayerController::OnFireEnd(const FInputActionValue& V)
{
	bFireHeld = false;
	if (PlayerChar)
	{
		PlayerChar->SetTriggerHeld(false);
		if (PlayerChar->IsInVehicle() && !bAimHeld) PlayerChar->SetAiming(false);
	}
}

void AGTAPlayerController::OnAimStart(const FInputActionValue& V)
{
	bAimHeld = true;
	if (IsMenuOpen() || !PlayerChar || PlayerChar->bDead) return;
	if (PlayerChar->IsInVehicle())
	{
		const FGTAWeaponDef& D = PlayerChar->CurrentDef();
		if (D.Cat == EGTAWeaponCat::Melee || (PlayerChar->SeatIndex == 0 && !D.bOneHanded) || CurrentVehicle()->IsAircraft()) return;
	}
	PlayerChar->SetAiming(true);
}

void AGTAPlayerController::OnAimEnd(const FInputActionValue& V)
{
	bAimHeld = false;
	if (PlayerChar) PlayerChar->SetAiming(false);
}

void AGTAPlayerController::OnReload(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar) return;
	if (AGTAVehicle* Veh = CurrentVehicle()) { if (!bAimHeld) { Veh->CycleRadio(1); return; } }
	PlayerChar->Reload();
}

void AGTAPlayerController::OnEnter(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar || PlayerChar->bDead) return;
	if (PlayerChar->InputParachute()) return;
	TryEnterOrExit();
}

void AGTAPlayerController::OnInteract(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar || PlayerChar->bDead) return;
	if (AGTAVehicle* Veh = CurrentVehicle())
	{
		if (!Veh->IsAircraft() && (Veh->GetDef().bPolice || Veh->GetDef().bEmergency)) { Veh->ToggleSiren(); return; }
	}
	Interact();
}

void AGTAPlayerController::OnWheelStart(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar || PlayerChar->bDead) return;
	bWheelOpen = true;
	WheelCursor = FVector2D::ZeroVector;
	WheelHover = WheelCategoryOf(PlayerChar->CurrentWeapon());
	GetWorldSettings()->SetTimeDilation(0.25f);
	PlayerChar->SetTriggerHeld(false);
}

void AGTAPlayerController::OnWheelEnd(const FInputActionValue& V)
{
	if (!bWheelOpen) return;
	bWheelOpen = false;
	if (!(GTA::Mode(this) && GTA::Mode(this)->bRespawning)) GetWorldSettings()->SetTimeDilation(1.f);
	if (!PlayerChar || WheelHover < 0) return;
	// equip the best weapon owned in the hovered category
	for (int32 i = PlayerChar->Weapons.Num() - 1; i >= 0; --i)
	{
		if (WheelCategoryOf(PlayerChar->Weapons[i].Id) == WheelHover) { PlayerChar->EquipWeapon(PlayerChar->Weapons[i].Id); break; }
	}
}

void AGTAPlayerController::OnNextWeapon(const FInputActionValue& V)
{
	if (IsMenuOpen()) { OnMenuUp(V); return; }
	if (PlayerChar) PlayerChar->CycleWeapon(1);
}

void AGTAPlayerController::OnPrevWeapon(const FInputActionValue& V)
{
	if (IsMenuOpen()) { OnMenuDown(V); return; }
	if (PlayerChar) PlayerChar->CycleWeapon(-1);
}

void AGTAPlayerController::OnNumber(int32 N)
{
	if (!PlayerChar) return;
	if (IsMenuOpen())
	{
		FGTAMenu& M = MenuStack.Last();
		if (M.Items.IsValidIndex(N - 1)) { M.Selected = N - 1; OnMenuAccept(FInputActionValue()); }
		return;
	}
	// number keys select the N-th owned weapon category slot
	TArray<EGTAWeapon> Owned;
	for (const FGTAWeaponSlot& S : PlayerChar->Weapons) Owned.Add(S.Id);
	if (Owned.IsValidIndex(N - 1)) PlayerChar->EquipWeapon(Owned[N - 1]);
}

void AGTAPlayerController::OnMap(const FInputActionValue& V)
{
	if (IsMenuOpen()) return;
	OpenMap();
}

void AGTAPlayerController::OnPause(const FInputActionValue& V)
{
	if (bMapOpen) { bMapOpen = false; return; }
	if (IsMenuOpen()) { CloseMenu(); return; }
	OpenPauseMenu();
}

void AGTAPlayerController::OnPhone(const FInputActionValue& V) { if (!IsMenuOpen()) OpenPhone(); }

void AGTAPlayerController::OnAdmin(const FInputActionValue& V)
{
	if (IsMenuOpen()) { CloseAllMenus(); return; }
	OpenAdminMenu();
}

void AGTAPlayerController::OnCover(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar || PlayerChar->IsInVehicle()) return;
	PlayerChar->InputCover();
}

void AGTAPlayerController::OnCamera(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar) return;
	if (AGTAVehicle* Veh = CurrentVehicle()) { Veh->SetFirstPerson(!Veh->bFirstPerson); return; }
	PlayerChar->ToggleFirstPerson();
}

void AGTAPlayerController::OnHornStart(const FInputActionValue& V) { if (AGTAVehicle* Veh = CurrentVehicle()) Veh->SetHorn(true); }
void AGTAPlayerController::OnHornEnd(const FInputActionValue& V) { if (AGTAVehicle* Veh = CurrentVehicle()) Veh->SetHorn(false); }
void AGTAPlayerController::OnLights(const FInputActionValue& V) { if (AGTAVehicle* Veh = CurrentVehicle()) Veh->ToggleLights(); }
void AGTAPlayerController::OnRoof(const FInputActionValue& V) { if (AGTAVehicle* Veh = CurrentVehicle()) Veh->ToggleRoof(); }

void AGTAPlayerController::OnDodge(const FInputActionValue& V)
{
	if (IsMenuOpen() || !PlayerChar) return;
	PlayerChar->InputDodge();
}

void AGTAPlayerController::OnBlockStart(const FInputActionValue& V) { if (PlayerChar) { PlayerChar->InputBlock(true); PlayerChar->PlayAction(EGTAClip::Block, true, 1.f); } }
void AGTAPlayerController::OnBlockEnd(const FInputActionValue& V) { if (PlayerChar) PlayerChar->InputBlock(false); }
void AGTAPlayerController::OnShoulder(const FInputActionValue& V) { if (PlayerChar) PlayerChar->SwapShoulder(); }

// ------------------------------------------------------------------------------------------------ weapon wheel

const TCHAR* AGTAPlayerController::WheelCategoryName(int32 Cat)
{
	static const TCHAR* N[] = { TEXT("Unarmed"), TEXT("Melee"), TEXT("Handguns"), TEXT("SMG"), TEXT("Shotguns"), TEXT("Rifles"), TEXT("Snipers"), TEXT("Heavy / Thrown") };
	return N[FMath::Clamp(Cat, 0, 7)];
}

int32 AGTAPlayerController::WheelCategoryOf(EGTAWeapon W)
{
	if (W == EGTAWeapon::Fists) return 0;
	switch (FGTAData::Weapon(W).Cat)
	{
	case EGTAWeaponCat::Melee: return 1;
	case EGTAWeaponCat::Handgun: return 2;
	case EGTAWeaponCat::SMG: return 3;
	case EGTAWeaponCat::Shotgun: return 4;
	case EGTAWeaponCat::Rifle: return 5;
	case EGTAWeaponCat::Sniper: return 6;
	default: return 7;
	}
}

void AGTAPlayerController::TickWeaponWheel(float Dt)
{
	if (!bWheelOpen) return;
	if (WheelCursor.Size() > 35.f)
	{
		float Ang = FMath::RadiansToDegrees(FMath::Atan2(WheelCursor.X, WheelCursor.Y));   // 0 = up, clockwise
		if (Ang < 0.f) Ang += 360.f;
		WheelHover = FMath::RoundToInt(Ang / 45.f) % 8;
	}
}

// ------------------------------------------------------------------------------------------------ vehicles

void AGTAPlayerController::TryEnterOrExit()
{
	if (!PlayerChar) return;
	if (PlayerChar->IsInVehicle()) { ExitVehicle(); return; }
	if (EnterPendingVehicle.IsValid()) return;
	int32 Seat = 0;
	AGTAVehicle* V = PlayerChar->FindVehicleToEnter(Seat);
	if (!V) return;
	EnterVehicle(V, Seat);
}

void AGTAPlayerController::EnterVehicle(AGTAVehicle* V, int32 Seat)
{
	if (!V || !PlayerChar) return;
	if (V->Occupants.Num() < V->NumSeats()) V->Occupants.SetNum(V->NumSeats());
	AGTACharacter* Occ = V->Occupants.IsValidIndex(Seat) ? V->Occupants[Seat].Get() : nullptr;
	const float Now = GetWorld()->GetTimeSeconds();
	if (Occ && Occ != PlayerChar && !EnterPendingVehicle.IsValid())
	{
		// carjack: pull the occupant out, then take the seat
		const FVector Exit = V->GetExitLocation(Seat);
		V->RemoveOccupant(Occ);
		Occ->LeaveVehicleTo(Exit, V->GetActorRotation().Yaw);
		if (!Occ->bDead) Occ->Knockdown((Exit - V->GetActorLocation()).GetSafeNormal2D() * 300.f + FVector(0, 0, 100.f), 1.6f);
		if (AGTANPCController* AIC = Cast<AGTANPCController>(Occ->GetController())) AIC->OnVehicleJacked(PlayerChar);
		PlayerChar->PlayAction(EGTAClip::Punch, true, 1.2f);
		GTA::Play3D(this, TEXT("S_DoorOpen"), V->GetActorLocation(), 0.8f);
		GTA::ReportCrime(this, PlayerChar, V->GetDef().bPolice ? EGTACrime::StealCopCar : EGTACrime::CarJack, V->GetActorLocation(), Occ);
		EnterPendingVehicle = V;
		EnterPendingSeat = Seat;
		EnterPendingTime = Now + 0.55f;
		return;
	}
	if (!V->AddOccupant(PlayerChar, Seat)) return;
	EnterPendingVehicle = nullptr;
	GTA::Play3D(this, TEXT("S_DoorClose"), V->GetActorLocation(), 0.7f);
	if (Seat == 0)
	{
		if (V->bParked && !V->bPlayerOwned && !V->bWasStolen)
		{
			V->bWasStolen = true;
			if (FMath::FRand() < 0.3f)
			{
				GTA::Play3D(this, TEXT("S_CarAlarm"), V->GetActorLocation(), 0.8f);
				GTA::ReportCrime(this, PlayerChar, V->GetDef().bPolice ? EGTACrime::StealCopCar : EGTACrime::CarJack, V->GetActorLocation(), nullptr);
			}
			else if (V->GetDef().bPolice) GTA::ReportCrime(this, PlayerChar, EGTACrime::StealCopCar, V->GetActorLocation(), nullptr);
		}
		V->bParked = false;
		V->bEngineOn = true;
		V->bAIDriven = false;
	}
	LastVehicle = V;
	const FRotator Rot(-10.f, V->GetActorRotation().Yaw, 0.f);
	Possess(V);
	SetControlRotation(Rot);
	PlayerChar->SetAiming(false);
}

void AGTAPlayerController::ExitVehicle(bool bForce)
{
	AGTAVehicle* V = CurrentVehicle();
	if (!V || !PlayerChar) return;
	const float Speed = V->GetVelocity().Size();
	const bool bAirborneAircraft = V->IsAircraft() && !V->IsGrounded();
	const int32 Seat = PlayerChar->SeatIndex;
	FVector Exit = V->GetExitLocation(Seat);
	if (bAirborneAircraft) Exit = V->GetActorLocation() - V->GetActorUpVector() * 250.f + V->GetActorRightVector() * (V->GetDef().Width * 50.f + 150.f);
	if (Seat == 0) V->ClearInputs();
	V->RemoveOccupant(PlayerChar);
	PlayerChar->LeaveVehicleTo(Exit, V->GetActorRotation().Yaw);
	Possess(PlayerChar);
	SetControlRotation(FRotator(-10.f, V->GetActorRotation().Yaw, 0.f));
	if (bAirborneAircraft)
	{
		PlayerChar->GetCharacterMovement()->Velocity = V->GetVelocity() * 0.5f;
		GTA::Notify(this, PlayerChar->bHasParachute ? TEXT("Press F to open the parachute") : TEXT("No parachute!"), 3.f);
	}
	else if (Speed > 900.f && !V->IsBoat())
	{
		PlayerChar->Knockdown(V->GetVelocity() * 0.35f + FVector(0, 0, 200.f), 1.8f);
		UGameplayStatics::ApplyDamage(PlayerChar, FMath::Min(40.f, Speed / 100.f), this, V, UGTADamage_Fall::StaticClass());
	}
	if (V->IsBoat() && GTA::IsOverSea(Exit)) PlayerChar->GetCharacterMovement()->SetMovementMode(MOVE_Falling);
	GTA::Play3D(this, TEXT("S_DoorClose"), V->GetActorLocation(), 0.6f);
}

void AGTAPlayerController::TickVehicleInput(float Dt)
{
	AGTAVehicle* V = CurrentVehicle();
	if (!V || !PlayerChar || PlayerChar->SeatIndex != 0 || bScriptedInput) return;
	if (IsMenuOpen() && MenuStack.Last().bPauseGame) { V->ClearInputs(); return; }
	const bool bShift = IsInputKeyDown(EKeys::LeftShift);
	const bool bCtrl = IsInputKeyDown(EKeys::LeftControl);
	const bool bQ = IsInputKeyDown(EKeys::Q);
	const bool bE = IsInputKeyDown(EKeys::E);
	const FVector2D In = (IsMenuOpen() || bWheelOpen) ? FVector2D::ZeroVector : MoveAxis;
	switch (V->Kind())
	{
	case EGTAVehicleKind::Helicopter:
		V->PitchInput = In.Y;
		V->Steer = In.X;
		V->YawInput = (bE ? 1.f : 0.f) - (bQ ? 1.f : 0.f);
		V->LiftInput = (bShift ? 1.f : 0.f) - (bCtrl ? 1.f : 0.f);
		V->Throttle = 0.f;
		break;
	case EGTAVehicleKind::Plane:
		V->PitchInput = In.Y;
		V->Steer = In.X;
		V->YawInput = (bE ? 1.f : 0.f) - (bQ ? 1.f : 0.f);
		V->Throttle = (bShift ? 1.f : 0.f) - (bCtrl ? 1.f : 0.f);
		break;
	default:
		V->Throttle = In.Y;
		V->Steer = In.X;
		V->bHandbrake = bJumpHeld;
		V->bBoost = bShift;
		V->PitchInput = V->IsTwoWheeler() ? (bShift ? 1.f : (bCtrl ? -1.f : 0.f)) : 0.f;
		break;
	}
}

// ------------------------------------------------------------------------------------------------ tick

void AGTAPlayerController::PlayerTick(float Dt)
{
	Super::PlayerTick(Dt);
	if (!PlayerChar) PlayerChar = Cast<AGTAPlayerCharacter>(GetPawn());
	if (EnterPendingVehicle.IsValid() && GetWorld()->GetTimeSeconds() >= EnterPendingTime)
	{
		AGTAVehicle* V = EnterPendingVehicle.Get();
		EnterPendingVehicle = nullptr;
		if (PlayerChar && !PlayerChar->bDead && FVector::Dist(V->GetActorLocation(), PlayerChar->GetActorLocation()) < 900.f) EnterVehicle(V, EnterPendingSeat);
	}
	TickVehicleInput(Dt);
	TickWeaponWheel(Dt);
	TickContext(Dt);
	TickStuntJump(Dt);
	if (PlayerChar && PlayerChar->bDead && PlayerChar->IsInVehicle())
	{
		AGTAVehicle* V = PlayerChar->Vehicle;
		V->RemoveOccupant(PlayerChar);
		PlayerChar->LeaveVehicleTo(V->GetExitLocation(0), V->GetActorRotation().Yaw);
		Possess(PlayerChar);
	}
}

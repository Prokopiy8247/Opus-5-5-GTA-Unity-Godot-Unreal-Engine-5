// Player controller: Enhanced Input (built in code), on-foot / vehicle routing, carjacking, menus, weapon wheel.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "Core/GTATypes.h"
#include "GTAPlayerController.generated.h"

class UInputAction;
class UInputMappingContext;
class AGTAPlayerCharacter;
class AGTAVehicle;
struct FInputActionValue;

struct FGTAMenuItem
{
	FString Label;
	FString Value;                       // right-aligned value text
	FString Hint;                        // description shown for the selected item
	TFunction<void()> OnSelect;
	TFunction<void(int32)> OnAdjust;     // left/right
	bool bEnabled = true;
};

struct FGTAMenu
{
	FString Title;
	FString Subtitle;
	TArray<FGTAMenuItem> Items;
	int32 Selected = 0;
	TFunction<void(FGTAMenu&)> Rebuild;  // refresh labels/values after a change
	bool bPauseGame = false;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAPlayerController : public APlayerController
{
	GENERATED_BODY()
public:
	AGTAPlayerController();
	virtual void BeginPlay() override;
	virtual void SetupInputComponent() override;
	virtual void PlayerTick(float DeltaTime) override;
	virtual void OnPossess(APawn* InPawn) override;

	UPROPERTY() TObjectPtr<AGTAPlayerCharacter> PlayerChar;
	AGTAVehicle* CurrentVehicle() const;

	void AddCameraShake(float Strength);

	// ---------------------------------------------------------------- vehicles
	void TryEnterOrExit();
	void EnterVehicle(AGTAVehicle* V, int32 Seat);
	void ExitVehicle(bool bForce = false);
	AGTAVehicle* LastVehicle = nullptr;
	FVector2D MoveAxis = FVector2D::ZeroVector;

	// ---------------------------------------------------------------- menus
	TArray<FGTAMenu> MenuStack;
	bool IsMenuOpen() const { return MenuStack.Num() > 0; }
	void OpenMenu(const FGTAMenu& M);
	void CloseMenu();
	void CloseAllMenus();
	void RefreshMenu();
	void OpenAdminMenu();
	void OpenPauseMenu();
	void OpenPhone();
	void OpenShop(int32 PoiType);
	void OpenModShop();
	void OpenWeaponShop();
	void OpenClothesShop(bool bBarber);
	void OpenGarage(int32 Index);
	void OpenSafehouse(int32 Index);
	void OpenMap() { bMapOpen = !bMapOpen; }
	bool bMapOpen = false;
	FVector Waypoint = FVector::ZeroVector;
	bool bHasWaypoint = false;

	// ---------------------------------------------------------------- weapon wheel
	bool bWheelOpen = false;
	int32 WheelHover = -1;          // category index 0..7
	FVector2D WheelCursor = FVector2D::ZeroVector;
	static const TCHAR* WheelCategoryName(int32 Cat);
	static int32 WheelCategoryOf(EGTAWeapon W);

	bool bScriptedInput = false;    // test director drives the vehicle

	// ---------------------------------------------------------------- debug overlay
	bool bShowFPS = false;
	bool bShowCoords = false;

	// ---------------------------------------------------------------- interaction
	FString ContextPrompt;
	void Interact();
	float NextInteractTime = 0.f;
	int32 StuntJumpActive = -1;
	float StuntStartTime = 0.f;
	FVector StuntStart = FVector::ZeroVector;

protected:
	void BuildInput();
	UInputAction* MakeAction(const TCHAR* Name, bool bAxis2D, bool bAxis1D = false);
	void MapKey(UInputAction* A, const FKey& K, bool bNegate = false, bool bSwizzle = false);

	void OnMove(const FInputActionValue& V);
	void OnMoveDone(const FInputActionValue& V);
	void OnLook(const FInputActionValue& V);
	void OnJumpStart(const FInputActionValue& V);
	void OnJumpEnd(const FInputActionValue& V);
	void OnSprintStart(const FInputActionValue& V);
	void OnSprintEnd(const FInputActionValue& V);
	void OnCrouch(const FInputActionValue& V);
	void OnFireStart(const FInputActionValue& V);
	void OnFireEnd(const FInputActionValue& V);
	void OnAimStart(const FInputActionValue& V);
	void OnAimEnd(const FInputActionValue& V);
	void OnReload(const FInputActionValue& V);
	void OnEnter(const FInputActionValue& V);
	void OnInteract(const FInputActionValue& V);
	void OnWheelStart(const FInputActionValue& V);
	void OnWheelEnd(const FInputActionValue& V);
	void OnNextWeapon(const FInputActionValue& V);
	void OnPrevWeapon(const FInputActionValue& V);
	void OnMap(const FInputActionValue& V);
	void OnPause(const FInputActionValue& V);
	void OnPhone(const FInputActionValue& V);
	void OnAdmin(const FInputActionValue& V);
	void OnCover(const FInputActionValue& V);
	void OnCamera(const FInputActionValue& V);
	void OnHornStart(const FInputActionValue& V);
	void OnHornEnd(const FInputActionValue& V);
	void OnLights(const FInputActionValue& V);
	void OnDodge(const FInputActionValue& V);
	void OnBlockStart(const FInputActionValue& V);
	void OnBlockEnd(const FInputActionValue& V);
	void OnShoulder(const FInputActionValue& V);
	void OnRoof(const FInputActionValue& V);
	void OnMenuUp(const FInputActionValue& V);
	void OnMenuDown(const FInputActionValue& V);
	void OnMenuLeft(const FInputActionValue& V);
	void OnMenuRight(const FInputActionValue& V);
	void OnMenuAccept(const FInputActionValue& V);
	void OnMenuBack(const FInputActionValue& V);
	void OnNumber(int32 N);

	void TickVehicleInput(float Dt);
	void TickContext(float Dt);
	void TickStuntJump(float Dt);
	void TickWeaponWheel(float Dt);

	UPROPERTY() TObjectPtr<UInputMappingContext> Mapping;
	UPROPERTY() TArray<TObjectPtr<UInputAction>> Actions;
	bool bJumpHeld = false;
	bool bSprintHeld = false;
	bool bCrouchHeld = false;
	bool bFireHeld = false;
	bool bAimHeld = false;
	bool bBoostHeld = false;
	float YawLeft = 0.f, YawRight = 0.f;
	float LastShake = 0.f;
	float EnterPendingTime = 0.f;
	TWeakObjectPtr<AGTAVehicle> EnterPendingVehicle;
	int32 EnterPendingSeat = 0;
};

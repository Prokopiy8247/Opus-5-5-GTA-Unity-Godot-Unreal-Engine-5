#include "UI/GTAHUD.h"
#include "UI/GTAWidgets.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Core/GTAGameInstance.h"
#include "Player/GTAPlayerCharacter.h"
#include "Player/GTAPlayerController.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "World/GTAEnvironment.h"
#include "Blueprint/WidgetTree.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/TextBlock.h"
#include "Components/ProgressBar.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"

using namespace GTAUI;

void AGTAHUD::BeginPlay()
{
	Super::BeginPlay();
	APlayerController* PC = GetOwningPlayerController();
	if (!PC) return;
	Widget = CreateWidget<UGTAHUDWidget>(PC, UGTAHUDWidget::StaticClass());
	if (Widget) Widget->AddToViewport(0);
}

// ------------------------------------------------------------------------------------------------ layout

namespace
{
	UCanvasPanelSlot* Anchor(UCanvasPanelSlot* S, const FVector2D& A, const FVector2D& Align, const FVector2D& Pos, const FVector2D& Size, bool bAuto = false)
	{
		S->SetAnchors(FAnchors(A.X, A.Y));
		S->SetAlignment(Align);
		S->SetPosition(Pos);
		if (bAuto) S->SetAutoSize(true);
		else S->SetSize(Size);
		return S;
	}
}

void UGTAHUDWidget::NativeOnInitialized()
{
	Super::NativeOnInitialized();
	BuildTree();
}

void UGTAHUDWidget::BuildTree()
{
	if (!WidgetTree || WidgetTree->RootWidget) return;
	Root = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("Root"));
	WidgetTree->RootWidget = Root;

	auto MakeText = [this](const TCHAR* Name, int32 Size, const FLinearColor& C, bool bBold = true)
	{
		UTextBlock* T = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), Name);
		T->SetFont(Font(Size, bBold));
		T->SetColorAndOpacity(FSlateColor(C));
		T->SetShadowOffset(FVector2D(1.f, 1.f));
		T->SetShadowColorAndOpacity(FLinearColor(0, 0, 0, 0.6f));
		return T;
	};
	auto MakeBar = [this](const TCHAR* Name, const FLinearColor& C)
	{
		UProgressBar* B = WidgetTree->ConstructWidget<UProgressBar>(UProgressBar::StaticClass(), Name);
		B->SetFillColorAndOpacity(C);
		B->SetPercent(1.f);
		FProgressBarStyle St = B->GetWidgetStyle();
		St.BackgroundImage.TintColor = FSlateColor(FLinearColor(0.f, 0.f, 0.f, 0.65f));
		St.FillImage.TintColor = FSlateColor(FLinearColor::White);
		B->SetWidgetStyle(St);
		return B;
	};

	// top-right: money, wanted stars, weapon
	MoneyText = MakeText(TEXT("Money"), 26, FLinearColor(0.35f, 1.f, 0.55f));
	Anchor(Root->AddChildToCanvas(MoneyText), FVector2D(1, 0), FVector2D(1, 0), FVector2D(-36, 26), FVector2D::ZeroVector, true);
	Stars = WidgetTree->ConstructWidget<UGTAStarsWidget>(UGTAStarsWidget::StaticClass(), TEXT("Stars"));
	Anchor(Root->AddChildToCanvas(Stars), FVector2D(1, 0), FVector2D(1, 0), FVector2D(-34, 66), FVector2D(220, 40));
	WeaponText = MakeText(TEXT("Weapon"), 16, Text);
	Anchor(Root->AddChildToCanvas(WeaponText), FVector2D(1, 0), FVector2D(1, 0), FVector2D(-36, 114), FVector2D::ZeroVector, true);
	AmmoText = MakeText(TEXT("Ammo"), 22, Teal);
	Anchor(Root->AddChildToCanvas(AmmoText), FVector2D(1, 0), FVector2D(1, 0), FVector2D(-36, 138), FVector2D::ZeroVector, true);

	// bottom-left: minimap with vitals
	Minimap = WidgetTree->ConstructWidget<UGTAMapWidget>(UGTAMapWidget::StaticClass(), TEXT("Minimap"));
	Minimap->SetClipping(EWidgetClipping::ClipToBounds);
	Anchor(Root->AddChildToCanvas(Minimap), FVector2D(0, 1), FVector2D(0, 1), FVector2D(32, -52), FVector2D(300, 210));
	HealthBar = MakeBar(TEXT("Health"), FLinearColor(0.25f, 0.95f, 0.45f));
	Anchor(Root->AddChildToCanvas(HealthBar), FVector2D(0, 1), FVector2D(0, 1), FVector2D(32, -34), FVector2D(148, 12));
	ArmorBar = MakeBar(TEXT("Armor"), FLinearColor(0.3f, 0.6f, 1.f));
	Anchor(Root->AddChildToCanvas(ArmorBar), FVector2D(0, 1), FVector2D(0, 1), FVector2D(184, -34), FVector2D(148, 12));
	BreathBar = MakeBar(TEXT("Breath"), FLinearColor(0.75f, 0.95f, 1.f));
	Anchor(Root->AddChildToCanvas(BreathBar), FVector2D(0, 1), FVector2D(0, 1), FVector2D(32, -18), FVector2D(300, 8));
	DistrictText = MakeText(TEXT("District"), 15, Text);
	Anchor(Root->AddChildToCanvas(DistrictText), FVector2D(0, 1), FVector2D(0, 1), FVector2D(34, -268), FVector2D::ZeroVector, true);

	// bottom-right: vehicle panel
	VehicleBox = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("VehicleBox"));
	VehicleBox->SetBrushColor(Panel);
	VehicleBox->SetPadding(FMargin(16.f, 10.f));
	Anchor(Root->AddChildToCanvas(VehicleBox), FVector2D(1, 1), FVector2D(1, 1), FVector2D(-32, -40), FVector2D(300, 118));
	UCanvasPanel* VC = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("VehicleCanvas"));
	VehicleBox->SetContent(VC);
	SpeedText = MakeText(TEXT("Speed"), 34, Text);
	Anchor(VC->AddChildToCanvas(SpeedText), FVector2D(0, 0), FVector2D(0, 0), FVector2D(0, -2), FVector2D::ZeroVector, true);
	VehicleText = MakeText(TEXT("VehicleInfo"), 11, Teal, false);
	Anchor(VC->AddChildToCanvas(VehicleText), FVector2D(0, 0), FVector2D(0, 0), FVector2D(0, 46), FVector2D::ZeroVector, true);
	VehicleHealthBar = MakeBar(TEXT("VehicleHealth"), Amber);
	Anchor(VC->AddChildToCanvas(VehicleHealthBar), FVector2D(0, 1), FVector2D(0, 1), FVector2D(0, 0), FVector2D(268, 6));

	// notifications (top-left), debug (top-center), prompt (bottom-center), controls hint
	NotifyText = MakeText(TEXT("Notify"), 14, Text, false);
	NotifyText->SetAutoWrapText(true);
	Anchor(Root->AddChildToCanvas(NotifyText), FVector2D(0, 0), FVector2D(0, 0), FVector2D(36, 30), FVector2D(560, 200));
	DebugText = MakeText(TEXT("Debug"), 13, Amber, false);
	Anchor(Root->AddChildToCanvas(DebugText), FVector2D(0.5f, 0), FVector2D(0.5f, 0), FVector2D(0, 12), FVector2D::ZeroVector, true);
	PromptBox = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("PromptBox"));
	PromptBox->SetBrushColor(Panel);
	PromptBox->SetPadding(FMargin(16.f, 8.f));
	PromptText = MakeText(TEXT("Prompt"), 15, Text);
	PromptBox->SetContent(PromptText);
	Anchor(Root->AddChildToCanvas(PromptBox), FVector2D(0.5f, 1), FVector2D(0.5f, 1), FVector2D(0, -150), FVector2D::ZeroVector, true);
	HintText = MakeText(TEXT("Hint"), 10, FLinearColor(1, 1, 1, 0.55f), false);
	Anchor(Root->AddChildToCanvas(HintText), FVector2D(1, 1), FVector2D(1, 1), FVector2D(-32, -8), FVector2D::ZeroVector, true);

	// overlays
	Wheel = WidgetTree->ConstructWidget<UGTAWheelWidget>(UGTAWheelWidget::StaticClass(), TEXT("Wheel"));
	Anchor(Root->AddChildToCanvas(Wheel), FVector2D(0.5f, 0.5f), FVector2D(0.5f, 0.5f), FVector2D(0, 0), FVector2D(520, 520));
	Menu = WidgetTree->ConstructWidget<UGTAMenuWidget>(UGTAMenuWidget::StaticClass(), TEXT("Menu"));
	Anchor(Root->AddChildToCanvas(Menu), FVector2D(0, 0), FVector2D(0, 0), FVector2D(36, 110), FVector2D(500, 680));
	BigMap = WidgetTree->ConstructWidget<UGTAMapWidget>(UGTAMapWidget::StaticClass(), TEXT("BigMap"));
	BigMap->bFullMap = true;
	BigMap->SetClipping(EWidgetClipping::ClipToBounds);
	UCanvasPanelSlot* BS = Root->AddChildToCanvas(BigMap);
	BS->SetAnchors(FAnchors(0.f, 0.f, 1.f, 1.f));
	BS->SetOffsets(FMargin(80.f, 60.f, 80.f, 60.f));
	BigMap->SetVisibility(ESlateVisibility::Collapsed);
}

// ------------------------------------------------------------------------------------------------ per-frame state

void UGTAHUDWidget::NativeTick(const FGeometry& MyGeometry, float Dt)
{
	Super::NativeTick(MyGeometry, Dt);
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetOwningPlayer());
	AGTAGameMode* M = GTA::Mode(this);
	AGTAPlayerCharacter* P = GTA::Player(this);
	UGTAGameInstance* GI = GTA::Instance(this);
	if (!PC || !M || !P || !GI || !Root) return;
	const float Now = GetWorld()->GetTimeSeconds();
	FPSAvg = FMath::Lerp(FPSAvg, 1.f / FMath::Max(Dt, 0.0001f), 0.05f);

	// money with delta flash
	const int32 Money = GI->Profile.Money;
	if (LastMoney >= 0 && Money != LastMoney) { MoneyDelta = Money - LastMoney; MoneyFlash = 2.f; }
	LastMoney = Money;
	MoneyFlash = FMath::Max(0.f, MoneyFlash - Dt);
	FString MoneyStr = FString::Printf(TEXT("$%s"), *FText::AsNumber(Money).ToString());
	if (MoneyFlash > 0.f) MoneyStr = FString::Printf(TEXT("%s%d   %s"), MoneyDelta >= 0 ? TEXT("+") : TEXT("−"), FMath::Abs(MoneyDelta), *MoneyStr);
	MoneyText->SetText(FText::FromString(MoneyStr));

	// weapon
	const FGTAWeaponDef& D = P->CurrentDef();
	WeaponText->SetText(FText::FromString(D.Name.ToUpper()));
	const FGTAWeaponSlot* S = P->Weapons.IsValidIndex(P->CurrentSlot) ? &P->Weapons[P->CurrentSlot] : nullptr;
	if (S && D.Clip > 0) AmmoText->SetText(FText::FromString(P->IsReloading() ? TEXT("RELOADING") : FString::Printf(TEXT("%d  /  %d"), S->InClip, S->Reserve)));
	else AmmoText->SetText(FText::GetEmpty());

	// vitals
	HealthBar->SetPercent(P->Health / FMath::Max(1.f, P->MaxHealth));
	HealthBar->SetFillColorAndOpacity(P->Health < 30.f ? FLinearColor(1.f, 0.25f, 0.2f) : FLinearColor(0.25f, 0.95f, 0.45f));
	ArmorBar->SetPercent(P->Armor / 100.f);
	const bool bBreath = P->IsUnderwater() || P->Breath < 0.999f;
	BreathBar->SetVisibility(bBreath ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
	BreathBar->SetPercent(P->Breath);
	if (M->City) DistrictText->SetText(FText::FromString(M->City->SectorName(P->GetActorLocation()) + (M->Env ? TEXT("   ") + M->Env->TimeString() : FString())));

	// vehicle panel
	AGTAVehicle* V = P->Vehicle;
	VehicleBox->SetVisibility(V ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
	if (V)
	{
		const FGTAVehicleDef& VD = V->GetDef();
		SpeedText->SetText(FText::FromString(FString::Printf(TEXT("%d km/h"), FMath::RoundToInt(V->SpeedKmh()))));
		FString Info = VD.Name;
		if (V->IsAircraft())
		{
			Info += FString::Printf(TEXT("  ·  ALT %d m"), FMath::RoundToInt(V->AltitudeAGL()));
			if (V->Kind() == EGTAVehicleKind::Plane) Info += FString::Printf(TEXT("  ·  THR %d%%"), FMath::RoundToInt(V->PlaneThrottle * 100.f));
		}
		else if (!V->IsBoat()) Info += FString::Printf(TEXT("  ·  GEAR %d"), V->Gear);
		if (V->RadioStation > 0) Info += TEXT("\n♪ ") + AGTAVehicle::StationName(V->RadioStation);
		VehicleText->SetText(FText::FromString(Info));
		VehicleHealthBar->SetPercent(V->Health / FMath::Max(1.f, VD.Health));
	}

	// notifications
	FString Notes;
	for (const FGTANotification& N : M->Notes) Notes += N.Text + TEXT("\n");
	NotifyText->SetText(FText::FromString(Notes));

	// prompt
	const FString Prompt = PC->IsMenuOpen() ? FString() : PC->ContextPrompt;
	PromptBox->SetVisibility(Prompt.IsEmpty() ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
	PromptText->SetText(FText::FromString(Prompt));
	HintText->SetText(FText::FromString(TEXT("F1 test menu · Tab weapons · M map · ↑ phone · Esc pause")));

	// debug overlay
	FString Dbg;
	if (PC->bShowFPS) Dbg += FString::Printf(TEXT("FPS %.0f  (%.1f ms)   "), FPSAvg, 1000.f / FMath::Max(FPSAvg, 1.f));
	if (PC->bShowCoords)
	{
		const FVector L = P->GetActorLocation();
		Dbg += FString::Printf(TEXT("X %.1f  Y %.1f  Z %.1f m   %s"), L.X / 100.f, L.Y / 100.f, L.Z / 100.f, M->City ? *M->City->SectorName(L) : TEXT(""));
	}
	DebugText->SetText(FText::FromString(Dbg));

	// overlays
	Wheel->SetVisibility(PC->bWheelOpen ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
	Menu->SetVisibility(PC->IsMenuOpen() ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
	Minimap->SetVisibility(PC->bMapOpen ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
	if (PC->bMapOpen != bMapWasOpen)
	{
		bMapWasOpen = PC->bMapOpen;
		BigMap->SetVisibility(bMapWasOpen ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
		PC->SetShowMouseCursor(bMapWasOpen);
		if (bMapWasOpen)
		{
			FInputModeGameAndUI Mode;
			Mode.SetHideCursorDuringCapture(false);
			Mode.SetLockMouseToViewportBehavior(EMouseLockMode::LockAlways);
			PC->SetInputMode(Mode);
		}
		else PC->SetInputMode(FInputModeGameOnly());
	}
}

// ------------------------------------------------------------------------------------------------ crosshair, big messages, damage vignette

int32 UGTAHUDWidget::NativePaint(const FPaintArgs& Args, const FGeometry& G, const FSlateRect& Cull, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const
{
	Layer = Super::NativePaint(Args, G, Cull, Out, Layer, Style, bParentEnabled);
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetOwningPlayer());
	AGTAGameMode* M = GTA::Mode(this);
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!PC || !M || !P) return Layer;
	const FVector2f Size(G.GetLocalSize());
	const FVector2f Ctr = Size * 0.5f;
	const float Now = GetWorld()->GetTimeSeconds();

	// crosshair
	const FGTAWeaponDef& D = P->CurrentDef();
	const bool bGun = D.Cat != EGTAWeaponCat::Melee;
	if ((P->bAiming || (bGun && !P->IsInVehicle())) && !PC->IsMenuOpen() && !PC->bMapOpen && !P->bDead)
	{
		const AGTACharacter* AimC = Cast<AGTACharacter>(P->CachedAimActor);
		const bool bHostile = AimC && !AimC->bDead;
		const FLinearColor C = bHostile ? FLinearColor(1.f, 0.25f, 0.3f, 0.95f) : FLinearColor(1.f, 1.f, 1.f, P->bAiming ? 0.95f : 0.5f);
		if (P->IsScoped())
		{
			// scope overlay
			const float R = Size.Y * 0.42f;
			Circle(Out, Layer + 1, G, Ctr, R, FLinearColor(0, 0, 0, 0.9f), false, 4.f);
			Lines(Out, Layer + 1, G, { Ctr - FVector2f(R, 0), Ctr + FVector2f(R, 0) }, FLinearColor(0, 0, 0, 0.85f), 1.5f);
			Lines(Out, Layer + 1, G, { Ctr - FVector2f(0, R), Ctr + FVector2f(0, R) }, FLinearColor(0, 0, 0, 0.85f), 1.5f);
			Box(Out, Layer, G, FVector2f(0, 0), FVector2f(Ctr.X - R, Size.Y), FLinearColor(0, 0, 0, 0.92f));
			Box(Out, Layer, G, FVector2f(Ctr.X + R, 0), FVector2f(Size.X - Ctr.X - R, Size.Y), FLinearColor(0, 0, 0, 0.92f));
		}
		else
		{
			const float Gap = P->bAiming ? 5.f : 9.f;
			const float Len = 7.f;
			for (const FVector2f& Dir : { FVector2f(1, 0), FVector2f(-1, 0), FVector2f(0, 1), FVector2f(0, -1) })
				Lines(Out, Layer + 1, G, { Ctr + Dir * Gap, Ctr + Dir * (Gap + Len) }, C, 2.f);
			Circle(Out, Layer + 1, G, Ctr, 1.6f, C);
		}
	}
	// low-health vignette
	if (P->Health < 35.f && !P->bDead)
	{
		const float A = (1.f - P->Health / 35.f) * (0.35f + 0.15f * FMath::Sin(Now * 5.f));
		Box(Out, Layer + 2, G, FVector2f(0, 0), FVector2f(Size.X, 40.f), FLinearColor(0.8f, 0.f, 0.f, A));
		Box(Out, Layer + 2, G, FVector2f(0, Size.Y - 40.f), FVector2f(Size.X, 40.f), FLinearColor(0.8f, 0.f, 0.f, A));
	}
	// big message (WASTED / BUSTED / STUNT JUMP)
	if (!M->BigMessage.IsEmpty() && Now < M->BigMessageUntil)
	{
		const FSlateFontInfo F = Font(64);
		const FLinearColor Col = M->BigMessage == TEXT("BUSTED") ? FLinearColor(0.3f, 0.55f, 1.f) : (M->BigMessage == TEXT("WASTED") ? FLinearColor(1.f, 0.2f, 0.25f) : Amber);
		Box(Out, Layer + 3, G, FVector2f(0.f, Ctr.Y - 60.f), FVector2f(Size.X, 120.f), FLinearColor(0, 0, 0, 0.55f));
		Label(Out, Layer + 4, G, FVector2f(Ctr.X, Ctr.Y - 44.f), M->BigMessage, F, Col, 0.5f);
	}
	return Layer + 5;
}

// HUD: AHUD owner + the root UMG widget (anchored layout built in C++).
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "Blueprint/UserWidget.h"
#include "GTAHUD.generated.h"

class UCanvasPanel;
class UTextBlock;
class UProgressBar;
class UBorder;
class UGTAMapWidget;
class UGTAStarsWidget;
class UGTAWheelWidget;
class UGTAMenuWidget;

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTAHUDWidget : public UUserWidget
{
	GENERATED_BODY()
public:
	void BuildTree();
protected:
	virtual void NativeOnInitialized() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;
	virtual int32 NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;

	UPROPERTY() TObjectPtr<UCanvasPanel> Root;
	UPROPERTY() TObjectPtr<UTextBlock> MoneyText;
	UPROPERTY() TObjectPtr<UTextBlock> WeaponText;
	UPROPERTY() TObjectPtr<UTextBlock> AmmoText;
	UPROPERTY() TObjectPtr<UTextBlock> DistrictText;
	UPROPERTY() TObjectPtr<UTextBlock> NotifyText;
	UPROPERTY() TObjectPtr<UTextBlock> PromptText;
	UPROPERTY() TObjectPtr<UBorder> PromptBox;
	UPROPERTY() TObjectPtr<UTextBlock> SpeedText;
	UPROPERTY() TObjectPtr<UTextBlock> VehicleText;
	UPROPERTY() TObjectPtr<UBorder> VehicleBox;
	UPROPERTY() TObjectPtr<UProgressBar> VehicleHealthBar;
	UPROPERTY() TObjectPtr<UTextBlock> DebugText;
	UPROPERTY() TObjectPtr<UTextBlock> HintText;
	UPROPERTY() TObjectPtr<UProgressBar> HealthBar;
	UPROPERTY() TObjectPtr<UProgressBar> ArmorBar;
	UPROPERTY() TObjectPtr<UProgressBar> BreathBar;
	UPROPERTY() TObjectPtr<UGTAMapWidget> Minimap;
	UPROPERTY() TObjectPtr<UGTAMapWidget> BigMap;
	UPROPERTY() TObjectPtr<UGTAStarsWidget> Stars;
	UPROPERTY() TObjectPtr<UGTAWheelWidget> Wheel;
	UPROPERTY() TObjectPtr<UGTAMenuWidget> Menu;

	bool bMapWasOpen = false;
	float FPSAvg = 60.f;
	int32 LastMoney = -1;
	float MoneyFlash = 0.f;
	int32 MoneyDelta = 0;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API AGTAHUD : public AHUD
{
	GENERATED_BODY()
public:
	virtual void BeginPlay() override;
	UPROPERTY() TObjectPtr<UGTAHUDWidget> Widget;
};

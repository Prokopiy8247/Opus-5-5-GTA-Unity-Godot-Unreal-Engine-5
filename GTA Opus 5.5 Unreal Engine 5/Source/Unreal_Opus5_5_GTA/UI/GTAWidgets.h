// Project-owned UMG widgets with custom painting (minimap / full map, wanted stars, weapon wheel, menus).
#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "GTAWidgets.generated.h"

/** Shared drawing helpers and the "Neon Tide" UI palette. */
namespace GTAUI
{
	extern const FLinearColor Teal;
	extern const FLinearColor Pink;
	extern const FLinearColor Amber;
	extern const FLinearColor Panel;
	extern const FLinearColor Text;
	FSlateFontInfo Font(int32 Size, bool bBold = true);
	void Box(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Pos, const FVector2f& Size, const FLinearColor& C);
	void RotBox(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Center, const FVector2f& Size, float AngleRad, const FLinearColor& C);
	void Lines(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const TArray<FVector2f>& Pts, const FLinearColor& C, float Thick);
	void Poly(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const TArray<FVector2f>& Pts, const FLinearColor& C);
	void Circle(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Center, float R, const FLinearColor& C, bool bFill = true, float Thick = 2.f);
	void Label(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Pos, const FString& S, const FSlateFontInfo& F, const FLinearColor& C, float AlignX = 0.f);
	FVector2f Measure(const FString& S, const FSlateFontInfo& F);
	TArray<FVector2f> StarPoints(const FVector2f& C, float R);
}

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTAMapWidget : public UUserWidget
{
	GENERATED_BODY()
public:
	bool bFullMap = false;
	float Zoom = 0.06f;          // pixels per cm (minimap)
protected:
	virtual int32 NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
	virtual FReply NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
	virtual FReply NativeOnMouseWheel(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
private:
	FVector2f WorldToMap(const FVector& W, const FVector& Center, float Yaw, const FVector2f& Size, float Scale) const;
	FVector MapToWorld(const FVector2f& P, const FVector& Center, const FVector2f& Size, float Scale) const;
	float FullScale = 0.f;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTAStarsWidget : public UUserWidget
{
	GENERATED_BODY()
protected:
	virtual int32 NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTAWheelWidget : public UUserWidget
{
	GENERATED_BODY()
protected:
	virtual int32 NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
};

UCLASS()
class UNREAL_OPUS5_5_GTA_API UGTAMenuWidget : public UUserWidget
{
	GENERATED_BODY()
protected:
	virtual int32 NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
};

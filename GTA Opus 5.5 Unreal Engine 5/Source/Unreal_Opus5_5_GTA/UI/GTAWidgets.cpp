#include "UI/GTAWidgets.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Player/GTAPlayerCharacter.h"
#include "Player/GTAPlayerController.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "World/GTAPopulation.h"
#include "Rendering/DrawElements.h"
#include "Styling/CoreStyle.h"
#include "Framework/Application/SlateApplication.h"
#include "Fonts/FontMeasure.h"
#include "Kismet/GameplayStatics.h"
#include "Camera/PlayerCameraManager.h"
#include "EngineUtils.h"

// ------------------------------------------------------------------------------------------------ helpers

namespace GTAUI
{
	const FLinearColor Teal(0.08f, 0.85f, 0.78f, 1.f);
	const FLinearColor Pink(1.f, 0.16f, 0.52f, 1.f);
	const FLinearColor Amber(1.f, 0.72f, 0.18f, 1.f);
	const FLinearColor Panel(0.01f, 0.015f, 0.03f, 0.72f);
	const FLinearColor Text(0.95f, 0.97f, 1.f, 1.f);

	const FSlateBrush* White() { return FCoreStyle::Get().GetBrush("WhiteBrush"); }

	FSlateFontInfo Font(int32 Size, bool bBold)
	{
		FSlateFontInfo F = FCoreStyle::GetDefaultFontStyle(bBold ? "Bold" : "Regular", Size);
		F.OutlineSettings.OutlineSize = Size >= 16 ? 2 : 1;
		F.OutlineSettings.OutlineColor = FLinearColor(0.f, 0.f, 0.f, 0.85f);
		return F;
	}

	void Box(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Pos, const FVector2f& Size, const FLinearColor& C)
	{
		FSlateDrawElement::MakeBox(Out, Layer, G.ToPaintGeometry(Size, FSlateLayoutTransform(Pos)), White(), ESlateDrawEffect::None, C);
	}

	void RotBox(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Center, const FVector2f& Size, float AngleRad, const FLinearColor& C)
	{
		FSlateDrawElement::MakeBox(Out, Layer, G.ToPaintGeometry(Size, FSlateLayoutTransform(Center - Size * 0.5f), FSlateRenderTransform(FQuat2f(AngleRad)), FVector2f(0.5f, 0.5f)), White(), ESlateDrawEffect::None, C);
	}

	void Lines(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const TArray<FVector2f>& Pts, const FLinearColor& C, float Thick)
	{
		if (Pts.Num() < 2) return;
		FSlateDrawElement::MakeLines(Out, Layer, G.ToPaintGeometry(), Pts, ESlateDrawEffect::None, C, true, Thick);
	}

	void Poly(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const TArray<FVector2f>& Pts, const FLinearColor& C)
	{
		if (Pts.Num() < 3) return;
		const FSlateResourceHandle H = FSlateApplication::Get().GetRenderer()->GetResourceHandle(*White());
		const FSlateRenderTransform RT = G.GetAccumulatedRenderTransform();
		const FColor Col = C.ToFColor(true);
		TArray<FSlateVertex> V;
		TArray<SlateIndex> I;
		for (const FVector2f& P : Pts) V.Add(FSlateVertex::Make<ESlateVertexRounding::Disabled>(RT, P, FVector2f(0.5f, 0.5f), Col));
		for (int32 k = 1; k + 1 < Pts.Num(); ++k) { I.Add(0); I.Add(k); I.Add(k + 1); }
		FSlateDrawElement::MakeCustomVerts(Out, Layer, H, V, I, nullptr, 0, 0);
	}

	void Circle(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Center, float R, const FLinearColor& C, bool bFill, float Thick)
	{
		TArray<FVector2f> P;
		const int32 N = FMath::Clamp(FMath::RoundToInt(R * 0.6f), 12, 48);
		for (int32 i = 0; i <= N; ++i)
		{
			const float A = 2.f * PI * i / N;
			P.Add(Center + FVector2f(FMath::Cos(A), FMath::Sin(A)) * R);
		}
		if (bFill) { P.Pop(); Poly(Out, Layer, G, P, C); }
		else Lines(Out, Layer, G, P, C, Thick);
	}

	FVector2f Measure(const FString& S, const FSlateFontInfo& F)
	{
		const TSharedRef<FSlateFontMeasure> M = FSlateApplication::Get().GetRenderer()->GetFontMeasureService();
		return FVector2f(M->Measure(S, F));
	}

	void Label(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& Pos, const FString& S, const FSlateFontInfo& F, const FLinearColor& C, float AlignX)
	{
		FVector2f P = Pos;
		if (AlignX != 0.f) P.X -= Measure(S, F).X * AlignX;
		FSlateDrawElement::MakeText(Out, Layer, G.ToPaintGeometry(FVector2f(2000.f, 200.f), FSlateLayoutTransform(P)), S, F, ESlateDrawEffect::None, C);
	}

	TArray<FVector2f> StarPoints(const FVector2f& C, float R)
	{
		TArray<FVector2f> P;
		P.Add(C);   // fan center
		for (int32 i = 0; i <= 10; ++i)
		{
			const float A = -PI * 0.5f + PI * i / 5.f;
			const float Rad = (i % 2 == 0) ? R : R * 0.45f;
			P.Add(C + FVector2f(FMath::Cos(A), FMath::Sin(A)) * Rad);
		}
		return P;
	}
}

using namespace GTAUI;

// ------------------------------------------------------------------------------------------------ map / minimap

FVector2f UGTAMapWidget::WorldToMap(const FVector& W, const FVector& Center, float Yaw, const FVector2f& Size, float Scale) const
{
	const FVector D = W - Center;
	const float Rad = FMath::DegreesToRadians(Yaw);
	const float X = D.X * FMath::Cos(Rad) + D.Y * FMath::Sin(Rad);
	const float Y = -D.X * FMath::Sin(Rad) + D.Y * FMath::Cos(Rad);
	return Size * 0.5f + FVector2f(Y, -X) * Scale;
}

FVector UGTAMapWidget::MapToWorld(const FVector2f& P, const FVector& Center, const FVector2f& Size, float Scale) const
{
	const FVector2f D = (P - Size * 0.5f) / Scale;
	return Center + FVector(-D.Y, D.X, 0.f);
}

FReply UGTAMapWidget::NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	if (!bFullMap || FullScale <= 0.f) return FReply::Unhandled();
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetOwningPlayer());
	if (!PC) return FReply::Unhandled();
	if (InMouseEvent.GetEffectingButton() == EKeys::RightMouseButton)
	{
		PC->bHasWaypoint = false;
		return FReply::Handled();
	}
	const FVector2f Local = FVector2f(InGeometry.AbsoluteToLocal(InMouseEvent.GetScreenSpacePosition()));
	PC->Waypoint = MapToWorld(Local, FVector(6000.f, 0.f, 0.f), FVector2f(InGeometry.GetLocalSize()), FullScale);
	PC->bHasWaypoint = true;
	GTA::Play2D(this, TEXT("S_UI_Select"), 0.5f);
	return FReply::Handled();
}

FReply UGTAMapWidget::NativeOnMouseWheel(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	return FReply::Handled();
}

int32 UGTAMapWidget::NativePaint(const FPaintArgs& Args, const FGeometry& G, const FSlateRect& Cull, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const
{
	Layer = Super::NativePaint(Args, G, Cull, Out, Layer, Style, bParentEnabled);
	AGTAGameMode* M = GTA::Mode(this);
	AGTAPlayerCharacter* P = GTA::Player(this);
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetOwningPlayer());
	if (!M || !M->City || !P || !PC) return Layer;
	const AGTACity* C = M->City;
	const FVector2f Size(G.GetLocalSize());
	const float Now = GetWorld()->GetTimeSeconds();
	FVector Center = P->GetActorLocation();
	float Yaw = 0.f;
	float Scale = Zoom;
	if (bFullMap)
	{
		Center = FVector(6000.f, 0.f, 0.f);
		Scale = FMath::Min(Size.X, Size.Y) / 64000.f;
		const_cast<UGTAMapWidget*>(this)->FullScale = Scale;
	}
	else
	{
		if (PC->PlayerCameraManager) Yaw = PC->PlayerCameraManager->GetCameraRotation().Yaw;
		const float Speed = P->IsInVehicle() && P->Vehicle ? P->Vehicle->SpeedKmh() : 0.f;
		Scale = Zoom * FMath::GetMappedRangeValueClamped(FVector2D(30.f, 150.f), FVector2D(1.f, 0.6f), Speed);
	}
	auto ToMap = [&](const FVector& W) { return WorldToMap(W, Center, Yaw, Size, Scale); };
	auto Rect = [&](float X0, float Y0, float X1, float Y1, const FLinearColor& Col, int32 L)
	{
		TArray<FVector2f> Q = { ToMap(FVector(X0, Y0, 0)), ToMap(FVector(X1, Y0, 0)), ToMap(FVector(X1, Y1, 0)), ToMap(FVector(X0, Y1, 0)) };
		Poly(Out, L, G, Q, Col);
	};
	// background: sea, land, beach
	Box(Out, Layer + 1, G, FVector2f(0.f), Size, FLinearColor(0.02f, 0.11f, 0.16f, 0.92f));
	Rect(AGTACity::CoastX, -30000.f, 30000.f, 30000.f, FLinearColor(0.11f, 0.12f, 0.14f, 1.f), Layer + 2);
	Rect(-19840.f, -19000.f, AGTACity::CoastX, 30000.f, FLinearColor(0.55f, 0.48f, 0.32f, 1.f), Layer + 2);
	Rect(17200.f, 17300.f - 800.f, 30000.f, 30000.f, FLinearColor(0.13f, 0.2f, 0.12f, 1.f), Layer + 2);
	Rect(-15000.f, 22500.f, 27000.f, 25500.f, FLinearColor(0.25f, 0.25f, 0.27f, 1.f), Layer + 3);
	Rect(18300.f, -3200.f, 30000.f, 17200.f, FLinearColor(0.12f, 0.24f, 0.12f, 1.f), Layer + 3);
	for (const FGTABlock& B : C->Blocks)
	{
		FLinearColor Col(0.17f, 0.18f, 0.21f, 1.f);
		if (B.District == EGTADistrict::Hills) Col = FLinearColor(0.15f, 0.21f, 0.15f, 1.f);
		else if (B.District == EGTADistrict::Downtown) Col = FLinearColor(0.2f, 0.19f, 0.25f, 1.f);
		else if (B.District == EGTADistrict::Industrial || B.District == EGTADistrict::Harbor) Col = FLinearColor(0.2f, 0.17f, 0.14f, 1.f);
		Rect(B.Rect.Min.X, B.Rect.Min.Y, B.Rect.Max.X, B.Rect.Max.Y, Col, Layer + 3);
	}
	// roads
	const float RoadPx = FMath::Max(2.f, 1000.f * Scale);
	for (const FGTARoadEdge& E : C->Edges)
	{
		Lines(Out, Layer + 4, G, { ToMap(C->Nodes[E.A].Pos), ToMap(C->Nodes[E.B].Pos) }, FLinearColor(0.62f, 0.64f, 0.7f, 1.f), RoadPx);
	}
	// points of interest
	const FSlateFontInfo Small = Font(bFullMap ? 9 : 8);
	for (const FGTAPOIData& Poi : C->POIs)
	{
		FLinearColor Col = Teal;
		FString Ch = TEXT("•");
		switch (Poi.Type)
		{
		case EGTAPOI::Safehouse: Col = FLinearColor(0.3f, 1.f, 0.4f); Ch = TEXT("H"); break;
		case EGTAPOI::GunShop: Col = FLinearColor(1.f, 0.3f, 0.3f); Ch = TEXT("A"); break;
		case EGTAPOI::ModShop: Col = Amber; Ch = TEXT("C"); break;
		case EGTAPOI::ClothesShop: Col = Pink; Ch = TEXT("W"); break;
		case EGTAPOI::Barber: Col = Pink; Ch = TEXT("B"); break;
		case EGTAPOI::Garage: Col = FLinearColor(0.5f, 0.8f, 1.f); Ch = TEXT("G"); break;
		case EGTAPOI::PoliceStation: Col = FLinearColor(0.3f, 0.5f, 1.f); Ch = TEXT("P"); break;
		case EGTAPOI::Hospital: Col = FLinearColor(1.f, 1.f, 1.f); Ch = TEXT("+"); break;
		case EGTAPOI::StuntJump: Col = Amber; Ch = TEXT("J"); break;
		case EGTAPOI::Helipad: case EGTAPOI::Hangar: Col = FLinearColor(0.8f, 0.8f, 1.f); Ch = TEXT("F"); break;
		case EGTAPOI::Marina: Col = FLinearColor(0.4f, 0.8f, 1.f); Ch = TEXT("M"); break;
		default: break;
		}
		const FVector2f Pm = ToMap(Poi.T.GetLocation());
		if (!bFullMap && (Pm.X < -10.f || Pm.Y < -10.f || Pm.X > Size.X + 10.f || Pm.Y > Size.Y + 10.f)) continue;
		Circle(Out, Layer + 5, G, Pm, bFullMap ? 9.f : 7.f, FLinearColor(0.f, 0.f, 0.f, 0.75f));
		Label(Out, Layer + 6, G, Pm - FVector2f(0.f, bFullMap ? 7.f : 6.f), Ch, Small, Col, 0.5f);
		if (bFullMap) Label(Out, Layer + 6, G, Pm + FVector2f(12.f, -6.f), Poi.Name, Small, FLinearColor(1, 1, 1, 0.8f));
	}
	// wanted: search area and police
	if (M->WantedLevel > 0)
	{
		const bool bSearch = M->WantedState == EGTAWantedState::Search;
		const float Pulse = 0.5f + 0.5f * FMath::Sin(Now * 6.f);
		if (bSearch) Circle(Out, Layer + 6, G, ToMap(M->LastKnownPos), M->SearchRadius() * Scale, FLinearColor(1.f, 0.2f, 0.3f, 0.12f + 0.08f * Pulse));
		if (M->Population)
		{
			for (AGTACharacter* Cop : M->Population->PoliceUnits)
			{
				if (!IsValid(Cop) || Cop->bDead) continue;
				const FVector2f Pm = ToMap(Cop->GetActorLocation());
				const bool bRed = FMath::Fmod(Now * 3.f + Cop->GetUniqueID() % 7, 2.f) < 1.f;
				if (bSearch)
				{
					// vision cone
					const FVector Fwd = Cop->IsInVehicle() && Cop->Vehicle ? Cop->Vehicle->GetActorForwardVector() : Cop->GetActorForwardVector();
					const float R = M->PoliceSightRange() * 0.5f;
					const FVector L = Cop->GetActorLocation();
					Poly(Out, Layer + 6, G, { Pm, ToMap(L + Fwd.RotateAngleAxis(-35.f, FVector::UpVector) * R), ToMap(L + Fwd.RotateAngleAxis(35.f, FVector::UpVector) * R) }, FLinearColor(0.3f, 0.5f, 1.f, 0.18f));
				}
				Circle(Out, Layer + 7, G, Pm, 4.f, bRed ? FLinearColor(1.f, 0.15f, 0.15f) : FLinearColor(0.2f, 0.4f, 1.f));
			}
		}
	}
	// waypoint
	if (PC->bHasWaypoint)
	{
		FVector2f W = ToMap(PC->Waypoint);
		if (!bFullMap)
		{
			const FVector2f Ctr = Size * 0.5f;
			const FVector2f D = W - Ctr;
			const float Lim = FMath::Min(Size.X, Size.Y) * 0.5f - 8.f;
			if (D.Size() > Lim) W = Ctr + D.GetSafeNormal() * Lim;
		}
		Poly(Out, Layer + 8, G, { W + FVector2f(0, -8), W + FVector2f(8, 0), W + FVector2f(0, 8), W + FVector2f(-8, 0) }, Amber);
	}
	// player arrow
	{
		const FVector2f Pm = ToMap(P->GetActorLocation());
		const float A = FMath::DegreesToRadians((P->IsInVehicle() && P->Vehicle ? P->Vehicle->GetActorRotation().Yaw : P->GetActorRotation().Yaw) - Yaw);
		const FVector2f F(FMath::Sin(A), -FMath::Cos(A));
		const FVector2f R(-F.Y, F.X);
		const float S = bFullMap ? 9.f : 8.f;
		Poly(Out, Layer + 9, G, { Pm + F * S * 1.3f, Pm - F * S * 0.8f + R * S * 0.8f, Pm - F * S * 0.4f, Pm - F * S * 0.8f - R * S * 0.8f }, FLinearColor::White);
	}
	// north marker + frame
	if (!bFullMap)
	{
		const float NA = FMath::DegreesToRadians(-Yaw);
		const FVector2f Ctr = Size * 0.5f;
		const FVector2f NPos = Ctr + FVector2f(FMath::Sin(NA), -FMath::Cos(NA)) * (FMath::Min(Size.X, Size.Y) * 0.5f - 12.f);
		Circle(Out, Layer + 9, G, NPos, 9.f, FLinearColor(0, 0, 0, 0.8f));
		Label(Out, Layer + 10, G, NPos - FVector2f(0.f, 8.f), TEXT("N"), Font(9), FLinearColor::White, 0.5f);
		Lines(Out, Layer + 10, G, { FVector2f(0, 0), FVector2f(Size.X, 0), FVector2f(Size.X, Size.Y), FVector2f(0, Size.Y), FVector2f(0, 0) }, FLinearColor(0.f, 0.f, 0.f, 0.9f), 3.f);
	}
	else
	{
		Label(Out, Layer + 10, G, FVector2f(16.f, 12.f), TEXT("PORT HALCYON — click to set waypoint · right click clears · M closes"), Font(14), Teal);
	}
	return Layer + 10;
}

// ------------------------------------------------------------------------------------------------ wanted stars

int32 UGTAStarsWidget::NativePaint(const FPaintArgs& Args, const FGeometry& G, const FSlateRect& Cull, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const
{
	Layer = Super::NativePaint(Args, G, Cull, Out, Layer, Style, bParentEnabled);
	AGTAGameMode* M = GTA::Mode(this);
	if (!M) return Layer;
	const FVector2f Size(G.GetLocalSize());
	const float R = Size.Y * 0.42f;
	const float Now = GetWorld()->GetRealTimeSeconds();
	const bool bSearch = M->WantedState == EGTAWantedState::Search;
	const float Flash = bSearch ? (FMath::Fmod(Now, 0.8f) < 0.4f ? 1.f : 0.35f) : 1.f;
	for (int32 i = 0; i < 5; ++i)
	{
		const FVector2f C(Size.X - R - i * (R * 2.3f), Size.Y * 0.5f);
		const bool bOn = (4 - i) < M->WantedLevel;
		TArray<FVector2f> P = StarPoints(C, R);
		TArray<FVector2f> Outline = P;
		Outline.RemoveAt(0);
		if (bOn) Poly(Out, Layer + 1, G, P, Amber * FLinearColor(1, 1, 1, Flash));
		else Poly(Out, Layer + 1, G, P, FLinearColor(0.f, 0.f, 0.f, M->WantedLevel > 0 ? 0.45f : 0.25f));
		Lines(Out, Layer + 2, G, Outline, FLinearColor(1.f, 1.f, 1.f, M->WantedLevel > 0 ? 0.9f : 0.35f), 1.5f);
	}
	if (M->WantedLevel > 0 && bSearch)
	{
		const float T = FMath::Clamp(M->EscapeProgress / M->EscapeRequired(), 0.f, 1.f);
		Box(Out, Layer + 1, G, FVector2f(Size.X - 5 * R * 2.3f, Size.Y - 3.f), FVector2f(5 * R * 2.3f, 3.f), FLinearColor(0, 0, 0, 0.6f));
		Box(Out, Layer + 2, G, FVector2f(Size.X - 5 * R * 2.3f, Size.Y - 3.f), FVector2f(5 * R * 2.3f * T, 3.f), Teal);
	}
	return Layer + 3;
}

// ------------------------------------------------------------------------------------------------ weapon wheel

int32 UGTAWheelWidget::NativePaint(const FPaintArgs& Args, const FGeometry& G, const FSlateRect& Cull, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const
{
	Layer = Super::NativePaint(Args, G, Cull, Out, Layer, Style, bParentEnabled);
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetOwningPlayer());
	AGTAPlayerCharacter* P = PC ? PC->PlayerChar.Get() : nullptr;
	if (!PC || !P || !PC->bWheelOpen) return Layer;
	const FVector2f Size(G.GetLocalSize());
	const FVector2f Ctr = Size * 0.5f;
	const float R0 = 90.f, R1 = 230.f;
	for (int32 c = 0; c < 8; ++c)
	{
		const float A0 = FMath::DegreesToRadians(c * 45.f - 22.5f + 1.5f) - PI * 0.5f;
		const float A1 = FMath::DegreesToRadians(c * 45.f + 22.5f - 1.5f) - PI * 0.5f;
		TArray<FVector2f> Seg;
		for (int32 k = 0; k <= 8; ++k) { const float A = FMath::Lerp(A0, A1, k / 8.f); Seg.Add(Ctr + FVector2f(FMath::Cos(A), FMath::Sin(A)) * R1); }
		for (int32 k = 8; k >= 0; --k) { const float A = FMath::Lerp(A0, A1, k / 8.f); Seg.Add(Ctr + FVector2f(FMath::Cos(A), FMath::Sin(A)) * R0); }
		const bool bHover = c == PC->WheelHover;
		// owned weapon of this category (highest)
		const FGTAWeaponSlot* Owned = nullptr;
		for (const FGTAWeaponSlot& S : P->Weapons) if (AGTAPlayerController::WheelCategoryOf(S.Id) == c) Owned = &S;
		const FLinearColor Fill = bHover ? FLinearColor(Pink.R, Pink.G, Pink.B, 0.8f) : FLinearColor(0.f, 0.02f, 0.05f, Owned ? 0.75f : 0.4f);
		// fan-triangulate the ring segment as quads
		for (int32 k = 0; k < 8; ++k)
		{
			Poly(Out, Layer + 1, G, { Seg[k], Seg[k + 1], Seg[17 - k - 1], Seg[17 - k] }, Fill);
		}
		const float AM = FMath::DegreesToRadians(c * 45.f) - PI * 0.5f;
		const FVector2f LP = Ctr + FVector2f(FMath::Cos(AM), FMath::Sin(AM)) * ((R0 + R1) * 0.5f);
		Label(Out, Layer + 2, G, LP - FVector2f(0.f, 18.f), AGTAPlayerController::WheelCategoryName(c), Font(11), Owned ? Text : FLinearColor(1, 1, 1, 0.35f), 0.5f);
		if (Owned)
		{
			const FGTAWeaponDef& D = FGTAData::Weapon(Owned->Id);
			Label(Out, Layer + 2, G, LP, D.Name, Font(9, false), Teal, 0.5f);
			if (D.Clip > 0) Label(Out, Layer + 2, G, LP + FVector2f(0.f, 14.f), FString::Printf(TEXT("%d | %d"), Owned->InClip, Owned->Reserve), Font(9, false), Text, 0.5f);
		}
	}
	Circle(Out, Layer + 1, G, Ctr, R0 - 6.f, FLinearColor(0.f, 0.f, 0.f, 0.7f));
	const FString Cur = PC->WheelHover >= 0 ? AGTAPlayerController::WheelCategoryName(PC->WheelHover) : TEXT("");
	Label(Out, Layer + 2, G, Ctr - FVector2f(0.f, 10.f), Cur, Font(14), Amber, 0.5f);
	// cursor
	Circle(Out, Layer + 3, G, Ctr + FVector2f(PC->WheelCursor) * 0.75f, 5.f, FLinearColor::White);
	return Layer + 3;
}

// ------------------------------------------------------------------------------------------------ menu

int32 UGTAMenuWidget::NativePaint(const FPaintArgs& Args, const FGeometry& G, const FSlateRect& Cull, FSlateWindowElementList& Out, int32 Layer, const FWidgetStyle& Style, bool bParentEnabled) const
{
	Layer = Super::NativePaint(Args, G, Cull, Out, Layer, Style, bParentEnabled);
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetOwningPlayer());
	if (!PC || !PC->IsMenuOpen()) return Layer;
	const FGTAMenu& M = PC->MenuStack.Last();
	const float W = G.GetLocalSize().X;
	const float RowH = 30.f;
	const int32 MaxRows = 16;
	float Y = 0.f;
	Box(Out, Layer + 1, G, FVector2f(0.f, 0.f), FVector2f(W, 64.f), Teal);
	Label(Out, Layer + 2, G, FVector2f(18.f, 12.f), M.Title, Font(22), FLinearColor(0.01f, 0.02f, 0.03f, 1.f));
	Y = 64.f;
	if (!M.Subtitle.IsEmpty())
	{
		Box(Out, Layer + 1, G, FVector2f(0.f, Y), FVector2f(W, 28.f), FLinearColor(0.f, 0.f, 0.f, 0.85f));
		Label(Out, Layer + 2, G, FVector2f(18.f, Y + 5.f), M.Subtitle, Font(11, false), Teal);
		Y += 28.f;
	}
	const int32 First = FMath::Clamp(M.Selected - MaxRows / 2, 0, FMath::Max(0, M.Items.Num() - MaxRows));
	const int32 Last = FMath::Min(M.Items.Num(), First + MaxRows);
	for (int32 i = First; i < Last; ++i)
	{
		const FGTAMenuItem& It = M.Items[i];
		const bool bSel = i == M.Selected;
		Box(Out, Layer + 1, G, FVector2f(0.f, Y), FVector2f(W, RowH), bSel ? FLinearColor(1.f, 1.f, 1.f, 0.92f) : Panel);
		const FLinearColor TC = !It.bEnabled ? FLinearColor(0.5f, 0.5f, 0.5f, 1.f) : (bSel ? FLinearColor(0.02f, 0.02f, 0.04f, 1.f) : Text);
		Label(Out, Layer + 2, G, FVector2f(18.f, Y + 6.f), It.Label, Font(12, bSel), TC);
		FString V = It.Value;
		if (It.OnAdjust && bSel) V = TEXT("‹ ") + V + TEXT(" ›");
		if (!V.IsEmpty()) Label(Out, Layer + 2, G, FVector2f(W - 16.f, Y + 6.f), V, Font(12, bSel), bSel ? FLinearColor(0.75f, 0.05f, 0.35f, 1.f) : Teal, 1.f);
		Y += RowH;
	}
	if (M.Items.Num() > MaxRows)
	{
		Box(Out, Layer + 1, G, FVector2f(0.f, Y), FVector2f(W, 22.f), FLinearColor(0, 0, 0, 0.85f));
		Label(Out, Layer + 2, G, FVector2f(W * 0.5f, Y + 3.f), FString::Printf(TEXT("%d / %d"), M.Selected + 1, M.Items.Num()), Font(10, false), Text, 0.5f);
		Y += 22.f;
	}
	if (M.Items.IsValidIndex(M.Selected) && !M.Items[M.Selected].Hint.IsEmpty())
	{
		Box(Out, Layer + 1, G, FVector2f(0.f, Y + 6.f), FVector2f(W, 34.f), FLinearColor(0.f, 0.f, 0.f, 0.85f));
		Box(Out, Layer + 2, G, FVector2f(0.f, Y + 6.f), FVector2f(4.f, 34.f), Pink);
		Label(Out, Layer + 2, G, FVector2f(16.f, Y + 14.f), M.Items[M.Selected].Hint, Font(10, false), Text);
	}
	return Layer + 3;
}

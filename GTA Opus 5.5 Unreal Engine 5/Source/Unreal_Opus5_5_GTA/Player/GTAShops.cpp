// Contextual interactions: shops, mod shop, garages, safehouses, services and stunt jumps.
#include "Player/GTAPlayerController.h"
#include "Player/GTAPlayerCharacter.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Core/GTAGameInstance.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "World/GTAEnvironment.h"
#include "World/GTAPopulation.h"
#include "GameFramework/WorldSettings.h"

namespace
{
	FGTAMenuItem ShopItem(const FString& Label, const FString& Value, TFunction<void()> F, const FString& Hint = FString())
	{
		FGTAMenuItem I;
		I.Label = Label;
		I.Value = Value;
		I.OnSelect = MoveTemp(F);
		I.Hint = Hint;
		return I;
	}
	FGTAMenuItem ShopAdjust(const FString& Label, const FString& Value, TFunction<void(int32)> F, const FString& Hint = FString())
	{
		FGTAMenuItem I;
		I.Label = Label;
		I.Value = Value;
		I.OnAdjust = MoveTemp(F);
		I.Hint = Hint;
		return I;
	}
	bool Pay(UObject* Ctx, int32 Price)
	{
		UGTAGameInstance* GI = GTA::Instance(Ctx);
		if (GI && GI->bAllModsUnlocked) return true;
		return GTA::SpendMoney(Ctx, Price);
	}
	const TCHAR* GFinish[] = { TEXT("Gloss"), TEXT("Metallic"), TEXT("Matte"), TEXT("Chrome") };
	const TCHAR* GHair[] = { TEXT("Shaved"), TEXT("Short"), TEXT("Long"), TEXT("Ponytail"), TEXT("Mohawk"), TEXT("Bun") };
	const TCHAR* GHat[] = { TEXT("None"), TEXT("Cap"), TEXT("Beanie"), TEXT("Police cap"), TEXT("Helmet") };
	const TCHAR* GGlasses[] = { TEXT("None"), TEXT("Sunglasses"), TEXT("Glasses") };
	const TCHAR* GBody[] = { TEXT("Casual (M)"), TEXT("Jacket (M)"), TEXT("Casual (F)"), TEXT("Skirt (F)") };
	const TCHAR* GLevel[] = { TEXT("Stock"), TEXT("Level 1"), TEXT("Level 2"), TEXT("Level 3"), TEXT("Level 4") };
	const TCHAR* GLights[] = { TEXT("White"), TEXT("Xenon blue"), TEXT("Amber") };
	const TCHAR* GTint[] = { TEXT("None"), TEXT("Light"), TEXT("Dark"), TEXT("Limo") };
	const TCHAR* GLivery[] = { TEXT("None"), TEXT("Racing stripes"), TEXT("Two-tone") };
	const TCHAR* GRoof[] = { TEXT("Stock"), TEXT("Roof rack"), TEXT("Open top") };
}

// ------------------------------------------------------------------------------------------------ context prompt / interaction

void AGTAPlayerController::TickContext(float Dt)
{
	ContextPrompt.Reset();
	AGTAGameMode* GM = GTA::Mode(this);
	if (!PlayerChar || !GM || !GM->City || PlayerChar->bDead) return;
	const FVector L = PlayerChar->GetActorLocation();
	const bool bInVeh = PlayerChar->IsInVehicle();
	for (const FGTAPOIData& P : GM->City->POIs)
	{
		const float R = (P.Type == EGTAPOI::ModShop || P.Type == EGTAPOI::Garage) ? 900.f : 450.f;
		if (FVector::Dist2D(P.T.GetLocation(), L) > R) continue;
		switch (P.Type)
		{
		case EGTAPOI::Safehouse: if (!bInVeh) ContextPrompt = FString::Printf(TEXT("E  %s (save / sleep / wardrobe)"), *P.Name); break;
		case EGTAPOI::GunShop: if (!bInVeh) ContextPrompt = TEXT("E  Halcyon Arms — weapons & mods"); break;
		case EGTAPOI::ClothesShop: if (!bInVeh) ContextPrompt = TEXT("E  Driftwear — clothing"); break;
		case EGTAPOI::Barber: if (!bInVeh) ContextPrompt = TEXT("E  Salt & Fade — hair"); break;
		case EGTAPOI::ModShop: ContextPrompt = bInVeh ? TEXT("E  Riptide Customs — repair, respray & upgrades") : TEXT("Drive a vehicle in to customize it"); break;
		case EGTAPOI::Garage: ContextPrompt = FString::Printf(TEXT("E  %s — store / retrieve / buy vehicles"), *P.Name); break;
		case EGTAPOI::Diner: if (!bInVeh) ContextPrompt = TEXT("E  Neon Gull Diner — eat ($15)"); break;
		case EGTAPOI::GasStation: if (!bInVeh) ContextPrompt = TEXT("E  Tidewater Fuel — snacks ($10)"); break;
		case EGTAPOI::Hospital: if (!bInVeh) ContextPrompt = TEXT("E  St. Brine — treatment ($200)"); break;
		case EGTAPOI::Marina: if (!bInVeh) ContextPrompt = TEXT("E  Rent a speedboat ($300)"); break;
		case EGTAPOI::Hangar: if (!bInVeh) ContextPrompt = TEXT("E  Rent an aircraft"); break;
		case EGTAPOI::Helipad: if (!bInVeh) ContextPrompt = TEXT("E  Rent a helicopter ($1500)"); break;
		case EGTAPOI::TaxiStand: if (!bInVeh) ContextPrompt = TEXT("E  Call a Neon Cab"); break;
		default: break;
		}
		if (!ContextPrompt.IsEmpty()) break;
	}
	if (ContextPrompt.IsEmpty() && PlayerChar && !PlayerChar->InteractPrompt.IsEmpty()) ContextPrompt = PlayerChar->InteractPrompt;
}

void AGTAPlayerController::Interact()
{
	AGTAGameMode* GM = GTA::Mode(this);
	if (!PlayerChar || !GM || !GM->City) return;
	const float Now = GetWorld()->GetTimeSeconds();
	if (Now < NextInteractTime) return;
	NextInteractTime = Now + 0.3f;
	const FVector L = PlayerChar->GetActorLocation();
	const bool bInVeh = PlayerChar->IsInVehicle();
	for (const FGTAPOIData& P : GM->City->POIs)
	{
		const float R = (P.Type == EGTAPOI::ModShop || P.Type == EGTAPOI::Garage) ? 900.f : 450.f;
		if (FVector::Dist2D(P.T.GetLocation(), L) > R) continue;
		switch (P.Type)
		{
		case EGTAPOI::Safehouse: if (!bInVeh) { OpenSafehouse(P.Index); return; } break;
		case EGTAPOI::GunShop: if (!bInVeh) { OpenWeaponShop(); return; } break;
		case EGTAPOI::ClothesShop: if (!bInVeh) { OpenClothesShop(false); return; } break;
		case EGTAPOI::Barber: if (!bInVeh) { OpenClothesShop(true); return; } break;
		case EGTAPOI::ModShop: if (bInVeh) { OpenModShop(); return; } break;
		case EGTAPOI::Garage: OpenGarage(P.Index); return;
		case EGTAPOI::Diner:
			if (!bInVeh && GTA::SpendMoney(this, 15)) { PlayerChar->Heal(40.f); GTA::Notify(this, TEXT("Tasty. +Health"), 2.f); }
			return;
		case EGTAPOI::GasStation:
			if (!bInVeh && GTA::SpendMoney(this, 10)) { PlayerChar->Heal(25.f); GTA::Notify(this, TEXT("Snack bought. +Health"), 2.f); }
			return;
		case EGTAPOI::Hospital:
			if (!bInVeh && GTA::SpendMoney(this, 200)) { PlayerChar->Health = PlayerChar->MaxHealth; GTA::Notify(this, TEXT("Fully treated."), 2.f); }
			return;
		case EGTAPOI::Marina:
			if (!bInVeh && GTA::SpendMoney(this, 300))
			{
				const FTransform T(FRotator(0.f, 180.f, 0.f), P.T.GetLocation() + FVector(-1100.f, 0.f, GTA::SeaLevel()));
				if (AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), EGTAVehicle::Speedboat, T)) { V->bPlayerOwned = true; EnterVehicle(V, 0); }
			}
			return;
		case EGTAPOI::Hangar:
			if (!bInVeh)
			{
				FGTAMenu M;
				M.Title = TEXT("GULLWING FIELD — AIRCRAFT RENTAL");
				M.Items.Add(ShopItem(TEXT("Gull prop plane"), TEXT("$800"), [this]()
				{
					if (!GTA::SpendMoney(this, 800)) return;
					if (AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), EGTAVehicle::PropPlane, FTransform(FRotator::ZeroRotator, FVector(-13500.f, 24000.f, 60.f)))) { V->bPlayerOwned = true; CloseAllMenus(); EnterVehicle(V, 0); }
				}));
				M.Items.Add(ShopItem(TEXT("Swift jet"), TEXT("$2500"), [this]()
				{
					if (!GTA::SpendMoney(this, 2500)) return;
					if (AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), EGTAVehicle::Jet, FTransform(FRotator::ZeroRotator, FVector(-13500.f, 24000.f, 60.f)))) { V->bPlayerOwned = true; CloseAllMenus(); EnterVehicle(V, 0); }
				}));
				M.Items.Add(ShopItem(TEXT("Parachute"), TEXT("$250"), [this]() { if (GTA::SpendMoney(this, 250)) PlayerChar->SetHasParachute(true); }));
				OpenMenu(M);
				return;
			}
			break;
		case EGTAPOI::Helipad:
			if (!bInVeh && GTA::SpendMoney(this, 1500))
			{
				if (AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), EGTAVehicle::Helicopter, FTransform(FRotator::ZeroRotator, P.T.GetLocation() + FVector(0, 0, 60.f)))) { V->bPlayerOwned = true; EnterVehicle(V, 0); }
			}
			return;
		case EGTAPOI::TaxiStand:
			if (!bInVeh && GM->Population) GM->Population->CallTaxi(L);
			return;
		default: break;
		}
	}
}

// ------------------------------------------------------------------------------------------------ weapon shop

void AGTAPlayerController::OpenShop(int32 PoiType)
{
	switch ((EGTAPOI)PoiType)
	{
	case EGTAPOI::GunShop: OpenWeaponShop(); break;
	case EGTAPOI::ClothesShop: OpenClothesShop(false); break;
	case EGTAPOI::Barber: OpenClothesShop(true); break;
	case EGTAPOI::ModShop: OpenModShop(); break;
	default: break;
	}
}

void AGTAPlayerController::OpenWeaponShop()
{
	FGTAMenu M;
	M.Title = TEXT("HALCYON ARMS");
	M.Rebuild = [this](FGTAMenu& Menu)
	{
		AGTAPlayerCharacter* P = PlayerChar;
		if (!P) return;
		Menu.Subtitle = FString::Printf(TEXT("Cash $%d"), GTA::Money(this));
		for (int32 i = 1; i < (int32)EGTAWeapon::MAX; ++i)
		{
			const EGTAWeapon W = (EGTAWeapon)i;
			const FGTAWeaponDef& D = FGTAData::Weapon(W);
			if (D.Price <= 0) continue;
			const bool bOwned = P->HasWeapon(W);
			if (!bOwned)
			{
				Menu.Items.Add(ShopItem(D.Name, FString::Printf(TEXT("$%d"), D.Price), [this, W, D]()
				{
					if (GTA::SpendMoney(this, D.Price)) { PlayerChar->GiveWeapon(W, D.Clip * 3, true); GTA::Notify(this, D.Name + TEXT(" purchased"), 2.f); }
				}, FString::Printf(TEXT("Damage %.0f · Mag %d · %s"), D.Damage, D.Clip, D.bAuto ? TEXT("automatic") : TEXT("semi-auto"))));
			}
			else if (D.Clip > 0)
			{
				Menu.Items.Add(ShopItem(D.Name + TEXT(" — ammo"), FString::Printf(TEXT("$%d"), D.AmmoPrice), [this, W, D]()
				{
					if (GTA::SpendMoney(this, D.AmmoPrice)) PlayerChar->GiveWeapon(W, D.Clip * 2, false);
				}, TEXT("Two magazines")));
			}
		}
		// mods for the equipped weapon
		FGTAWeaponSlot* S = P->CurrentSlotPtr();
		if (S && FGTAData::Weapon(S->Id).bModdable)
		{
			for (int32 m = 0; m < (int32)EGTAWeaponMod::MAX; ++m)
			{
				const EGTAWeaponMod Mod = (EGTAWeaponMod)m;
				if (!FGTAData::WeaponModAllowed(S->Id, Mod)) continue;
				const bool bHas = S->HasMod(Mod);
				Menu.Items.Add(ShopItem(FString::Printf(TEXT("%s: %s"), *FGTAData::Weapon(S->Id).Name, *FGTAData::WeaponModName(Mod)), bHas ? TEXT("Remove") : FString::Printf(TEXT("$%d"), FGTAData::WeaponModPrice(Mod)), [this, Mod]()
				{
					FGTAWeaponSlot* Slot = PlayerChar->CurrentSlotPtr();
					if (!Slot) return;
					const uint8 Bit = 1 << (uint8)Mod;
					if (Slot->Mods & Bit) Slot->Mods &= ~Bit;
					else if (Pay(this, FGTAData::WeaponModPrice(Mod))) Slot->Mods |= Bit;
					PlayerChar->UpdateWeaponVisual();
				}));
			}
			Menu.Items.Add(ShopAdjust(TEXT("Weapon tint"), FString::Printf(TEXT("%d / 5"), S->Tint + 1), [this](int32 D)
			{
				FGTAWeaponSlot* Slot = PlayerChar->CurrentSlotPtr();
				if (Slot && Pay(this, 150)) { Slot->Tint = (Slot->Tint + D + 5) % 5; PlayerChar->UpdateWeaponVisual(); }
			}, TEXT("$150 per change")));
		}
		Menu.Items.Add(ShopItem(TEXT("Body armor"), TEXT("$500"), [this]() { if (PlayerChar->Armor < 100.f && GTA::SpendMoney(this, 500)) PlayerChar->Armor = 100.f; }));
		Menu.Items.Add(ShopItem(TEXT("Parachute"), TEXT("$250"), [this]() { if (!PlayerChar->bHasParachute && GTA::SpendMoney(this, 250)) PlayerChar->SetHasParachute(true); }));
	};
	OpenMenu(M);
}

// ------------------------------------------------------------------------------------------------ clothing / barber

void AGTAPlayerController::OpenClothesShop(bool bBarber)
{
	FGTAMenu M;
	M.Title = bBarber ? TEXT("SALT & FADE BARBERS") : TEXT("DRIFTWEAR");
	M.Rebuild = [this, bBarber](FGTAMenu& Menu)
	{
		AGTAPlayerCharacter* P = PlayerChar;
		if (!P) return;
		FGTAAppearance& A = P->Appearance;
		Menu.Subtitle = FString::Printf(TEXT("Cash $%d · ←/→ to change (charged per change)"), GTA::Money(this));
		auto Cycle = [this, P](int32& Field, int32 Count, int32 Price)
		{
			return [this, P, &Field, Count, Price](int32 D)
			{
				if (!Pay(this, Price)) return;
				Field = (Field + D + Count) % Count;
				P->ApplyAppearance();
				P->SaveToProfile();
			};
		};
		auto Color = [this, P](FLinearColor& Field, int32 Price)
		{
			return [this, P, &Field, Price](int32 D)
			{
				if (!Pay(this, Price)) return;
				int32 Best = 0;
				float BestD = 1e9f;
				for (int32 i = 0; i < FGTAData::NumClothColors(); ++i)
				{
					const float Dist = FVector::Dist(FVector(FGTAData::ClothColor(i)), FVector(Field));
					if (Dist < BestD) { BestD = Dist; Best = i; }
				}
				Field = FGTAData::ClothColor((Best + D + FGTAData::NumClothColors()) % FGTAData::NumClothColors());
				P->ApplyAppearance();
				P->SaveToProfile();
			};
		};
		if (bBarber)
		{
			Menu.Items.Add(ShopAdjust(TEXT("Hair style"), GHair[FMath::Clamp(A.HairStyle, 0, 5)], Cycle(A.HairStyle, 6, 60), TEXT("$60")));
			Menu.Items.Add(ShopAdjust(TEXT("Hair color"), TEXT("<  >"), Color(A.Hair, 40), TEXT("$40")));
			Menu.Items.Add(ShopAdjust(TEXT("Beard"), A.Beard ? TEXT("Full") : TEXT("None"), Cycle(A.Beard, 2, 40), TEXT("$40")));
			return;
		}
		Menu.Items.Add(ShopAdjust(TEXT("Outfit"), GBody[FMath::Clamp(A.Body, 0, 3)], Cycle(A.Body, 4, 200), TEXT("$200")));
		Menu.Items.Add(ShopAdjust(TEXT("Shirt / top color"), TEXT("<  >"), Color(A.Shirt, 50), TEXT("$50")));
		Menu.Items.Add(ShopAdjust(TEXT("Jacket color"), TEXT("<  >"), Color(A.Jacket, 80), TEXT("$80")));
		Menu.Items.Add(ShopAdjust(TEXT("Pants color"), TEXT("<  >"), Color(A.Pants, 50), TEXT("$50")));
		Menu.Items.Add(ShopAdjust(TEXT("Shoes color"), TEXT("<  >"), Color(A.Shoes, 40), TEXT("$40")));
		Menu.Items.Add(ShopAdjust(TEXT("Hat"), GHat[FMath::Clamp(A.Hat, 0, 4)], Cycle(A.Hat, 5, 60), TEXT("$60")));
		Menu.Items.Add(ShopAdjust(TEXT("Glasses"), GGlasses[FMath::Clamp(A.Glasses, 0, 2)], Cycle(A.Glasses, 3, 70), TEXT("$70")));
	};
	OpenMenu(M);
}

// ------------------------------------------------------------------------------------------------ vehicle mod shop

void AGTAPlayerController::OpenModShop()
{
	FGTAMenu M;
	M.Title = TEXT("RIPTIDE CUSTOMS");
	M.Rebuild = [this](FGTAMenu& Menu)
	{
		AGTAVehicle* V = CurrentVehicle();
		AGTAGameMode* GM = GTA::Mode(this);
		UGTAGameInstance* GI = GTA::Instance(this);
		if (!V || !GM || !GI) return;
		FGTAVehicleMods& Md = V->Mods;
		Menu.Subtitle = FString::Printf(TEXT("%s · Cash $%d%s"), *V->GetDef().Name, GTA::Money(this), GI->bAllModsUnlocked ? TEXT(" · ALL UNLOCKED") : TEXT(""));
		auto Set = [this, V](int32& Field, int32 Count, int32 PricePerLevel)
		{
			return [this, V, &Field, Count, PricePerLevel](int32 D)
			{
				const int32 NewV = FMath::Clamp(Field + D, 0, Count - 1);
				if (NewV == Field) return;
				if (NewV > Field && !Pay(this, PricePerLevel * FMath::Max(1, NewV))) return;
				Field = NewV;
				V->ApplyMods();
				GTA::Play2D(this, TEXT("S_Wrench"), 0.6f);
			};
		};
		auto Paint = [this, V](FLinearColor& Field)
		{
			return [this, V, &Field](int32 D)
			{
				if (!Pay(this, 300)) return;
				int32 Best = 0;
				float BestD = 1e9f;
				for (int32 i = 0; i < FGTAData::NumPaintColors(); ++i)
				{
					const float Dist = FVector::Dist(FVector(FGTAData::PaintColor(i)), FVector(Field));
					if (Dist < BestD) { BestD = Dist; Best = i; }
				}
				Field = FGTAData::PaintColor((Best + D + FGTAData::NumPaintColors()) % FGTAData::NumPaintColors());
				V->ApplyMods();
				// a fresh respray helps lose the police while they have lost sight of you
				AGTAGameMode* G = GTA::Mode(this);
				if (G && G->WantedLevel > 0 && !G->IsPursuit()) { G->ClearWanted(); GTA::Notify(this, TEXT("New paint — the police lost your description."), 3.f); }
			};
		};
		auto PaintName = [](const FLinearColor& C)
		{
			int32 Best = 0;
			float BestD = 1e9f;
			for (int32 i = 0; i < FGTAData::NumPaintColors(); ++i)
			{
				const float Dist = FVector::Dist(FVector(FGTAData::PaintColor(i)), FVector(C));
				if (Dist < BestD) { BestD = Dist; Best = i; }
			}
			return FGTAData::PaintName(Best);
		};
		const int32 RepairCost = FMath::Max(0, FMath::RoundToInt((V->GetDef().Health - V->Health) * 0.6f));
		Menu.Items.Add(ShopItem(TEXT("Repair"), RepairCost > 0 ? FString::Printf(TEXT("$%d"), RepairCost) : TEXT("OK"), [this, V, RepairCost]()
		{
			if (RepairCost > 0 && Pay(this, RepairCost)) { V->Repair(); GTA::Notify(this, TEXT("Repaired"), 2.f); }
		}));
		Menu.Items.Add(ShopAdjust(TEXT("Primary color"), PaintName(Md.Primary), Paint(Md.Primary), TEXT("$300 · clears an unseen wanted level")));
		Menu.Items.Add(ShopAdjust(TEXT("Secondary color"), PaintName(Md.Secondary), Paint(Md.Secondary), TEXT("$300")));
		Menu.Items.Add(ShopAdjust(TEXT("Paint finish"), GFinish[FMath::Clamp(Md.Finish, 0, 3)], [this, V, &Md](int32 D) { if (Pay(this, 500)) { Md.Finish = (Md.Finish + D + 4) % 4; V->ApplyMods(); } }, TEXT("$500")));
		Menu.Items.Add(ShopAdjust(TEXT("Rims"), Md.Rims == 0 ? TEXT("Stock") : FString::Printf(TEXT("Style %d"), Md.Rims), [this, V, &Md](int32 D) { if (Pay(this, 400)) { Md.Rims = (Md.Rims + D + 5) % 5; V->ApplyMods(); } }, TEXT("$400")));
		Menu.Items.Add(ShopAdjust(TEXT("Rim color"), PaintName(Md.RimColor), Paint(Md.RimColor), TEXT("$300")));
		Menu.Items.Add(ShopAdjust(TEXT("Window tint"), GTint[FMath::Clamp(Md.WindowTint, 0, 3)], Set(Md.WindowTint, 4, 200), TEXT("$200")));
		Menu.Items.Add(ShopAdjust(TEXT("Livery"), GLivery[FMath::Clamp(Md.Livery, 0, 2)], [this, V, &Md](int32 D) { if (Pay(this, 350)) { Md.Livery = (Md.Livery + D + 3) % 3; V->ApplyMods(); } }, TEXT("$350")));
		if (!V->IsTwoWheeler() && !V->IsAircraft() && !V->IsBoat())
		{
			Menu.Items.Add(ShopAdjust(TEXT("Spoiler"), Md.Spoiler == 0 ? TEXT("None") : FString::Printf(TEXT("Style %d"), Md.Spoiler), Set(Md.Spoiler, 4, 600), TEXT("$600/level · adds downforce")));
			Menu.Items.Add(ShopAdjust(TEXT("Front bumper"), Md.Bumper == 0 ? TEXT("Stock") : FString::Printf(TEXT("Style %d"), Md.Bumper), Set(Md.Bumper, 3, 500), TEXT("$500")));
			Menu.Items.Add(ShopAdjust(TEXT("Hood scoop"), Md.Hood == 0 ? TEXT("Stock") : FString::Printf(TEXT("Style %d"), Md.Hood), Set(Md.Hood, 3, 450), TEXT("$450")));
			Menu.Items.Add(ShopAdjust(TEXT("Exhaust"), Md.Exhaust == 0 ? TEXT("Stock") : FString::Printf(TEXT("Style %d"), Md.Exhaust), Set(Md.Exhaust, 3, 350), TEXT("$350")));
			Menu.Items.Add(ShopAdjust(TEXT("Side skirts"), Md.Skirts ? TEXT("Installed") : TEXT("None"), Set(Md.Skirts, 2, 400), TEXT("$400")));
			Menu.Items.Add(ShopAdjust(TEXT("Roof"), GRoof[FMath::Clamp(Md.Roof, 0, 2)], Set(Md.Roof, V->GetDef().bConvertible ? 3 : 2, 300), TEXT("$300")));
		}
		Menu.Items.Add(ShopAdjust(TEXT("Engine"), GLevel[FMath::Clamp(Md.Engine, 0, 4)], Set(Md.Engine, 4, 2000), TEXT("$2000/level · acceleration & top speed")));
		Menu.Items.Add(ShopAdjust(TEXT("Brakes"), GLevel[FMath::Clamp(Md.Brakes, 0, 4)], Set(Md.Brakes, 4, 1000), TEXT("$1000/level")));
		Menu.Items.Add(ShopAdjust(TEXT("Suspension"), GLevel[FMath::Clamp(Md.Suspension, 0, 4)], Set(Md.Suspension, 4, 900), TEXT("$900/level · lower & stiffer")));
		Menu.Items.Add(ShopAdjust(TEXT("Transmission"), GLevel[FMath::Clamp(Md.Transmission, 0, 4)], Set(Md.Transmission, 4, 1200), TEXT("$1200/level")));
		Menu.Items.Add(ShopItem(TEXT("Turbo"), Md.bTurbo ? TEXT("Installed") : TEXT("$5000"), [this, V, &Md]() { if (!Md.bTurbo && Pay(this, 5000)) { Md.bTurbo = true; V->ApplyMods(); } }));
		Menu.Items.Add(ShopAdjust(TEXT("Armor"), GLevel[FMath::Clamp(Md.Armor, 0, 4)], Set(Md.Armor, 5, 2500), TEXT("$2500/level · damage resistance")));
		Menu.Items.Add(ShopItem(TEXT("Bulletproof tires"), Md.bBulletproofTires ? TEXT("Installed") : TEXT("$3000"), [this, V, &Md]() { if (!Md.bBulletproofTires && Pay(this, 3000)) { Md.bBulletproofTires = true; V->ApplyMods(); } }));
		Menu.Items.Add(ShopAdjust(TEXT("Horn"), FString::Printf(TEXT("Horn %d"), Md.Horn + 1), [this, V, &Md](int32 D) { if (Pay(this, 100)) { Md.Horn = (Md.Horn + D + 4) % 4; V->ApplyMods(); V->SetHorn(true); FTimerHandle H; GetWorldTimerManager().SetTimer(H, FTimerDelegate::CreateWeakLambda(V, [V]() { V->SetHorn(false); }), 0.5f, false); } }, TEXT("$100")));
		Menu.Items.Add(ShopAdjust(TEXT("Headlight color"), GLights[FMath::Clamp(Md.LightColor, 0, 2)], [this, V, &Md](int32 D) { if (Pay(this, 200)) { Md.LightColor = (Md.LightColor + D + 3) % 3; V->ApplyMods(); } }, TEXT("$200")));
		Menu.Items.Add(ShopAdjust(TEXT("License plate"), FString::Printf(TEXT("Style %d"), Md.Plate + 1), [this, V, &Md](int32 D) { if (Pay(this, 100)) { Md.Plate = (Md.Plate + D + 3) % 3; V->ApplyMods(); } }, TEXT("$100")));
	};
	OpenMenu(M);
}

// ------------------------------------------------------------------------------------------------ garages

void AGTAPlayerController::OpenGarage(int32 Index)
{
	FGTAMenu M;
	M.Title = TEXT("GARAGE");
	M.Rebuild = [this, Index](FGTAMenu& Menu)
	{
		UGTAGameInstance* GI = GTA::Instance(this);
		AGTAGameMode* GM = GTA::Mode(this);
		if (!GI || !GM || !GM->City) return;
		const FGTAPOIData* P = GM->City->FindPOI(EGTAPOI::Garage, Index);
		if (!P) return;
		Menu.Title = P->Name.ToUpper();
		Menu.Subtitle = FString::Printf(TEXT("Cash $%d · stored %d / 4"), GTA::Money(this), GI->Profile.Garage.FilterByPredicate([Index](const FGTAStoredVehicle& S) { return S.Garage == Index; }).Num());
		AGTAVehicle* V = CurrentVehicle();
		if (V && !V->IsAircraft() && !V->IsBoat())
		{
			Menu.Items.Add(ShopItem(FString::Printf(TEXT("Store %s"), *V->GetDef().Name), TEXT(""), [this, V, Index, GI]()
			{
				int32 Count = 0;
				for (const FGTAStoredVehicle& S : GI->Profile.Garage) if (S.Garage == Index) Count++;
				if (Count >= 4) { GTA::Notify(this, TEXT("Garage full"), 2.f); return; }
				FGTAStoredVehicle S;
				S.Id = V->VehicleId;
				S.Mods = V->Mods;
				S.Garage = Index;
				GI->Profile.Garage.Add(S);
				ExitVehicle(true);
				V->Destroy();
				GTA::Notify(this, TEXT("Vehicle stored"), 2.f);
				CloseAllMenus();
			}));
		}
		for (int32 i = 0; i < GI->Profile.Garage.Num(); ++i)
		{
			const FGTAStoredVehicle S = GI->Profile.Garage[i];
			if (S.Garage != Index) continue;
			const FTransform Spawn(P->T.Rotator() + FRotator(0.f, 180.f, 0.f), P->T.GetLocation() - P->T.GetRotation().GetForwardVector() * 700.f + FVector(0, 0, 40.f));
			Menu.Items.Add(ShopItem(FString::Printf(TEXT("Take out %s"), *FGTAData::Vehicle(S.Id).Name), TEXT(""), [this, i, S, Spawn, GI]()
			{
				if (PlayerChar->IsInVehicle()) ExitVehicle(true);
				if (AGTAVehicle* NV = AGTAVehicle::SpawnVehicle(GetWorld(), S.Id, Spawn, &S.Mods))
				{
					NV->bPlayerOwned = true;
					GI->Profile.Garage.RemoveAt(i);
					CloseAllMenus();
					EnterVehicle(NV, 0);
				}
			}));
		}
		// dealership
		for (const FGTAVehicleDef& D : FGTAData::Vehicles())
		{
			if (D.bPolice || D.bEmergency || D.Kind == EGTAVehicleKind::Boat || D.Kind == EGTAVehicleKind::Helicopter || D.Kind == EGTAVehicleKind::Plane || D.Id == EGTAVehicle::Tactical) continue;
			const EGTAVehicle Id = D.Id;
			Menu.Items.Add(ShopItem(FString::Printf(TEXT("Buy %s"), *D.Name), FString::Printf(TEXT("$%d"), D.Price), [this, Id, Index, GI, D]()
			{
				int32 Count = 0;
				for (const FGTAStoredVehicle& S : GI->Profile.Garage) if (S.Garage == Index) Count++;
				if (Count >= 4) { GTA::Notify(this, TEXT("Garage full"), 2.f); return; }
				if (!GTA::SpendMoney(this, D.Price)) return;
				FGTAStoredVehicle S;
				S.Id = Id;
				S.Mods.Primary = D.DefaultPaint;
				S.Garage = Index;
				GI->Profile.Garage.Add(S);
				GTA::Notify(this, D.Name + TEXT(" delivered to your garage"), 3.f);
			}));
		}
	};
	OpenMenu(M);
}

// ------------------------------------------------------------------------------------------------ safehouses

void AGTAPlayerController::OpenSafehouse(int32 Index)
{
	FGTAMenu M;
	M.Title = TEXT("SAFEHOUSE");
	M.Rebuild = [this, Index](FGTAMenu& Menu)
	{
		UGTAGameInstance* GI = GTA::Instance(this);
		AGTAGameMode* GM = GTA::Mode(this);
		if (!GI || !GM || !GM->City) return;
		const FGTAPOIData* P = GM->City->FindPOI(EGTAPOI::Safehouse, Index);
		Menu.Title = P ? P->Name.ToUpper() : TEXT("SAFEHOUSE");
		const bool bOwned = Index == 0 || GI->Profile.OwnedSafehouses.Contains(Index);
		const int32 Price = Index == 1 ? 85000 : 120000;
		if (!bOwned)
		{
			Menu.Items.Add(ShopItem(TEXT("Buy property"), FString::Printf(TEXT("$%d"), Price), [this, GI, Index, Price]()
			{
				if (GTA::SpendMoney(this, Price)) { GI->Profile.OwnedSafehouses.AddUnique(Index); GTA::Notify(this, TEXT("Property purchased!"), 3.f); }
			}, TEXT("Unlocks saving, sleeping and the wardrobe here")));
			return;
		}
		Menu.Items.Add(ShopItem(TEXT("Save game"), TEXT(""), [this, GI, Index]()
		{
			GI->Profile.LastSafehouse = Index;
			PlayerChar->SaveToProfile();
			GTA::Notify(this, GI->SaveProfile() ? TEXT("Game saved") : TEXT("Save failed"), 2.f);
		}));
		Menu.Items.Add(ShopItem(TEXT("Sleep 6 hours (save)"), TEXT(""), [this, GI, GM, Index]()
		{
			if (GM->WantedLevel > 0) { GTA::Notify(this, TEXT("You can't sleep while wanted."), 2.f); return; }
			if (GM->Env) GM->Env->SetTimeOfDay(GM->Env->TimeOfDay + 6.f);
			PlayerChar->Health = PlayerChar->MaxHealth;
			GI->Profile.LastSafehouse = Index;
			PlayerChar->SaveToProfile();
			GI->SaveProfile();
			GTA::Notify(this, TEXT("Rested. Game saved."), 3.f);
			CloseAllMenus();
		}));
		Menu.Items.Add(ShopItem(TEXT("Wardrobe"), TEXT("free"), [this, GI]()
		{
			const bool bWas = GI->bAllModsUnlocked;
			GI->bAllModsUnlocked = true;   // wardrobe changes are free at home
			OpenClothesShop(false);
			GI->bAllModsUnlocked = bWas;
		}));
	};
	OpenMenu(M);
}

// ------------------------------------------------------------------------------------------------ stunt jumps

void AGTAPlayerController::TickStuntJump(float Dt)
{
	AGTAVehicle* V = CurrentVehicle();
	AGTAGameMode* GM = GTA::Mode(this);
	if (!V || !GM || !GM->City || V->IsAircraft() || V->IsBoat()) { StuntJumpActive = -1; return; }
	const float Now = GetWorld()->GetTimeSeconds();
	if (StuntJumpActive < 0)
	{
		for (const FGTAPOIData& P : GM->City->POIs)
		{
			if (P.Type != EGTAPOI::StuntJump) continue;
			if (FVector::Dist2D(P.T.GetLocation(), V->GetActorLocation()) > 450.f) continue;
			if (V->SpeedKmh() < 55.f) continue;
			if (FVector::DotProduct(V->GetActorForwardVector(), P.T.GetRotation().GetForwardVector()) < 0.7f) continue;
			StuntJumpActive = P.Index;
			StuntStartTime = Now;
			StuntStart = V->GetActorLocation();
			break;
		}
		return;
	}
	const float T = Now - StuntStartTime;
	if (!V->IsGrounded() && T > 0.25f) GetWorldSettings()->SetTimeDilation(0.45f);
	if (V->IsGrounded() && T > 0.6f)
	{
		GetWorldSettings()->SetTimeDilation(1.f);
		const float Dist = FVector::Dist2D(StuntStart, V->GetActorLocation()) / 100.f;
		if (Dist > 22.f && !V->IsUpsideDown())
		{
			UGTAGameInstance* GI = GTA::Instance(this);
			const int32 Bit = 1 << StuntJumpActive;
			const bool bNew = GI && !(GI->Profile.StuntJumpsDone & Bit);
			if (GI) GI->Profile.StuntJumpsDone |= Bit;
			GTA::AddMoney(this, bNew ? 1000 : 200);
			GM->ShowBigMessage(TEXT("STUNT JUMP COMPLETED"), 2.5f);
			GTA::Notify(this, FString::Printf(TEXT("Distance %.0f m · +$%d"), Dist, bNew ? 1000 : 200), 3.f);
		}
		else GTA::Notify(this, TEXT("Stunt jump failed"), 2.f);
		StuntJumpActive = -1;
	}
	if (T > 8.f) { StuntJumpActive = -1; GetWorldSettings()->SetTimeDilation(1.f); }
}

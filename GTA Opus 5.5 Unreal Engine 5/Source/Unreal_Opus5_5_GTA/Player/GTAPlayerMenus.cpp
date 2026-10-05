// Menu stack + admin/benchmark menu, pause menu and phone.
#include "Player/GTAPlayerController.h"
#include "Player/GTAPlayerCharacter.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Core/GTAGameInstance.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "World/GTAEnvironment.h"
#include "World/GTAPopulation.h"
#include "AI/GTANPCController.h"
#include "GameFramework/WorldSettings.h"
#include "Kismet/GameplayStatics.h"
#include "Kismet/KismetSystemLibrary.h"
#include "InputActionValue.h"

// ------------------------------------------------------------------------------------------------ menu stack

void AGTAPlayerController::OpenMenu(const FGTAMenu& M)
{
	MenuStack.Add(M);
	RefreshMenu();
	if (M.bPauseGame) UGameplayStatics::SetGamePaused(this, true);
	GTA::Play2D(this, TEXT("S_UI_Open"), 0.5f);
	if (PlayerChar) PlayerChar->SetTriggerHeld(false);
}

void AGTAPlayerController::CloseMenu()
{
	if (MenuStack.Num() == 0) return;
	MenuStack.Pop();
	if (MenuStack.Num() == 0 || !MenuStack.Last().bPauseGame) UGameplayStatics::SetGamePaused(this, false);
	RefreshMenu();
	GTA::Play2D(this, TEXT("S_UI_Back"), 0.5f);
}

void AGTAPlayerController::CloseAllMenus()
{
	MenuStack.Reset();
	UGameplayStatics::SetGamePaused(this, false);
}

void AGTAPlayerController::RefreshMenu()
{
	if (MenuStack.Num() == 0) return;
	FGTAMenu& M = MenuStack.Last();
	if (M.Rebuild)
	{
		const int32 Sel = M.Selected;
		M.Items.Reset();
		M.Rebuild(M);
		M.Selected = FMath::Clamp(Sel, 0, FMath::Max(0, M.Items.Num() - 1));
	}
}

void AGTAPlayerController::OnMenuUp(const FInputActionValue& V)
{
	if (!IsMenuOpen()) { if (!bMapOpen) OpenPhone(); return; }
	FGTAMenu& M = MenuStack.Last();
	if (M.Items.Num() == 0) return;
	M.Selected = (M.Selected - 1 + M.Items.Num()) % M.Items.Num();
	GTA::Play2D(this, TEXT("S_UI_Tick"), 0.35f);
}

void AGTAPlayerController::OnMenuDown(const FInputActionValue& V)
{
	if (!IsMenuOpen()) return;
	FGTAMenu& M = MenuStack.Last();
	if (M.Items.Num() == 0) return;
	M.Selected = (M.Selected + 1) % M.Items.Num();
	GTA::Play2D(this, TEXT("S_UI_Tick"), 0.35f);
}

void AGTAPlayerController::OnMenuLeft(const FInputActionValue& V)
{
	if (!IsMenuOpen()) return;
	FGTAMenu& M = MenuStack.Last();
	if (!M.Items.IsValidIndex(M.Selected)) return;
	if (M.Items[M.Selected].OnAdjust) { TFunction<void(int32)> F = M.Items[M.Selected].OnAdjust; F(-1); RefreshMenu(); GTA::Play2D(this, TEXT("S_UI_Tick"), 0.35f); }
}

void AGTAPlayerController::OnMenuRight(const FInputActionValue& V)
{
	if (!IsMenuOpen()) return;
	FGTAMenu& M = MenuStack.Last();
	if (!M.Items.IsValidIndex(M.Selected)) return;
	if (M.Items[M.Selected].OnAdjust) { TFunction<void(int32)> F = M.Items[M.Selected].OnAdjust; F(1); RefreshMenu(); GTA::Play2D(this, TEXT("S_UI_Tick"), 0.35f); }
}

void AGTAPlayerController::OnMenuAccept(const FInputActionValue& V)
{
	if (!IsMenuOpen()) { Interact(); return; }
	const int32 Depth = MenuStack.Num();
	FGTAMenu& M = MenuStack.Last();
	if (!M.Items.IsValidIndex(M.Selected)) return;
	const FGTAMenuItem& It = M.Items[M.Selected];
	if (!It.bEnabled) { GTA::Play2D(this, TEXT("S_UI_Error"), 0.5f); return; }
	TFunction<void()> F = It.OnSelect;
	if (F)
	{
		GTA::Play2D(this, TEXT("S_UI_Select"), 0.5f);
		F();
		if (MenuStack.Num() == Depth) RefreshMenu();
	}
	else if (It.OnAdjust) { TFunction<void(int32)> A = It.OnAdjust; A(1); RefreshMenu(); }
}

void AGTAPlayerController::OnMenuBack(const FInputActionValue& V)
{
	if (IsMenuOpen()) CloseMenu();
}

// ------------------------------------------------------------------------------------------------ helpers

namespace
{
	FGTAMenuItem Item(const FString& Label, TFunction<void()> F, const FString& Value = FString(), const FString& Hint = FString())
	{
		FGTAMenuItem I;
		I.Label = Label;
		I.OnSelect = MoveTemp(F);
		I.Value = Value;
		I.Hint = Hint;
		return I;
	}
	FGTAMenuItem Adjust(const FString& Label, const FString& Value, TFunction<void(int32)> F, const FString& Hint = FString())
	{
		FGTAMenuItem I;
		I.Label = Label;
		I.Value = Value;
		I.OnAdjust = MoveTemp(F);
		I.Hint = Hint;
		return I;
	}
	FString OnOff(bool b) { return b ? TEXT("ON") : TEXT("OFF"); }
}

static AGTAVehicle* GTASpawnVehicleForPlayer(AGTAPlayerController* PC, EGTAVehicle Id)
{
	AGTAPlayerCharacter* P = PC->PlayerChar;
	AGTAGameMode* M = GTA::Mode(PC);
	if (!P || !M || !M->City) return nullptr;
	if (P->IsInVehicle()) PC->ExitVehicle(true);
	const FGTAVehicleDef& D = FGTAData::Vehicle(Id);
	FTransform T(FRotator(0.f, P->GetActorRotation().Yaw, 0.f), P->GetActorLocation() + P->GetActorForwardVector() * (D.Length * 50.f + 250.f));
	if (D.Kind == EGTAVehicleKind::Boat)
	{
		const FTransform* Best = nullptr;
		for (const FTransform& B : M->City->BoatSpots) if (!Best || FVector::Dist2D(B.GetLocation(), P->GetActorLocation()) < FVector::Dist2D(Best->GetLocation(), P->GetActorLocation())) Best = &B;
		if (!GTA::IsOverSea(T.GetLocation()) && Best) T = FTransform(Best->Rotator(), Best->GetLocation() + FVector(0, 600.f, 0.f));
	}
	else if (D.Kind == EGTAVehicleKind::Plane)
	{
		T = FTransform(FRotator(0.f, 0.f, 0.f), FVector(-13500.f, 24000.f, 60.f));   // runway threshold, facing north
	}
	else if (D.Kind == EGTAVehicleKind::Helicopter)
	{
		FHitResult H;
		FCollisionQueryParams Q(SCENE_QUERY_STAT(GTAHeliSpace), false, P);
		if (P->GetWorld()->SweepSingleByChannel(H, T.GetLocation() + FVector(0, 0, 600.f), T.GetLocation() + FVector(0, 0, 601.f), FQuat::Identity, ECC_WorldStatic, FCollisionShape::MakeSphere(700.f), Q))
		{
			T = FTransform(FRotator::ZeroRotator, FVector(12000.f, 28500.f, 60.f));   // helipad
		}
	}
	FGTAVehicleMods Mods;
	Mods.Primary = D.DefaultPaint;
	AGTAVehicle* V = AGTAVehicle::SpawnVehicle(P->GetWorld(), Id, T, &Mods);
	if (V)
	{
		V->bPlayerOwned = true;
		PC->EnterVehicle(V, 0);
	}
	return V;
}

// ------------------------------------------------------------------------------------------------ admin / benchmark menu

void AGTAPlayerController::OpenAdminMenu()
{
	FGTAMenu M;
	M.Title = TEXT("PORT HALCYON — TEST MENU");
	M.Subtitle = TEXT("F1 close · Enter select · ←/→ adjust · Backspace back");
	M.Rebuild = [this](FGTAMenu& Menu)
	{
		UGTAGameInstance* GI = GTA::Instance(this);
		AGTAGameMode* GM = GTA::Mode(this);
		AGTAPlayerCharacter* P = PlayerChar;
		if (!GI || !GM || !P) return;
		Menu.Items.Add(Item(TEXT("Teleport…"), [this, GM]()
		{
			FGTAMenu T;
			T.Title = TEXT("TELEPORT");
			if (GM->City)
			{
				for (const TPair<FString, FVector>& Tp : GM->City->Teleports)
				{
					const FVector L = Tp.Value;
					T.Items.Add(Item(Tp.Key, [this, L]()
					{
						if (PlayerChar->IsInVehicle()) ExitVehicle(true);
						PlayerChar->TeleportTo(L, PlayerChar->GetActorRotation(), false, true);
						CloseAllMenus();
					}));
				}
			}
			OpenMenu(T);
		}, FString(), TEXT("Jump to key districts and landmarks")));
		Menu.Items.Add(Item(TEXT("Spawn vehicle…"), [this]()
		{
			FGTAMenu T;
			T.Title = TEXT("SPAWN VEHICLE");
			for (const FGTAVehicleDef& D : FGTAData::Vehicles())
			{
				const EGTAVehicle Id = D.Id;
				const bool bMesh = FGTAAssets::GenMesh(TEXT("Vehicles"), TEXT("SM_Veh_") + D.Key) != nullptr;
				FGTAMenuItem I = Item(D.Name, [this, Id]() { GTASpawnVehicleForPlayer(this, Id); CloseAllMenus(); }, bMesh ? TEXT("") : TEXT("(no mesh)"));
				T.Items.Add(I);
			}
			OpenMenu(T);
		}, FString(), TEXT("Cars, bikes, boats, helicopters and planes")));
		Menu.Items.Add(Item(TEXT("Spawn helicopter"), [this]() { GTASpawnVehicleForPlayer(this, EGTAVehicle::Helicopter); CloseAllMenus(); }));
		Menu.Items.Add(Item(TEXT("Spawn airplane (runway)"), [this]() { GTASpawnVehicleForPlayer(this, EGTAVehicle::PropPlane); CloseAllMenus(); }));
		Menu.Items.Add(Item(TEXT("Spawn boat (marina)"), [this]() { GTASpawnVehicleForPlayer(this, EGTAVehicle::Speedboat); CloseAllMenus(); }));
		Menu.Items.Add(Item(TEXT("Weapons…"), [this]()
		{
			FGTAMenu T;
			T.Title = TEXT("GIVE WEAPON");
			T.Items.Add(Item(TEXT("Give ALL weapons"), [this]()
			{
				for (int32 i = 1; i < (int32)EGTAWeapon::MAX; ++i) PlayerChar->GiveWeapon((EGTAWeapon)i, 9999, false);
				PlayerChar->RefillAllAmmo();
				GTA::Notify(this, TEXT("All weapons given"), 2.f);
			}));
			T.Items.Add(Item(TEXT("Refill ammo"), [this]() { PlayerChar->RefillAllAmmo(); GTA::Notify(this, TEXT("Ammo refilled"), 2.f); }));
			for (int32 i = 1; i < (int32)EGTAWeapon::MAX; ++i)
			{
				const EGTAWeapon W = (EGTAWeapon)i;
				T.Items.Add(Item(FGTAData::Weapon(W).Name, [this, W]() { PlayerChar->GiveWeapon(W, 9999, true); PlayerChar->RefillAllAmmo(); }));
			}
			OpenMenu(T);
		}));
		Menu.Items.Add(Adjust(TEXT("Money"), FString::Printf(TEXT("$%d"), GI->Profile.Money), [GI](int32 D) { GI->Profile.Money = FMath::Max(0, GI->Profile.Money + D * 10000); }, TEXT("←/→ ±$10,000")));
		Menu.Items.Add(Item(TEXT("Set money $1,000,000"), [GI]() { GI->Profile.Money = 1000000; }));
		Menu.Items.Add(Adjust(TEXT("Health"), FString::Printf(TEXT("%d"), FMath::RoundToInt(P->Health)), [P](int32 D) { P->Health = FMath::Clamp(P->Health + D * 25.f, 1.f, P->MaxHealth); }, TEXT("Enter = full health")));
		Menu.Items.Last().OnSelect = [P]() { P->Health = P->MaxHealth; };
		Menu.Items.Add(Adjust(TEXT("Armor"), FString::Printf(TEXT("%d"), FMath::RoundToInt(P->Armor)), [P](int32 D) { P->Armor = FMath::Clamp(P->Armor + D * 25.f, 0.f, 100.f); }));
		Menu.Items.Last().OnSelect = [P]() { P->Armor = 100.f; };
		Menu.Items.Add(Adjust(TEXT("Wanted level"), FString::Printf(TEXT("%d"), GM->WantedLevel), [GM](int32 D) { GM->SetWantedLevel(FMath::Clamp(GM->WantedLevel + D, 0, 5), true); }, TEXT("←/→ set 0–5")));
		Menu.Items.Add(Item(TEXT("Clear wanted level"), [GM]() { GM->ClearWanted(); }));
		Menu.Items.Add(Item(TEXT("Spawn police unit"), [this, GM, P]()
		{
			if (GM->Population) GM->Population->SpawnPoliceUnit(P->GetActorLocation(), false);
			GTA::Notify(this, TEXT("Police unit dispatched"), 2.f);
		}));
		Menu.Items.Add(Adjust(TEXT("Time of day"), GM->Env ? GM->Env->TimeString() : TEXT("-"), [GM](int32 D) { if (GM->Env) GM->Env->SetTimeOfDay(GM->Env->TimeOfDay + D); }, TEXT("←/→ ±1 hour, Enter toggles freeze")));
		Menu.Items.Last().OnSelect = [GM]() { if (GM->Env) GM->Env->bTimeFrozen = !GM->Env->bTimeFrozen; };
		Menu.Items.Add(Adjust(TEXT("Weather"), GM->Env ? FGTAData::WeatherName(GM->Env->Weather) : TEXT("-"), [GM](int32 D)
		{
			if (!GM->Env) return;
			const int32 N = (int32)EGTAWeather::MAX;
			GM->Env->bAutoWeather = false;
			GM->Env->SetWeather((EGTAWeather)(((int32)GM->Env->Weather + D + N) % N), true);
		}, TEXT("←/→ cycle (disables automatic weather)")));
		Menu.Items.Add(Item(TEXT("Repair current vehicle"), [this]()
		{
			AGTAVehicle* V = LastVehicle ? LastVehicle : CurrentVehicle();
			if (V) { V->Repair(); GTA::Notify(this, TEXT("Vehicle repaired"), 2.f); }
		}, FString(), TEXT("Repairs the current / last used vehicle")));
		Menu.Items.Add(Item(TEXT("Open vehicle customization"), [this]()
		{
			if (!CurrentVehicle()) { GTA::Notify(this, TEXT("Get in a vehicle first"), 2.f); return; }
			OpenModShop();
		}));
		Menu.Items.Add(Item(TEXT("Unlock all modifications"), [GI]() { GI->bAllModsUnlocked = !GI->bAllModsUnlocked; }, OnOff(GI->bAllModsUnlocked)));
		Menu.Items.Add(Item(TEXT("Give parachute"), [P]() { P->SetHasParachute(true); }, OnOff(P->bHasParachute)));
		Menu.Items.Add(Item(TEXT("Toggle scuba / refill lungs"), [P]() { P->SetScuba(!P->bScuba); P->Breath = 1.f; }, OnOff(P->bScuba)));
		Menu.Items.Add(Item(TEXT("Max all skills"), [GI]() { GI->SetAllSkills(1.f); }));
		Menu.Items.Add(Item(TEXT("Reset all skills"), [GI]() { GI->SetAllSkills(0.f); }));
		Menu.Items.Add(Item(TEXT("Call taxi"), [this, GM, P]()
		{
			if (GM->Population) GM->Population->CallTaxi(P->GetActorLocation());
			CloseAllMenus();
		}));
		Menu.Items.Add(Item(TEXT("Wildlife"), [GI]() { GI->bWildlifeEnabled = !GI->bWildlifeEnabled; }, OnOff(GI->bWildlifeEnabled)));
		Menu.Items.Add(Item(TEXT("Invulnerability"), [GI]() { GI->bInvulnerable = !GI->bInvulnerable; }, OnOff(GI->bInvulnerable)));
		Menu.Items.Add(Item(TEXT("Traffic"), [GI, GM]() { GI->bTrafficEnabled = !GI->bTrafficEnabled; }, OnOff(GI->bTrafficEnabled)));
		Menu.Items.Add(Item(TEXT("Pedestrians"), [GI]() { GI->bPedsEnabled = !GI->bPedsEnabled; }, OnOff(GI->bPedsEnabled)));
		Menu.Items.Add(Item(TEXT("Show FPS"), [this, GI]() { bShowFPS = !bShowFPS; GI->bShowFPS = bShowFPS; }, OnOff(bShowFPS)));
		Menu.Items.Add(Item(TEXT("Show coordinates / sector"), [this, GI]() { bShowCoords = !bShowCoords; GI->bShowCoords = bShowCoords; }, OnOff(bShowCoords)));
		Menu.Items.Add(Item(TEXT("Clear population"), [GM]() { if (GM->Population) GM->Population->ClearAll(); }));
		Menu.Items.Add(Item(TEXT("Quick save"), [this, GI, P]() { P->SaveToProfile(); GTA::Notify(this, GI->SaveProfile() ? TEXT("Game saved") : TEXT("Save failed"), 2.f); }));
		Menu.Items.Add(Item(TEXT("Quick load"), [this, GI, P]() { if (GI->LoadProfile()) { P->LoadFromProfile(); GTA::Notify(this, TEXT("Game loaded"), 2.f); } else GTA::Notify(this, TEXT("No save found"), 2.f); }));
	};
	OpenMenu(M);
}

// ------------------------------------------------------------------------------------------------ pause menu

void AGTAPlayerController::OpenPauseMenu()
{
	FGTAMenu M;
	M.Title = TEXT("PAUSED");
	M.bPauseGame = true;
	M.Rebuild = [this](FGTAMenu& Menu)
	{
		UGTAGameInstance* GI = GTA::Instance(this);
		if (!GI) return;
		Menu.Items.Add(Item(TEXT("Resume"), [this]() { CloseAllMenus(); }));
		Menu.Items.Add(Adjust(TEXT("Mouse sensitivity"), FString::Printf(TEXT("%.2f"), GI->MouseSensitivity), [GI](int32 D) { GI->MouseSensitivity = FMath::Clamp(GI->MouseSensitivity + D * 0.1f, 0.2f, 3.f); }));
		Menu.Items.Add(Item(TEXT("Invert mouse Y"), [GI]() { GI->bInvertY = !GI->bInvertY; }, OnOff(GI->bInvertY)));
		Menu.Items.Add(Item(TEXT("Save game"), [this, GI]() { if (PlayerChar) PlayerChar->SaveToProfile(); GTA::Notify(this, GI->SaveProfile() ? TEXT("Game saved") : TEXT("Save failed"), 2.f); }));
		Menu.Items.Add(Item(TEXT("Load game"), [this, GI]() { if (GI->LoadProfile() && PlayerChar) { PlayerChar->LoadFromProfile(); CloseAllMenus(); } }, GI->HasSave() ? TEXT("") : TEXT("(no save)")));
		Menu.Items.Add(Item(TEXT("Controls"), [this]()
		{
			FGTAMenu C;
			C.Title = TEXT("CONTROLS");
			const TCHAR* Lines[][2] = {
				{ TEXT("WASD / Mouse"), TEXT("Move / camera") }, { TEXT("Shift"), TEXT("Sprint / boost / climb") }, { TEXT("Space"), TEXT("Jump, vault / handbrake") },
				{ TEXT("Ctrl / C"), TEXT("Stealth crouch / descend") }, { TEXT("F"), TEXT("Enter / exit / carjack, parachute") }, { TEXT("LMB / RMB"), TEXT("Fire / melee, aim") },
				{ TEXT("R"), TEXT("Reload / radio in vehicle") }, { TEXT("Q"), TEXT("Cover / yaw left in aircraft") }, { TEXT("E"), TEXT("Interact / siren / yaw right") },
				{ TEXT("Tab"), TEXT("Weapon wheel") }, { TEXT("1–9, wheel"), TEXT("Select weapon") }, { TEXT("X / B"), TEXT("Dodge / block") },
				{ TEXT("V"), TEXT("First-person toggle") }, { TEXT("H / L / T"), TEXT("Horn / lights / roof") }, { TEXT("M"), TEXT("Map (click: waypoint)") },
				{ TEXT("Up arrow"), TEXT("Phone") }, { TEXT("F1"), TEXT("Test menu") }, { TEXT("Esc"), TEXT("Pause") } };
			for (auto& L : Lines) C.Items.Add(Item(L[0], nullptr, L[1]));
			C.bPauseGame = true;
			OpenMenu(C);
		}));
		Menu.Items.Add(Item(TEXT("Quit to desktop"), [this]() { UKismetSystemLibrary::QuitGame(this, this, EQuitPreference::Quit, false); }));
	};
	OpenMenu(M);
}

// ------------------------------------------------------------------------------------------------ phone

void AGTAPlayerController::OpenPhone()
{
	FGTAMenu M;
	M.Title = TEXT("HALCYON PHONE");
	M.Rebuild = [this](FGTAMenu& Menu)
	{
		AGTAGameMode* GM = GTA::Mode(this);
		UGTAGameInstance* GI = GTA::Instance(this);
		if (!GM || !GI || !PlayerChar) return;
		Menu.Subtitle = GM->Env ? GM->Env->TimeString() + TEXT("  ·  ") + FGTAData::WeatherName(GM->Env->Weather) : FString();
		Menu.Items.Add(Item(TEXT("Call taxi"), [this, GM]() { if (GM->Population) GM->Population->CallTaxi(PlayerChar->GetActorLocation()); CloseAllMenus(); }, TEXT("$20+"), TEXT("A Neon Cab picks you up; set a waypoint with M")));
		Menu.Items.Add(Item(TEXT("Mechanic: deliver my vehicle"), [this, GI]()
		{
			if (GI->Profile.Garage.Num() == 0) { GTA::Notify(this, TEXT("No stored vehicles. Buy or store one at a garage."), 3.f); return; }
			if (!GTA::SpendMoney(this, 150)) return;
			const FGTAStoredVehicle SV = GI->Profile.Garage[0];
			GI->Profile.Garage.RemoveAt(0);
			const FVector L = PlayerChar->GetActorLocation() + PlayerChar->GetActorForwardVector() * 600.f;
			if (AGTAVehicle* V = AGTAVehicle::SpawnVehicle(GetWorld(), SV.Id, FTransform(PlayerChar->GetActorRotation(), L), &SV.Mods)) { V->bPlayerOwned = true; GTA::Notify(this, TEXT("Your vehicle has been delivered."), 3.f); }
			CloseAllMenus();
		}, TEXT("$150")));
		Menu.Items.Add(Item(TEXT("Emergency: request ambulance (heal)"), [this]()
		{
			if (GTA::SpendMoney(this, 300)) { PlayerChar->Health = PlayerChar->MaxHealth; GTA::Notify(this, TEXT("Paramedics patched you up."), 3.f); }
			CloseAllMenus();
		}, TEXT("$300")));
		Menu.Items.Add(Item(TEXT("Lawyer: reduce wanted level"), [this, GM]()
		{
			if (GM->WantedLevel == 0) { GTA::Notify(this, TEXT("You're not wanted."), 2.f); return; }
			if (GM->IsPursuit()) { GTA::Notify(this, TEXT("Can't talk now — the police can see you!"), 2.f); return; }
			if (GTA::SpendMoney(this, 2000 * GM->WantedLevel)) GM->SetWantedLevel(GM->WantedLevel - 1, false);
			CloseAllMenus();
		}, FString::Printf(TEXT("$%d"), 2000 * FMath::Max(1, GM->WantedLevel)), TEXT("Only while police have lost sight of you")));
		Menu.Items.Add(Item(TEXT("Skills"), [this, GI]()
		{
			FGTAMenu S;
			S.Title = TEXT("SKILLS");
			for (int32 i = 0; i < (int32)EGTASkill::MAX; ++i)
				S.Items.Add(Item(FGTAData::SkillName((EGTASkill)i), nullptr, FString::Printf(TEXT("%d%%"), FMath::RoundToInt(GI->GetSkill((EGTASkill)i) * 100.f))));
			OpenMenu(S);
		}));
		Menu.Items.Add(Item(TEXT("Stats"), [this, GI]()
		{
			FGTAMenu S;
			S.Title = TEXT("STATS");
			S.Items.Add(Item(TEXT("Kills"), nullptr, FString::FromInt(GI->Profile.Kills)));
			S.Items.Add(Item(TEXT("Deaths"), nullptr, FString::FromInt(GI->Profile.Deaths)));
			S.Items.Add(Item(TEXT("Busted"), nullptr, FString::FromInt(GI->Profile.Busted)));
			S.Items.Add(Item(TEXT("Stunt jumps"), nullptr, FString::Printf(TEXT("%d / 3"), (int32)FMath::CountBits((uint64)GI->Profile.StuntJumpsDone))));
			S.Items.Add(Item(TEXT("Range best score"), nullptr, FString::FromInt(GI->Profile.RangeBestScore)));
			OpenMenu(S);
		}));
		Menu.Items.Add(Item(TEXT("Quick save"), [this, GI]() { PlayerChar->SaveToProfile(); GTA::Notify(this, GI->SaveProfile() ? TEXT("Game saved") : TEXT("Save failed"), 2.f); }));
	};
	OpenMenu(M);
}

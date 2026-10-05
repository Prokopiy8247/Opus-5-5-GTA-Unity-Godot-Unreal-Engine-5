#include "Core/GTATestDirector.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameMode.h"
#include "Core/GTAGameInstance.h"
#include "Player/GTAPlayerCharacter.h"
#include "Player/GTAPlayerController.h"
#include "Vehicles/GTAVehicle.h"
#include "World/GTACity.h"
#include "World/GTAEnvironment.h"
#include "World/GTAPopulation.h"
#include "World/GTAFX.h"
#include "GameFramework/SpectatorPawn.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"
#include "UnrealClient.h"
#include "HAL/PlatformMisc.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Kismet/GameplayStatics.h"

namespace
{
	struct FGTATestStep { const TCHAR* Name; float Duration; };
	const FGTATestStep GSteps[] = {
		{ TEXT("spawn"), 7.f },
		{ TEXT("orbit"), 2.f },
		{ TEXT("walk"), 3.f },
		{ TEXT("jump"), 2.f },
		{ TEXT("drive"), 7.f },
		{ TEXT("exit"), 2.f },
		{ TEXT("shoot"), 4.f },
		{ TEXT("police"), 10.f },
		{ TEXT("night"), 3.f },
		{ TEXT("rain"), 4.f },
		{ TEXT("heli"), 7.f },
		{ TEXT("plane"), 8.f },
		{ TEXT("boat"), 6.f },
		{ TEXT("map"), 2.f },
		{ TEXT("menu"), 2.f },
		{ TEXT("wheel"), 2.f },
		{ TEXT("persistence"), 2.f },
		{ TEXT("swim"), 3.f },
		{ TEXT("services"), 2.f },
		{ TEXT("parachute"), 3.f },
		{ TEXT("escape"), 18.f },
		{ TEXT("done"), 1.f },
	};

	// Render bisection, run with -gtadiag. Each entry applies CVars then captures one frame.
	struct FGTADiagStep { const TCHAR* Name; const TCHAR* Cmds[6]; };
	const FGTADiagStep GDiagSteps[] = {
		{ TEXT("baseline"),      { nullptr } },
		{ TEXT("noclouds"),      { TEXT("r.VolumetricCloud 0"), nullptr } },
		{ TEXT("noatmosphere"),  { TEXT("r.SkyAtmosphere 0"), nullptr } },
		{ TEXT("novsm"),         { TEXT("r.Shadow.Virtual.Enable 0"), nullptr } },
		{ TEXT("nogi"),          { TEXT("r.Lumen.DiffuseIndirect.Allow 0"), TEXT("r.ReflectionMethod 0"), nullptr } },
		{ TEXT("noexposure"),    { TEXT("r.DefaultFeature.AutoExposure 0"), nullptr } },
		{ TEXT("nofog"),         { TEXT("r.Fog 0"), TEXT("r.VolumetricFog 0"), nullptr } },
		{ TEXT("unlit"),         { TEXT("viewmode unlit"), nullptr } },
		{ TEXT("lit"),           { TEXT("viewmode lit"), TEXT("r.SkyAtmosphere 1"), TEXT("r.Fog 1"), TEXT("r.VolumetricFog 1"), TEXT("r.VolumetricCloud 1"), TEXT("r.DefaultFeature.AutoExposure 1") } },
	};
}

AGTATestDirector::AGTATestDirector()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bTickEvenWhenPaused = true;
}

void AGTATestDirector::BeginPlay()
{
	Super::BeginPlay();
	FParse::Value(FCommandLine::Get(), TEXT("gtatestonly="), Only);
	bDebugCam = FParse::Param(FCommandLine::Get(), TEXT("gtadebugcam"));
	bLightLog = FParse::Param(FCommandLine::Get(), TEXT("gtalightlog"));
	bDiag = FParse::Param(FCommandLine::Get(), TEXT("gtadiag"));
	// Shader compilation on a cold run holds the scene black for a long time; the captures are
	// worthless until it finishes, so allow the caller to delay the first step.
	float Warmup = 3.f;
	FParse::Value(FCommandLine::Get(), TEXT("gtatestwarmup="), Warmup);
	if (bDiag) { DiagNext = GetWorld()->GetTimeSeconds() + FMath::Max(3.f, Warmup); }
	OutDir = FPaths::ConvertRelativePathToFull(FPaths::ProjectSavedDir() / TEXT("GTATest"));
	IFileManager::Get().MakeDirectory(*OutDir, true);
	WarmupEnd = GetWorld()->GetTimeSeconds() + FMath::Max(3.f, Warmup);
	NextStepTime = WarmupEnd;
	Mark(FString::Printf(TEXT("director ready (warmup %.0fs)"), FMath::Max(3.f, Warmup)));
}

void AGTATestDirector::DebugCam()
{
	// Fly a detached spectator above the district so a capture shows what the renderer produces
	// regardless of where the player pawn happens to be standing.
	APlayerController* PC = GetWorld()->GetFirstPlayerController();
	if (!PC) return;
	// -gtacamz=NNNN overrides the height; -gtacampitch=NN points it up at the sky.
	float CamZ = 12000.f, CamPitch = -60.f;
	FParse::Value(FCommandLine::Get(), TEXT("gtacamz="), CamZ);
	FParse::Value(FCommandLine::Get(), TEXT("gtacampitch="), CamPitch);
	const FVector Loc(StartLoc.X, StartLoc.Y, CamZ);
	const FRotator Rot(CamPitch, 0.f, 0.f);
	ASpectatorPawn* S = Cast<ASpectatorPawn>(PC->GetPawn());
	if (!S || !S->IsA<ASpectatorPawn>())
	{
		FActorSpawnParameters P;
		P.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		S = GetWorld()->SpawnActor<ASpectatorPawn>(Loc, Rot, P);
		if (S)
		{
			PC->Possess(S);
			CamPawn = S;
			Mark(TEXT("debug camera possessed"));
		}
	}
	if (S)
	{
		S->SetActorLocationAndRotation(Loc, Rot);
		if (APlayerCameraManager* PCM = PC->PlayerCameraManager)
		{
			PCM->SetActorLocationAndRotation(Loc, Rot);
		}
		UE_LOG(LogGTA, Display, TEXT("GTATEST: debug cam at %s pitch %.0f"), *Loc.ToString(), CamPitch);
	}
}

void AGTATestDirector::Mark(const FString& Msg)
{
	UE_LOG(LogGTA, Display, TEXT("GTATEST: %s"), *Msg);
}

void AGTATestDirector::Check(bool bPassed, const FString& What)
{
	if (bPassed) ++ChecksPassed; else ++ChecksFailed;
	const FString Line = FString(bPassed ? TEXT("PASS ") : TEXT("FAIL ")) + What;
	CheckReport += Line + TEXT("\n");
	Mark(Line);
}

void AGTATestDirector::Shot(const FString& Name)
{
	const FString File = OutDir / (Name + TEXT(".png"));
	FScreenshotRequest::RequestScreenshot(File, true, false);
	Mark(TEXT("screenshot ") + File);
}

void AGTATestDirector::RunStep(int32 Index)
{
	AGTAGameMode* M = GTA::Mode(this);
	AGTAPlayerCharacter* P = GTA::Player(this);
	AGTAPlayerController* PC = Cast<AGTAPlayerController>(GetWorld()->GetFirstPlayerController());
	if (!M || !P || !PC) return;
	const FString Name = GSteps[Index].Name;
	Mark(FString::Printf(TEXT("step %d %s"), Index, *Name));
	UWorld* W = GetWorld();
	auto SpawnAndEnter = [&](EGTAVehicle Id, const FTransform& T)
	{
		if (P->IsInVehicle()) PC->ExitVehicle(true);
		AGTAVehicle* V = AGTAVehicle::SpawnVehicle(W, Id, T);
		if (V) { V->bPlayerOwned = true; PC->EnterVehicle(V, 0); }
		TestVehicle = V;
		PC->bScriptedInput = true;
		return V;
	};
	if (Name == TEXT("spawn"))
	{
		if (M->Env) { M->Env->SetTimeOfDay(10.f); M->Env->SetWeather(EGTAWeather::Clear, true); M->Env->bAutoWeather = false; }
		StartLoc = P->GetActorLocation();
		P->bInvulnerable = true; // Keep independent smoke checks alive; damage is tested separately.
		PC->SetIgnoreLookInput(true);
		PC->SetControlRotation(FRotator(-12.f,0.f,0.f));
		USkeletalMeshComponent* Mesh = P->GetMesh();
		if (Mesh->GetSkeletalMeshAsset()) Mark(TEXT("REFROOT ") + Mesh->GetSkeletalMeshAsset()->GetRefSkeleton().GetRefBonePose()[0].ToString());
		Mark(FString::Printf(TEXT("PLAYER mesh=%s visible=%d bounds=%s pelvis=%s rootScale=%s"),
			*GetNameSafe(Mesh->GetSkeletalMeshAsset()), Mesh->IsVisible() ? 1 : 0,
			*Mesh->Bounds.BoxExtent.ToString(), *Mesh->GetBoneLocation(TEXT("pelvis")).ToString(),
			*Mesh->GetBoneTransform(0).GetScale3D().ToString()));
		Mark(FString::Printf(TEXT("player at %s, city instances %d missing %d"), *StartLoc.ToString(), M->City ? M->City->InstanceCount : -1, M->City ? M->City->MissingMeshCount : -1));
		Check(M->City && M->City->MissingMeshCount == 0, TEXT("city meshes resolve"));
		Check(Mesh->GetSkeletalMeshAsset() && Mesh->Bounds.BoxExtent.Z > 60.f && Mesh->Bounds.BoxExtent.Z < 150.f, TEXT("animated character is human size"));
		// -gtaspawn=X|Y|Z teleports the player before the first capture, so a suspected bad spawn
		// point can be tested without rebuilding the level. Pipe-separated: commas collide with the
		// engine's own command-line list parsing.
		FString Override;
		if (FParse::Value(FCommandLine::Get(), TEXT("gtaspawn="), Override))
		{
			TArray<FString> Parts;
			Override.ParseIntoArray(Parts, TEXT("|"));
			Mark(FString::Printf(TEXT("spawn override raw='%s' parts=%d"), *Override, Parts.Num()));
			if (Parts.Num() == 3)
			{
				const FVector Target(FCString::Atof(*Parts[0]), FCString::Atof(*Parts[1]), FCString::Atof(*Parts[2]));
				P->TeleportTo(Target, P->GetActorRotation(), false, true);
				StartLoc = Target;
				Mark(FString::Printf(TEXT("player teleported to %s"), *Target.ToString()));
			}
		}
	}
	else if (Name == TEXT("walk")) { WalkStart = P->GetActorLocation(); PC->SetControlRotation(FRotator(0,90,0)); }
	else if (Name == TEXT("jump"))
	{
		Check(FVector::Dist2D(WalkStart,P->GetActorLocation()) > 100.f, TEXT("on-foot movement"));
		P->InputMove(FVector2D::ZeroVector);
		P->Jump();
	}
	else if (Name == TEXT("drive"))
	{
		const FVector L = P->GetActorLocation() + FVector(-300.f, 0.f, 0.f);
		SpawnAndEnter(EGTAVehicle::Sedan, FTransform(FRotator(0.f, 90.f, 0.f), FVector(-17500.f + 250.f, 2000.f, 80.f)));
	}
	else if (Name == TEXT("exit"))
	{
		if (AGTAVehicle* V = TestVehicle.Get())
		{
			Check(FVector::Dist2D(V->GetActorLocation(),FVector(-17250,2000,80)) > 300.f, TEXT("sedan drives"));
			Check(V->GetActorLocation().Z < 1000.f, TEXT("sedan remains near road"));
			const FVector Hip=V->BodyMesh->GetComponentTransform().InverseTransformPosition(P->GetMesh()->GetBoneLocation(TEXT("pelvis")));
			Check(FMath::Abs(Hip.Y)<V->GetDef().Width*40.f && Hip.Z<V->GetDef().Height*70.f,TEXT("driver pelvis stays inside cabin"));
		}
		if (AGTAVehicle* V = TestVehicle.Get()) Mark(FString::Printf(TEXT("vehicle speed before exit %.1f km/h, moved %.1f m"), V->SpeedKmh(), FVector::Dist(V->GetActorLocation(), FVector(-17250.f, 2000.f, 80.f)) / 100.f));
		PC->bScriptedInput = false;
		PC->ExitVehicle(true);
	}
	else if (Name == TEXT("shoot"))
	{
		P->GiveWeapon(EGTAWeapon::Pistol, 60, true);
		AmmoBefore = P->CurrentSlotPtr() ? P->CurrentSlotPtr()->InClip : 0;
		P->SetAiming(true);
	}
	else if (Name == TEXT("police"))
	{
		Check(P->CurrentSlotPtr() && P->CurrentSlotPtr()->InClip<AmmoBefore,TEXT("fire consumes ammunition"));
		P->SetAiming(false);
		P->SetTriggerHeld(false);
		Mark(FString::Printf(TEXT("wanted after shooting: %d (witnessed %d / unwitnessed %d, pending reports %d)"), M->WantedLevel, M->CrimesWitnessed, M->CrimesUnwitnessed, M->PendingReportCount()));
		M->SetWantedLevel(2, true);
	}
	else if (Name == TEXT("night"))
	{
		Check(M->Population && M->Population->PoliceUnits.Num() > 0, TEXT("police dispatch"));
		Mark(FString::Printf(TEXT("police units %d vehicles %d"), M->Population ? M->Population->PoliceUnits.Num() : -1, M->Population ? M->Population->PoliceVehicles.Num() : -1));
		M->ClearWanted();
		if (M->Population) M->Population->ClearPolice();
		if (M->Env) M->Env->SetTimeOfDay(21.5f);
	}
	else if (Name == TEXT("rain"))
	{
		if (M->Env) { M->Env->SetTimeOfDay(17.f); M->Env->SetWeather(EGTAWeather::Rain, true); }
	}
	else if (Name == TEXT("heli"))
	{
		if (M->Env) { M->Env->SetWeather(EGTAWeather::Clear, true); M->Env->SetTimeOfDay(12.f); }
		SpawnAndEnter(EGTAVehicle::Helicopter, FTransform(FRotator::ZeroRotator, FVector(12000.f, 28500.f, 60.f)));
	}
	else if (Name == TEXT("plane"))
	{
		Check(TestVehicle.IsValid() && TestVehicle->AltitudeAGL() > 4.f, TEXT("helicopter takeoff"));
		if (AGTAVehicle* V = TestVehicle.Get()) Mark(FString::Printf(TEXT("heli altitude %.1f m"), V->AltitudeAGL()));
		SpawnAndEnter(EGTAVehicle::PropPlane, FTransform(FRotator::ZeroRotator, FVector(-13500.f, 24000.f, 60.f)));
	}
	else if (Name == TEXT("boat"))
	{
		Check(TestVehicle.IsValid() && TestVehicle->AltitudeAGL() > 2.f, TEXT("airplane takeoff"));
		if (AGTAVehicle* V = TestVehicle.Get()) Mark(FString::Printf(TEXT("plane speed %.1f km/h altitude %.1f m"), V->SpeedKmh(), V->AltitudeAGL()));
		SpawnAndEnter(EGTAVehicle::Speedboat, FTransform(FRotator(0.f, 180.f, 0.f), FVector(-23000.f, 0.f, GTA::SeaLevel())));
	}
	else if (Name == TEXT("map"))
	{
		Check(TestVehicle.IsValid() && TestVehicle->SpeedKmh() > 5.f, TEXT("boat propulsion"));
		if (AGTAVehicle* V = TestVehicle.Get()) Mark(FString::Printf(TEXT("boat speed %.1f km/h z %.1f"), V->SpeedKmh(), V->GetActorLocation().Z));
		PC->bScriptedInput = false;
		PC->ExitVehicle(true);
		P->TeleportTo(FVector(-14000.f, 0.f, 200.f), FRotator::ZeroRotator, false, true);
		PC->bMapOpen = true;
	}
	else if (Name == TEXT("menu"))
	{
		PC->bMapOpen = false;
		PC->OpenAdminMenu();
	}
	else if (Name == TEXT("wheel"))
	{
		PC->CloseAllMenus();
		for (int32 i = 1; i < (int32)EGTAWeapon::MAX; ++i) P->GiveWeapon((EGTAWeapon)i, 200, false);
		PC->bWheelOpen = true;
		PC->WheelHover = 5;
	}
	else if (Name == TEXT("persistence"))
	{
		PC->bWheelOpen = false;
		PC->CloseAllMenus();
		UGTAGameInstance* GI = GTA::Instance(this);
		const int32 Money = GI->Profile.Money;
		const FVector Loc = P->GetActorLocation();
		Check(GI->SaveProfile(TEXT("PortHalcyon_Automation")),TEXT("save slot writes"));
		GI->Profile.Money = -1;
		P->SetActorLocation(Loc+FVector(1000,0,0));
		const bool Loaded = GI->LoadProfile(TEXT("PortHalcyon_Automation"));
		P->LoadFromProfile();
		Check(Loaded && GI->Profile.Money == Money && FVector::Dist(P->GetActorLocation(),Loc)<10.f, TEXT("save restores money and position"));
	}
	else if (Name == TEXT("swim"))
	{
		P->TeleportTo(FVector(-23000,0,-400),FRotator::ZeroRotator,false,true);
	}
	else if (Name == TEXT("services"))
	{
		Check(P->IsSwimming(),TEXT("water volume activates swimming"));
		P->TeleportTo(StartLoc,FRotator::ZeroRotator,false,true);
		P->GetCharacterMovement()->SetMovementMode(MOVE_Walking);
		PC->OpenWeaponShop();
		Check(PC->IsMenuOpen() && PC->MenuStack.Last().Items.Num()>5,TEXT("weapon shop catalog"));
		PC->CloseAllMenus();
		PC->OpenAdminMenu();
		Check(PC->IsMenuOpen() && PC->MenuStack.Last().Items.Num()>15,TEXT("benchmark menu"));
		PC->CloseAllMenus();
		bool VehiclesResolve=true;
		for (const FGTAVehicleDef& Def : FGTAData::Vehicles())
			VehiclesResolve &= FGTAAssets::GenMesh(TEXT("Vehicles"),TEXT("SM_Veh_")+Def.Key)!=nullptr;
		Check(VehiclesResolve,TEXT("all 20 vehicle bodies load"));
		bool WeaponsResolve=true;
		for (int32 I=1;I<(int32)EGTAWeapon::MAX;++I)
			WeaponsResolve &= FGTAAssets::GenMesh(TEXT("Weapons"),FGTAData::Weapon((EGTAWeapon)I).Mesh)!=nullptr;
		Check(WeaponsResolve,TEXT("all 14 weapon meshes load"));
		bool Levels=true;
		for (int32 L=0;L<=5;++L) { M->SetWantedLevel(L,false); Levels &= M->WantedLevel==L; }
		Check(Levels,TEXT("wanted levels 0 through 5"));
		M->ClearWanted();
		if (AGTACharacter* Victim=M->Population->SpawnPed(StartLoc+FVector(400,0,0),0,EGTAPedRole::Civilian,9876))
		{
			UGameplayStatics::ApplyDamage(Victim,1000.f,PC,P,UGTADamage_Bullet::StaticClass());
			Check(Victim->bDead && Victim->IsRagdoll() && Victim->GetMesh()->GetPhysicsAsset(),TEXT("damage and physics ragdoll"));
		}
		if (AGTAVehicle* V=TestVehicle.Get())
		{
			V->Health=100.f; V->Repair();
			Check(V->Health>=V->GetDef().Health,TEXT("vehicle repair"));
		}
	}
	else if (Name == TEXT("parachute"))
	{
		P->Revive();
		P->SetBase(static_cast<UPrimitiveComponent*>(nullptr));
		P->GetCharacterMovement()->StopMovementImmediately();
		P->SetHasParachute(true);
		P->TeleportTo(FVector(-17000,16000,8000),FRotator::ZeroRotator,false,true);
		Check(FMath::Abs(P->GetActorLocation().Z-8000.f)<10.f,TEXT("parachute starts at 80 metres"));
		P->GetCharacterMovement()->SetMovementMode(MOVE_Falling);
		Check(P->InputParachute(),TEXT("parachute deploys"));
	}
	else if (Name == TEXT("escape"))
	{
		Check(P->GetActorLocation().Z>5500.f && P->GetActorLocation().Z<8200.f && FVector::Dist2D(P->GetActorLocation(),FVector(-17000,16000,0))<5000.f,TEXT("parachute trajectory stays local and descends"));
		Check(P->GetVelocity().Z>-900.f,TEXT("parachute slows descent"));
		P->InputParachute();
		M->Population->ClearPolice();
		M->SetWantedLevel(1,true);
		P->TeleportTo(FVector(-55000,0,-200),FRotator::ZeroRotator,false,true);
		bEscapeTest=true;
	}
	else if (Name == TEXT("done"))
	{
		if (bEscapeTest) Check(M->WantedLevel==0,TEXT("escape after losing police line of sight"));
		PC->bWheelOpen = false;
		Mark(FString::Printf(TEXT("FX particles %d, peds %d, traffic %d, parked %d"), M->FX ? M->FX->ActiveParticles() : -1,
			M->Population ? M->Population->Peds.Num() : -1, M->Population ? M->Population->Traffic.Num() : -1, M->Population ? M->Population->Parked.Num() : -1));
		Mark(TEXT("complete"));
		if (FrameTimes.Num()>0)
		{
			float Sum=0; for(float F:FrameTimes) Sum+=F;
			FrameTimes.Sort();
			const float P95=FrameTimes[FMath::Min(FrameTimes.Num()-1,FMath::FloorToInt(FrameTimes.Num()*.95f))];
			const FString Perf=FString::Printf(TEXT("FPS mean=%.1f p95_frame_ms=%.2f frames=%d\n"),FrameTimes.Num()/FMath::Max(.001f,Sum),P95*1000.f,FrameTimes.Num());
			Mark(Perf); CheckReport+=Perf;
		}
		Mark(FString::Printf(TEXT("RESULT passed=%d failed=%d"),ChecksPassed,ChecksFailed));
		FFileHelper::SaveStringToFile(CheckReport+FString::Printf(TEXT("passed=%d failed=%d\n"),ChecksPassed,ChecksFailed),*(OutDir/TEXT("checks.txt")));
	}
}

void AGTATestDirector::Tick(float Dt)
{
	Super::Tick(Dt);
	UWorld* W = GetWorld();
	const float Now = W->GetTimeSeconds();
	const double Wall=FPlatformTime::Seconds();
	if (LastFrameWall>0 && Now>WarmupEnd) FrameTimes.Add((float)(Wall-LastFrameWall));
	LastFrameWall=Wall;
	AGTAPlayerCharacter* P = GTA::Player(this);
	if (!P) return;

	// -gtadiag: apply one render configuration at a time and capture each. Console commands passed
	// on the command line never reached this build, so the only trustworthy way to bisect the
	// renderer is to drive the CVars from inside the running game.
	if (bDiag)
	{
		if (Now < DiagNext) return;
		if (DiagStep >= UE_ARRAY_COUNT(GDiagSteps))
		{
			Mark(TEXT("DIAG complete"));
			SetActorTickEnabled(false);
			FPlatformMisc::RequestExit(false);
			return;
		}
		const FGTADiagStep& S = GDiagSteps[DiagStep];
		for (const TCHAR* C : S.Cmds)
		{
			if (C && *C) GEngine->Exec(W, C);
		}
		// Let the renderer settle: several of these force a full lighting/shadow re-init.
		DiagNext = Now + 9.f;
		Mark(FString::Printf(TEXT("DIAG step %d %s"), DiagStep, S.Name));
		Shot(FString::Printf(TEXT("D%02d_%s"), DiagStep, S.Name));
		++DiagStep;
		return;
	}

	// -gtalightlog: dump the live lighting state once a second. Rendering faults here are invisible
	// from the outside (the frame is just black), so the actual intensities have to be read back.
	if (bLightLog && Now - LastLightLog > 1.f)
	{
		LastLightLog = Now;
		AGTAGameMode* M = GTA::Mode(this);
		AGTAEnvironment* E = M ? M->Env : nullptr;
		FString SunStr = TEXT("no env"), SkyStr = TEXT("-");
		if (E)
		{
			TArray<UDirectionalLightComponent*> Suns;
			E->GetComponents(Suns);
			for (UDirectionalLightComponent* L : Suns)
			{
				SunStr += FString::Printf(TEXT("[%s I=%.2f vis=%d pitch=%.1f]"), *L->GetName(),
					(double)L->Intensity, L->IsVisible() ? 1 : 0, (double)L->GetComponentRotation().Pitch);
			}
			TArray<USkyLightComponent*> Skies;
			E->GetComponents(Skies);
			for (USkyLightComponent* S : Skies)
			{
				SkyStr += FString::Printf(TEXT("[%s I=%.2f vis=%d]"), *S->GetName(), (double)S->Intensity, S->IsVisible() ? 1 : 0);
			}		}
		const FVector Cam = W->GetFirstPlayerController() && W->GetFirstPlayerController()->PlayerCameraManager
			? W->GetFirstPlayerController()->PlayerCameraManager->GetCameraLocation() : FVector::ZeroVector;
		Mark(FString::Printf(TEXT("LIGHT sun=%s sky=%s cam=%s"), *SunStr, *SkyStr, *Cam.ToCompactString()));

		// What is actually in front of the camera? Without this the only symptom is a black frame.
		APlayerController* PCam = W->GetFirstPlayerController();
		const FRotator CamRot = PCam ? PCam->GetControlRotation() : FRotator::ZeroRotator;
		FCollisionQueryParams Q(SCENE_QUERY_STAT(GTACamProbe), false);
		Q.AddIgnoredActor(P);
		for (float Dist : {200.f, 5000.f})
		{
			FHitResult H;
			const FVector To = Cam + CamRot.Vector() * Dist;
			const bool bHit = W->LineTraceSingleByChannel(H, Cam, To, ECC_Visibility, Q);
			Mark(FString::Printf(TEXT("CAMPROBE %.0fcm hit=%d %s"), Dist, bHit ? 1 : 0,
				bHit ? *FString::Printf(TEXT("%s actor=%s"), *H.ImpactPoint.ToCompactString(), *GetNameSafe(H.GetActor())) : TEXT("clear")));
		}
		// Which vehicle is nearest the player, and how far? A parked car sitting on the spawn point
		// shows up here as a hit on every probe distance.
		{
			AGTAGameMode* M2 = GTA::Mode(this);
			float Best = 1e9f;
			FString BestName = TEXT("none");
			FVector BestLoc = FVector::ZeroVector;
			if (M2 && M2->Population)
			{
				for (const TObjectPtr<AGTAVehicle>& V : M2->Population->Parked)
				{
					if (!V) continue;
					const float D = FVector::Dist(V->GetActorLocation(), P->GetActorLocation());
					if (D < Best) { Best = D; BestName = V->GetName(); BestLoc = V->GetActorLocation(); }
				}
			}
			Mark(FString::Printf(TEXT("NEARVEH %s dist=%.0fcm at %s"), *BestName, Best, *BestLoc.ToCompactString()));
		}
		// Every vehicle physically at the camera. The probe above reports an impact at the camera
		// origin, which means the trace starts inside a collider: find out which actor that is.
		{
			APlayerController* PCam2 = W->GetFirstPlayerController();
			const FVector CamLoc = PCam2 && PCam2->PlayerCameraManager
				? PCam2->PlayerCameraManager->GetCameraLocation() : P->GetActorLocation();
			int32 Near = 0;
			for (TActorIterator<AGTAVehicle> It(W); It; ++It)
			{
				AGTAVehicle* V = *It;
				if (!V) continue;
				const float D = FVector::Dist(V->GetActorLocation(), CamLoc);
				if (D > 1500.f) continue;
				Mark(FString::Printf(TEXT("VEH@CAM %s dist=%.0f loc=%s parked=%d plyr=%d"),
					*V->GetName(), D, *V->GetActorLocation().ToCompactString(), V->bParked ? 1 : 0, V->bPlayerOwned ? 1 : 0));
				++Near;
				if (Near >= 6) break;
			}
			if (Near == 0) Mark(TEXT("VEH@CAM none within 15m"));
		}
		// Is the pawn itself overlapping something it should not be? A character spawned inside a
		// building or a car reports a hit right at its own capsule.
		{
			USkeletalMeshComponent* Sk = P->GetMesh();
			Mark(FString::Printf(TEXT("PAWN z=%.1f skel=%s vis=%d loc=%s"), P->GetActorLocation().Z,
				Sk && Sk->GetSkeletalMeshAsset() ? *Sk->GetSkeletalMeshAsset()->GetName() : TEXT("NULL"),
				Sk && Sk->IsVisible() ? 1 : 0, *P->GetActorLocation().ToCompactString()));
		}
	}

	// continuous inputs during steps
	if (Step >= 0 && Step < UE_ARRAY_COUNT(GSteps))
	{
		const FString Name = GSteps[Step].Name;
		const float T = Now - StepStart;
		AGTAVehicle* V = TestVehicle.Get();
		if (Name == TEXT("parachute") && FMath::FloorToInt(T)!=FMath::FloorToInt(T-Dt))
			Mark(FString::Printf(TEXT("PARACHUTE pos=%s velocity=%s head=%s"),*P->GetActorLocation().ToString(),*P->GetVelocity().ToString(),*P->GetMesh()->GetBoneLocation(TEXT("head")).ToString()));
		if (Name == TEXT("walk")) P->InputMove(FVector2D(0,1));
		if (Name == TEXT("orbit")) { if (APlayerController* PC = W->GetFirstPlayerController()) PC->AddYawInput(Dt * 40.f); }
		if (Name == TEXT("drive") && V)
		{
			V->Throttle = 1.f; V->Steer = T > 4.f ? 0.25f : 0.f;
			if (FMath::FloorToInt(T) != FMath::FloorToInt(T-Dt))
				Mark(FString::Printf(TEXT("DRIVE pos=%s vel=%s wheels=%d"), *V->GetActorLocation().ToString(), *V->GetVelocity().ToString(), V->WheelsInContact()));
		}
		if (Name == TEXT("shoot") && T > 1.f) { P->SetTriggerHeld(FMath::Fmod(T, 0.6f) < 0.1f); }
		if (Name == TEXT("heli") && V) { V->LiftInput = T < 3.5f ? 1.f : 0.f; V->PitchInput = T > 3.5f ? 0.4f : 0.f; }
		if (Name == TEXT("plane") && V) { V->Throttle = 1.f; V->PitchInput = T > 5.f ? -0.5f : 0.f; }
		if (Name == TEXT("boat") && V) { V->Throttle = 1.f; V->Steer = 0.2f; }
		const float Dur = GSteps[Step].Duration;
		if (T > Dur - 0.6f && T - Dt <= Dur - 0.6f) Shot(FString::Printf(TEXT("%02d_%s"), Step, *Name));
	}
	if (Now < NextStepTime) return;
	Step++;
	if (Step >= UE_ARRAY_COUNT(GSteps))
	{
		Mark(TEXT("exit"));
		SetActorTickEnabled(false);
		FPlatformMisc::RequestExitWithStatus(false,ChecksFailed>0 ? 1 : 0);
		return;
	}
	if (!Only.IsEmpty() && !Only.Contains(GSteps[Step].Name) && FString(GSteps[Step].Name) != TEXT("done")) { NextStepTime = Now; return; }
	StepStart = Now;
	NextStepTime = Now + GSteps[Step].Duration;
	RunStep(Step);
	if (bDebugCam && Step == 1) DebugCam();
}

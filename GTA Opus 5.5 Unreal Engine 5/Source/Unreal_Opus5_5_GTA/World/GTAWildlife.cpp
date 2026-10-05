#include "World/GTAWildlife.h"
#include "Core/GTAGame.h"
#include "Core/GTAGameInstance.h"
#include "Player/GTAPlayerCharacter.h"
#include "Components/InstancedStaticMeshComponent.h"

AGTAWildlife::AGTAWildlife()
{
	PrimaryActorTick.bCanEverTick=true;
	PrimaryActorTick.TickInterval=0.05f;
	RootComponent=CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	Gulls=CreateDefaultSubobject<UInstancedStaticMeshComponent>(TEXT("Gulls"));
	Wings=CreateDefaultSubobject<UInstancedStaticMeshComponent>(TEXT("Wings"));
	Fish=CreateDefaultSubobject<UInstancedStaticMeshComponent>(TEXT("Fish"));
	Deer=CreateDefaultSubobject<UInstancedStaticMeshComponent>(TEXT("Deer"));
	for (auto* C : {Gulls.Get(),Wings.Get(),Fish.Get(),Deer.Get()})
	{
		C->SetupAttachment(RootComponent);
		C->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		C->SetCanEverAffectNavigation(false);
	}
}
void AGTAWildlife::BeginPlay()
{
	Super::BeginPlay();
	Gulls->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Animals"),TEXT("SM_Animal_Gull")));
	Wings->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Animals"),TEXT("SM_Animal_GullWing")));
	Fish->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Animals"),TEXT("SM_Animal_Fish")));
	Deer->SetStaticMesh(FGTAAssets::GenMesh(TEXT("Animals"),TEXT("SM_Animal_Deer")));
	for (int32 I=0;I<12;++I) { Gulls->AddInstance(FTransform::Identity); Wings->AddInstance(FTransform::Identity); Wings->AddInstance(FTransform::Identity); }
	for (int32 I=0;I<16;++I) Fish->AddInstance(FTransform::Identity);
	for (int32 I=0;I<4;++I) { DeerPositions.Add(FVector(23500+I*650,11500+I*350,0)); Deer->AddInstance(FTransform(DeerPositions.Last())); }
	UE_LOG(LogGTA,Display,TEXT("WILDLIFE: 12 gulls, 16 fish, 4 deer"));
}
void AGTAWildlife::Tick(float Dt)
{
	Super::Tick(Dt);
	const auto* GI=GTA::Instance(this);
	const bool Visible=!GI || GI->bWildlifeEnabled;
	for (auto* C : {Gulls.Get(),Wings.Get(),Fish.Get(),Deer.Get()}) C->SetVisibility(Visible);
	if (!Visible) return;
	const float T=GetWorld()->GetTimeSeconds();
	for (int32 I=0;I<12;++I)
	{
		const float A=T*(0.1f+I*.003f)+I*2.3f;
		const FVector P(-20500+FMath::Cos(A)*1600,-16000+I*2600+FMath::Sin(A)*1300,1200+I*60+FMath::Sin(A*2)*120);
		const FRotator R(0,FMath::RadiansToDegrees(A)+90,0);
		Gulls->UpdateInstanceTransform(I,FTransform(R,P,FVector(1.4f)),false,true);
		for (int32 Side=0;Side<2;++Side)
		{
			const float Flap=FMath::Sin(T*7+I)*28;
			Wings->UpdateInstanceTransform(I*2+Side,FTransform(R.Quaternion()*FRotator(0,0,Side?180-Flap:Flap).Quaternion(),P,FVector(1.4f)),false,true);
		}
	}
	for (int32 I=0;I<16;++I)
	{
		const float A=T*.17f+I*2.1f;
		const FVector P(-25300+FMath::Cos(A)*1100,-8000+I*900+FMath::Sin(A)*450,-400+FMath::Sin(A)*60);
		Fish->UpdateInstanceTransform(I,FTransform(FRotator(0,FMath::RadiansToDegrees(A)+90,0),P),false,true);
	}
	const AGTAPlayerCharacter* Player=GTA::Player(this);
	for (int32 I=0;I<DeerPositions.Num();++I)
	{
		FVector& P=DeerPositions[I];
		FVector Dir(FMath::Cos(T*.2f+I*2),FMath::Sin(T*.2f+I*2),0);
		float Speed=35;
		if (Player && FVector::Dist2D(P,Player->GetActorLocation())<2000) { Dir=(P-Player->GetActorLocation()).GetSafeNormal2D(); Speed=380; }
		P+=Dir*Speed*Dt;
		P.X=FMath::Clamp(P.X,21500.,28500.); P.Y=FMath::Clamp(P.Y,10000.,15800.);
		Deer->UpdateInstanceTransform(I,FTransform(Dir.Rotation(),P+FVector(0,0,FMath::Abs(FMath::Sin(T*(Speed>100?9:2)+I))*5)),false,true);
	}
}

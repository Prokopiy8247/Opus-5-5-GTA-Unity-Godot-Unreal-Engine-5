// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;

public class Unreal_Opus5_5_GTA : ModuleRules
{
	public Unreal_Opus5_5_GTA(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput",
			"UMG", "Slate", "SlateCore", "AIModule", "NavigationSystem", "PhysicsCore",
			"GameplayTasks", "AudioMixer"
		});

		PublicIncludePaths.Add(ModuleDirectory);

		if (Target.bBuildEditor)
		{
			PrivateDependencyModuleNames.AddRange(new string[] { "UnrealEd", "PhysicsUtilities", "AssetRegistry" });
		}
	}
}

using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>
    /// Single entry point placed in the start scene by the editor WorldBuilder. Creates every runtime system,
    /// spawns the player at the safehouse and drops straight into free roam (no missions).
    /// </summary>
    [DefaultExecutionOrder(-100)]
    public class GameBootstrap : MonoBehaviour
    {
        public Light sun, moon;
        public GameObject skyDome;
        public Camera mainCamera;
        public static bool AutoTest;

        void Awake()
        {
            Application.targetFrameRate = 144;
            QualitySettings.vSyncCount = 1;
            Time.fixedDeltaTime = 1f / 60f;
            Physics.defaultSolverIterations = 8;
            Layers.SetupCollisionMatrix();
            AudioFX.Init();
            if (GameManager.I == null) new GameObject("[GameManager]").AddComponent<GameManager>();

            var world = FindAnyObjectByType<WorldData>();
            if (world != null) world.ApplyToRuntime();

            GameTime.Init(skyDome);
            GameTime.I.sun = sun; GameTime.I.moon = moon;
            GameTime.I.SetTime(10.5f);
            Weather.Init();

            new GameObject("[Wanted]").AddComponent<WantedSystem>();
            new GameObject("[PoliceDispatch]").AddComponent<PoliceDispatch>();
            new GameObject("[Traffic]").AddComponent<TrafficManager>();
            new GameObject("[Population]").AddComponent<PopulationManager>();
            Wildlife.Init();
            Activities.Init();
            Parachute.Init();

            var player = SpawnPlayer(world);
            SetupCamera(player);

            HUD.Init();
            WeaponWheel.Init();
            MapScreen.Init();
            PauseMenu.Init();
            AdminMenu.Init();
            Phone.Init();
            ModShop.Init();
            ShopUI.Init();
            WorldInteractions.BindAll();

            TrafficManager.I.Begin();
            PopulationManager.I.Begin();
            if (world != null) world.SpawnShowcaseVehicles();

            GameInput.LockCursor(true);
            HUD.Notify("Welcome to Port Halcyon - free roam. F1: admin menu, Esc: pause, M: map, Up/P: phone", 6f);
            AutoTest = System.Environment.CommandLine.Contains("-autotest");
            if (AutoTest) gameObject.AddComponent<AutoTester>();
        }

        GameObject SpawnPlayer(WorldData world)
        {
            var prefab = GameDatabase.I != null ? GameDatabase.I.Get("CHR_Male") : null;
            Vector3 pos = world != null ? world.playerSpawn : new Vector3(0f, 3f, 0f);
            float yaw = world != null ? world.playerSpawnYaw : 0f;
            GameObject go;
            if (prefab != null) go = Instantiate(prefab, pos, Quaternion.Euler(0f, yaw, 0f));
            else { go = new GameObject("Player"); go.transform.position = pos; }
            go.name = "Player";
            Layers.SetRecursive(go, Layers.Player);
            var cc = go.GetComponent<CharacterController>() ?? go.AddComponent<CharacterController>();
            cc.height = 1.8f; cc.radius = 0.32f; cc.center = new Vector3(0f, 0.92f, 0f); cc.stepOffset = 0.45f; cc.slopeLimit = 55f; cc.skinWidth = 0.05f;
            var rig = go.GetComponent<CharacterRig>() ?? go.AddComponent<CharacterRig>();
            rig.Init();
            var look = go.GetComponent<CharacterAppearance>() ?? go.AddComponent<CharacterAppearance>();
            var actor = go.GetComponent<Actor>() ?? go.AddComponent<Actor>();
            actor.faction = Faction.Player; actor.displayName = "You"; actor.maxHealth = actor.health = 200f; actor.armor = 50f;
            var wc = go.GetComponent<WeaponController>() ?? go.AddComponent<WeaponController>();
            wc.isPlayer = true; wc.owner = actor;
            actor.rig = rig; actor.weapons = wc; actor.look = look;
            var state = new GameObject("[PlayerState]").AddComponent<PlayerState>();
            state.outfit = CharacterAppearance.PlayerDefault();
            state.SkillUp += msg => HUD.Notify(msg, 2.2f);
            look.Apply(state.outfit);
            look.SetGear(state.hasParachute, state.hasScuba);
            go.AddComponent<PlayerController>();
            wc.Give("pistol", 60);
            wc.Give("bat", 0);
            wc.Equip("pistol");
            actor.Died += OnPlayerDied;
            return go;
        }

        void SetupCamera(GameObject player)
        {
            var cam = mainCamera != null ? mainCamera : Camera.main;
            if (cam == null) { var cg = new GameObject("Main Camera"); cam = cg.AddComponent<Camera>(); cg.tag = "MainCamera"; cg.AddComponent<AudioListener>(); }
            cam.farClipPlane = 1800f;
            cam.nearClipPlane = 0.1f;
            var pc = cam.GetComponent<PlayerCamera>() ?? cam.gameObject.AddComponent<PlayerCamera>();
            pc.cam = cam;
            pc.yaw = player.transform.eulerAngles.y;
        }

        void OnPlayerDied(Actor a, DamageInfo d)
        {
            StartCoroutine(DeathRoutine());
        }

        IEnumerator DeathRoutine()
        {
            AudioFX.Play("stinger_dead", 0.8f);
            HUD.Notify("FLATLINED", 4f);
            GameManager.TimeScale = 0.35f;
            yield return new WaitForSecondsRealtime(3.2f);
            GameManager.TimeScale = 1f;
            var pc = PlayerController.I;
            var ps = PlayerState.I;
            int bill = Mathf.Min(ps.money, 500);
            ps.money -= bill;
            WantedSystem.Clear();
            var spawn = WorldMarkers.Hospital + new Vector3(0f, 0.5f, 0f);
            spawn.y = U.GroundHeight(spawn + Vector3.up * 3f, spawn.y) + 0.2f;
            pc.actor.Revive(spawn, Quaternion.identity);
            pc.Teleport(spawn, 180f);
            pc.breath = 1f;
            HUD.Notify("Hospital bill: " + U.Money(bill), 3f);
        }

        void Update()
        {
            if (GameInput.DownRaw(UnityEngine.InputSystem.Key.M) && !PauseMenu.IsOpen && !AdminMenu.Open) MapScreen.Toggle();
            if ((GameInput.DownRaw(UnityEngine.InputSystem.Key.UpArrow) || GameInput.DownRaw(UnityEngine.InputSystem.Key.P)) && !PauseMenu.IsOpen && !AdminMenu.Open && !MapScreen.IsOpen) Phone.Toggle();
            RadioSystem.Tick(Vector3.zero);
        }
    }
}

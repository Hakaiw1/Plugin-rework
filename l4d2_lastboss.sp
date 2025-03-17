// ============================================================================
// [L4D2] Last Boss v2.0
// Author: ztar
// Web: http://ztar.blog7.fc2.com/
// Description: Special Tank spawns during finales with unique abilities and transformations.
// Version: 2.0
// ============================================================================

#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.0"
#define DEBUG 0

// Constants for plugin states and forms
#define STATE_ON 1
#define STATE_OFF 0
#define FORM_ONE 1
#define FORM_TWO 2
#define FORM_THREE 3
#define FORM_FOUR 4
#define FORM_DEAD -1

#define TEAM_SURVIVOR 2
#define ZOMBIE_CLASS_TANK 8
#define WEAPON_TYPE_MOLOTOV 0
#define WEAPON_TYPE_EXPLODE 1

// Model paths
#define MODEL_GASCAN "models/props_junk/gascan001a.mdl"
#define MODEL_PROPANE "models/props_junk/propanecanister001a.mdl"

// Sound paths
#define SOUND_EXPLOSION "animation/bombing_run_01.wav"
#define SOUND_SPAWN "music/pzattack/contusion.wav"
#define SOUND_BURN_CLAW "weapons/grenade_launcher/grenadefire/grenade_launcher_explode_1.wav"
#define SOUND_GRAVITY_CLAW "plats/churchbell_end.wav"
#define SOUND_DREAD_CLAW "ambient/random_amb_sounds/randbridgegroan_03.wav"
#define SOUND_EARTHQUAKE "player/charger/hit/charger_smash_02.wav"
#define SOUND_STEEL "physics/metal/metal_solid_impact_hard5.wav"
#define SOUND_FORM_CHANGE "items/suitchargeok1.wav"
#define SOUND_HOWL "player/tank/voice/pain/tank_fire_08.wav"
#define SOUND_WARP "ambient/energy/zap9.wav"

// Particle effects
#define PARTICLE_SPAWN "electrical_arc_01_system"
#define PARTICLE_DEATH "gas_explosion_main"
#define PARTICLE_FORM_THREE "apc_wheel_smoke1"
#define PARTICLE_FORM_FOUR "aircraft_destroy_fastFireTrail"
#define PARTICLE_WARP "water_splash"

// Chat messages
#define MESSAGE_SPAWN "\x05Ready for Last Battle! \x04Type-UNKNOWN\x01[THE BOSS]"
#define MESSAGE_SPAWN_HEALTH "  Health:?????  SpeedRate:???\n"
#define MESSAGE_FORM_TWO "\x05Form changed -> \x01[STEEL OVERLOAD]"
#define MESSAGE_FORM_THREE "\x05Form changed -> \x01[NIGHT STALKER]"
#define MESSAGE_FORM_FOUR "\x05Form changed -> \x01[SPIRIT OF FIRE]"

// ConVar handles
ConVar g_cvEnablePlugin;
ConVar g_cvEnableAnnounce;
ConVar g_cvEnableSteel;
ConVar g_cvEnableStealth;
ConVar g_cvEnableGravity;
ConVar g_cvEnableBurn;
ConVar g_cvEnableJump;
ConVar g_cvEnableQuake;
ConVar g_cvEnableComet;
ConVar g_cvEnableDread;
ConVar g_cvEnableGush;
ConVar g_cvEnableAbyss;
ConVar g_cvEnableWarp;

ConVar g_cvHealthMax;
ConVar g_cvHealthFormTwo;
ConVar g_cvHealthFormThree;
ConVar g_cvHealthFormFour;

ConVar g_cvColorFormOne;
ConVar g_cvColorFormTwo;
ConVar g_cvColorFormThree;
ConVar g_cvColorFormFour;

ConVar g_cvForceFormOne;
ConVar g_cvForceFormTwo;
ConVar g_cvForceFormThree;
ConVar g_cvForceFormFour;

ConVar g_cvSpeedFormOne;
ConVar g_cvSpeedFormTwo;
ConVar g_cvSpeedFormThree;
ConVar g_cvSpeedFormFour;

ConVar g_cvWeightFormTwo;
ConVar g_cvStealthIntervalFormThree;
ConVar g_cvJumpIntervalFormFour;
ConVar g_cvJumpHeightFormFour;
ConVar g_cvGravityInterval;
ConVar g_cvQuakeRadius;
ConVar g_cvQuakeForce;
ConVar g_cvDreadInterval;
ConVar g_cvDreadRate;
ConVar g_cvForceFormFourC5M5;
ConVar g_cvWarpInterval;

// Global variables
int g_iAlphaRate;
int g_iVisibility;
int g_iBossFlag = STATE_OFF;
int g_iLastFlag = STATE_OFF;
int g_iBossClient = FORM_DEAD;
int g_iPreviousForm = FORM_DEAD;
int g_iDefaultTankForce;
int g_iVelocityOffset = -1;
int g_iWaveCount;
float g_fTeleportPosition[3];
bool g_bIsL4D1 = false;
Handle g_hTimerUpdate = null;

// Plugin information
public Plugin myinfo = {
    name = "[L4D2] LAST BOSS",
    author = "ztar",
    description = "Special Tank spawns during finale with unique abilities.",
    version = PLUGIN_VERSION,
    url = "http://ztar.blog7.fc2.com/"
};

// ============================================================================
// Plugin Startup
// ============================================================================

public void OnPluginStart() {
    // Detect game version (L4D1 or L4D2)
    char gameName[32];
    GetGameFolderName(gameName, sizeof(gameName));
    g_bIsL4D1 = StrEqual(gameName, "left4dead");

    // Initialize ConVars
    InitializeConVars();

    // Hook events
    HookEvent("round_start", Event_RoundStart);
    HookEvent("finale_start", Event_FinaleStart);
    HookEvent("finale_vehicle_incoming", Event_FinaleLast);
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_incapacitated", Event_PlayerHurt);
    if (!g_bIsL4D1) {
        HookEvent("finale_bridge_lowering", Event_FinaleStart);
    }

    // Auto-execute configuration file
    AutoExecConfig(true, "l4d2_lastboss");

    // Store default tank throw force
    g_iDefaultTankForce = GetConVarInt(FindConVar("z_tank_throw_force"));

    // Find velocity offset for player movement
    g_iVelocityOffset = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
    if (g_iVelocityOffset == -1) {
        LogError("Failed to find offset for CBasePlayer::m_vecVelocity[0]");
    }
}

// Initialize ConVars for plugin configuration
void InitializeConVars() {
    // Enable/Disable settings
    g_cvEnablePlugin = CreateConVar("sm_lastboss_enable", "1", "Enable Last Boss spawning (0: OFF, 1: Finale Only, 2: Always, 3: Second Tank Only)", FCVAR_NOTIFY);
    g_cvEnableAnnounce = CreateConVar("sm_lastboss_enable_announce", "1", "Enable announcements (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableSteel = CreateConVar("sm_lastboss_enable_steel", "1", "Enable Steel Skin ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableStealth = CreateConVar("sm_lastboss_enable_stealth", "1", "Enable Stealth Skin ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableGravity = CreateConVar("sm_lastboss_enable_gravity", "1", "Enable Gravity Claw ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableBurn = CreateConVar("sm_lastboss_enable_burn", "1", "Enable Burning Claw ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableQuake = CreateConVar("sm_lastboss_enable_quake", "1", "Enable Earth Quake ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableJump = CreateConVar("sm_lastboss_enable_jump", "1", "Enable Mad Spring ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableComet = CreateConVar("sm_lastboss_enable_comet", "1", "Enable Blast Rock and Comet Strike abilities (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableDread = CreateConVar("sm_lastboss_enable_dread", "1", "Enable Dread Claw ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableGush = CreateConVar("sm_lastboss_enable_gush", "1", "Enable Flame Gush ability (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvEnableAbyss = CreateConVar("sm_lastboss_enable_abyss", "1", "Enable Call of Abyss ability (0: OFF, 1: Fourth Form Only, 2: All Forms)", FCVAR_NOTIFY);
    g_cvEnableWarp = CreateConVar("sm_lastboss_enable_warp", "1", "Enable Fatal Mirror ability (0: OFF, 1: ON)", FCVAR_NOTIFY);

    // Health settings
    g_cvHealthMax = CreateConVar("sm_lastboss_health_max", "30000", "Maximum health for Last Boss", FCVAR_NOTIFY);
    g_cvHealthFormTwo = CreateConVar("sm_lastboss_health_second", "22000", "Health for second form", FCVAR_NOTIFY);
    g_cvHealthFormThree = CreateConVar("sm_lastboss_health_third", "14000", "Health for third form", FCVAR_NOTIFY);
    g_cvHealthFormFour = CreateConVar("sm_lastboss_health_forth", "8000", "Health for fourth form", FCVAR_NOTIFY);

    // Color settings
    g_cvColorFormOne = CreateConVar("sm_lastboss_color_first", "255 255 80", "RGB color for first form (0-255)", FCVAR_NOTIFY);
    g_cvColorFormTwo = CreateConVar("sm_lastboss_color_second", "80 255 80", "RGB color for second form (0-255)", FCVAR_NOTIFY);
    g_cvColorFormThree = CreateConVar("sm_lastboss_color_third", "80 80 255", "RGB color for third form (0-255)", FCVAR_NOTIFY);
    g_cvColorFormFour = CreateConVar("sm_lastboss_color_forth", "255 80 80", "RGB color for fourth form (0-255)", FCVAR_NOTIFY);

    // Force settings
    g_cvForceFormOne = CreateConVar("sm_lastboss_force_first", "1000", "Throw force for first form", FCVAR_NOTIFY);
    g_cvForceFormTwo = CreateConVar("sm_lastboss_force_second", "1500", "Throw force for second form", FCVAR_NOTIFY);
    g_cvForceFormThree = CreateConVar("sm_lastboss_force_third", "800", "Throw force for third form", FCVAR_NOTIFY);
    g_cvForceFormFour = CreateConVar("sm_lastboss_force_forth", "1800", "Throw force for fourth form", FCVAR_NOTIFY);

    // Speed settings
    g_cvSpeedFormOne = CreateConVar("sm_lastboss_speed_first", "0.9", "Movement speed for first form", FCVAR_NOTIFY);
    g_cvSpeedFormTwo = CreateConVar("sm_lastboss_speed_second", "1.1", "Movement speed for second form", FCVAR_NOTIFY);
    g_cvSpeedFormThree = CreateConVar("sm_lastboss_speed_third", "1.0", "Movement speed for third form", FCVAR_NOTIFY);
    g_cvSpeedFormFour = CreateConVar("sm_lastboss_speed_forth", "1.2", "Movement speed for fourth form", FCVAR_NOTIFY);

    // Skill settings
    g_cvWeightFormTwo = CreateConVar("sm_lastboss_weight_second", "8.0", "Gravity for second form", FCVAR_NOTIFY);
    g_cvStealthIntervalFormThree = CreateConVar("sm_lastboss_stealth_third", "10.0", "Stealth interval for third form", FCVAR_NOTIFY);
    g_cvJumpIntervalFormFour = CreateConVar("sm_lastboss_jumpinterval_forth", "1.0", "Jump interval for fourth form", FCVAR_NOTIFY);
    g_cvJumpHeightFormFour = CreateConVar("sm_lastboss_jumpheight_forth", "300.0", "Jump height for fourth form", FCVAR_NOTIFY);
    g_cvGravityInterval = CreateConVar("sm_lastboss_gravityinterval", "6.0", "Gravity Claw interval for second form", FCVAR_NOTIFY);
    g_cvQuakeRadius = CreateConVar("sm_lastboss_quake_radius", "600.0", "Earth Quake radius", FCVAR_NOTIFY);
    g_cvQuakeForce = CreateConVar("sm_lastboss_quake_force", "350.0", "Earth Quake force", FCVAR_NOTIFY);
    g_cvDreadInterval = CreateConVar("sm_lastboss_dreadinterval", "8.0", "Dread Claw interval for third form", FCVAR_NOTIFY);
    g_cvDreadRate = CreateConVar("sm_lastboss_dreadrate", "235", "Dread Claw blind rate for third form", FCVAR_NOTIFY);
    g_cvForceFormFourC5M5 = CreateConVar("sm_lastboss_forth_c5m5_bridge", "0", "Start in fourth form on c5m5_bridge (0: OFF, 1: ON)", FCVAR_NOTIFY);
    g_cvWarpInterval = CreateConVar("sm_lastboss_warp_interval", "35.0", "Fatal Mirror interval for all forms", FCVAR_NOTIFY);
}

// ============================================================================
// Initialization Functions
// ============================================================================

void PrecacheResources() {
    // Precache models
    PrecacheModel(MODEL_PROPANE, true);
    PrecacheModel(MODEL_GASCAN, true);

    // Precache sounds
    PrecacheSound(SOUND_EXPLOSION, true);
    PrecacheSound(SOUND_SPAWN, true);
    PrecacheSound(SOUND_BURN_CLAW, true);
    PrecacheSound(SOUND_GRAVITY_CLAW, true);
    PrecacheSound(SOUND_DREAD_CLAW, true);
    PrecacheSound(SOUND_EARTHQUAKE, true);
    PrecacheSound(SOUND_STEEL, true);
    PrecacheSound(SOUND_FORM_CHANGE, true);
    PrecacheSound(SOUND_HOWL, true);
    PrecacheSound(SOUND_WARP, true);

    // Precache particles
    PrecacheParticle(PARTICLE_SPAWN);
    PrecacheParticle(PARTICLE_DEATH);
    PrecacheParticle(PARTICLE_FORM_THREE);
    PrecacheParticle(PARTICLE_FORM_FOUR);
    PrecacheParticle(PARTICLE_WARP);
}

void ResetPluginData() {
    g_iBossFlag = STATE_OFF;
    g_iLastFlag = STATE_OFF;
    g_iBossClient = FORM_DEAD;
    g_iPreviousForm = FORM_DEAD;
    g_iWaveCount = 0;
    SetConVarInt(FindConVar("z_tank_throw_force"), g_iDefaultTankForce, true, true);
}

public void OnMapStart() {
    PrecacheResources();
    ResetPluginData();
}

public void OnMapEnd() {
    ResetPluginData();
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    ResetPluginData();
}

public void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
    g_iBossFlag = STATE_ON;
    g_iLastFlag = STATE_OFF;

    // Handle map-specific exceptions
    char currentMap[64];
    GetCurrentMap(currentMap, sizeof(currentMap));
    if (StrEqual(currentMap, "c1m4_atrium") || StrEqual(currentMap, "c5m5_bridge")) {
        g_iWaveCount = 2;
    } else {
        g_iWaveCount = 1;
    }
}

public void Event_FinaleLast(Event event, const char[] name, bool dontBroadcast) {
    g_iLastFlag = STATE_ON;
}

// ============================================================================
// Tank Spawn and Death Events
// ============================================================================

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
    // Handle map-specific exceptions
    char currentMap[64];
    GetCurrentMap(currentMap, sizeof(currentMap));
    if (StrEqual(currentMap, "c1m4_atrium") || StrEqual(currentMap, "c5m5_bridge")) {
        g_iBossFlag = STATE_ON;
    }

    // Check if a boss already exists
    if (g_iBossClient != FORM_DEAD) {
        return;
    }

    // Check wave count for second tank spawning
    if (g_iWaveCount < 2 && g_cvEnablePlugin.IntValue == 3) {
        return;
    }

    // Determine if the Tank should be a Last Boss
    if ((g_iBossFlag && g_cvEnablePlugin.IntValue == 1) ||
        (g_cvEnablePlugin.IntValue == 2) ||
        (g_iBossFlag && g_cvEnablePlugin.IntValue == 3)) {
        int client = GetClientOfUserId(event.GetInt("userid"));
        if (!IsValidClient(client) || !IsClientInGame(client)) {
            return;
        }

        // Set boss health and start update timer
        CreateTimer(0.3, Timer_SetTankHealth, client);
        if (g_hTimerUpdate != null) {
            CloseHandle(g_hTimerUpdate);
            g_hTimerUpdate = null;
        }
        g_hTimerUpdate = CreateTimer(1.0, Timer_TankUpdate, _, TIMER_REPEAT);

        // Play spawn sound and display announcement
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                EmitSoundToClient(i, SOUND_SPAWN);
            }
        }
        if (g_cvEnableAnnounce.BoolValue) {
            PrintToChatAll(MESSAGE_SPAWN);
            PrintToChatAll(MESSAGE_SPAWN_HEALTH);
        }
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || !IsClientInGame(client)) {
        return;
    }
    if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZOMBIE_CLASS_TANK) {
        return;
    }
    if (g_iWaveCount < 2 && g_cvEnablePlugin.IntValue == 3) {
        g_iWaveCount++;
        return;
    }

    if ((g_iBossFlag && g_cvEnablePlugin.IntValue == 1) ||
        (g_cvEnablePlugin.IntValue == 2) ||
        (g_iBossFlag && g_cvEnablePlugin.IntValue == 3)) {
        if (g_iBossClient == client) {
            float pos[3];
            GetClientAbsOrigin(g_iBossClient, pos);
            EmitSoundToAll(SOUND_EXPLOSION, g_iBossClient);
            ShowParticle(pos, PARTICLE_DEATH, 5.0);
            CreateExplosion(pos, WEAPON_TYPE_MOLOTOV);
            CreateExplosion(pos, WEAPON_TYPE_EXPLODE);
            g_iBossClient = FORM_DEAD;
            g_iPreviousForm = FORM_DEAD;
        }
    }
}

public Action Timer_SetTankHealth(Handle timer, int client) {
    g_iBossClient = client;
    char currentMap[64];
    GetCurrentMap(currentMap, sizeof(currentMap));

    if (!IsValidClient(g_iBossClient) || !IsClientInGame(g_iBossClient)) {
        return Plugin_Handled;
    }

    // Set health based on map and finale state
    if (g_iLastFlag || (StrEqual(currentMap, "c5m5_bridge") && g_cvForceFormFourC5M5.BoolValue)) {
        SetEntityHealth(g_iBossClient, g_cvHealthFormFour.IntValue);
    } else {
        SetEntityHealth(g_iBossClient, g_cvHealthMax.IntValue);
    }
    return Plugin_Handled;
}

// ============================================================================
// Player Hurt Events and Skills
// ============================================================================

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int target = GetClientOfUserId(event.GetInt("userid"));
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    if (!IsValidClient(g_iBossClient) || !IsClientInGame(g_iBossClient) || g_iBossClient == FORM_DEAD) {
        return;
    }
    if (g_iWaveCount < 2 && g_cvEnablePlugin.IntValue == 3) {
        return;
    }

    if ((g_iBossFlag && g_cvEnablePlugin.IntValue == 1) ||
        (g_cvEnablePlugin.IntValue == 2) ||
        (g_iBossFlag && g_cvEnablePlugin.IntValue == 3)) {
        // Handle Tank Claw attacks
        if (StrEqual(weapon, "tank_claw") && attacker == g_iBossClient) {
            if (g_cvEnableQuake.BoolValue) {
                Skill_EarthQuake(target);
            }
            if (g_cvEnableGravity.BoolValue && g_iPreviousForm == FORM_TWO) {
                Skill_GravityClaw(target);
            }
            if (g_cvEnableDread.BoolValue && g_iPreviousForm == FORM_THREE) {
                Skill_DreadClaw(target);
            }
            if (g_cvEnableBurn.BoolValue && g_iPreviousForm == FORM_FOUR) {
                Skill_BurnClaw(target);
            }
        }

        // Handle Tank Rock attacks
        if (StrEqual(weapon, "tank_rock") && attacker == g_iBossClient) {
            if (g_cvEnableComet.BoolValue) {
                if (g_iPreviousForm == FORM_FOUR) {
                    Skill_CometStrike(target, WEAPON_TYPE_MOLOTOV);
                } else {
                    Skill_CometStrike(target, WEAPON_TYPE_EXPLODE);
                }
            }
        }

        // Handle melee attacks against the Tank
        if (StrEqual(weapon, "melee") && target == g_iBossClient) {
            if (g_cvEnableSteel.BoolValue && g_iPreviousForm == FORM_TWO) {
                EmitSoundToClient(attacker, SOUND_STEEL);
                SetEntityHealth(g_iBossClient, event.GetInt("dmg_health") + event.GetInt("health"));
            }
            if (g_cvEnableGush.BoolValue && g_iPreviousForm == FORM_FOUR) {
                Skill_FlameGush(attacker);
            }
        }
    }
}

void Skill_EarthQuake(int target) {
    if (!IsPlayerIncapacitated(target)) {
        return;
    }

    float bossPos[3], targetPos[3];
    GetClientAbsOrigin(g_iBossClient, bossPos);
    for (int i = 1; i <= MaxClients; i++) {
        if (i == g_iBossClient || !IsValidClient(i) || !IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR) {
            continue;
        }
        GetClientAbsOrigin(i, targetPos);
        if (GetVectorDistance(targetPos, bossPos) < g_cvQuakeRadius.FloatValue) {
            EmitSoundToClient(i, SOUND_EARTHQUAKE);
            ScreenShake(i, 60.0);
            Smash(g_iBossClient, i, g_cvQuakeForce.FloatValue, 1.0, 1.5);
        }
    }
}

void Skill_DreadClaw(int target) {
    g_iVisibility = g_cvDreadRate.IntValue;
    CreateTimer(g_cvDreadInterval.FloatValue, Timer_DreadFade, target);
    EmitSoundToAll(SOUND_DREAD_CLAW, target);
    ScreenFade(target, 0, 0, 0, g_iVisibility, 0, 0);
}

void Skill_GravityClaw(int target) {
    SetEntityGravity(target, 0.3);
    CreateTimer(g_cvGravityInterval.FloatValue, Timer_ResetGravity, target);
    EmitSoundToAll(SOUND_GRAVITY_CLAW, target);
    ScreenFade(target, 0, 0, 100, 80, 4000, 1);
    ScreenShake(target, 30.0);
}

void Skill_BurnClaw(int target) {
    int health = GetClientHealth(target);
    if (health > 0 && !IsPlayerIncapacitated(target)) {
        SetEntityHealth(target, 1);
        SetEntPropFloat(target, Prop_Send, "m_healthBuffer", float(health));
    }
    EmitSoundToAll(SOUND_BURN_CLAW, target);
    ScreenFade(target, 200, 0, 0, 150, 80, 1);
    ScreenShake(target, 50.0);
}

void Skill_CometStrike(int target, int type) {
    float pos[3];
    GetClientAbsOrigin(target, pos);
    if (type == WEAPON_TYPE_MOLOTOV) {
        CreateExplosion(pos, WEAPON_TYPE_EXPLODE);
        CreateExplosion(pos, WEAPON_TYPE_MOLOTOV);
    } else if (type == WEAPON_TYPE_EXPLODE) {
        CreateExplosion(pos, WEAPON_TYPE_EXPLODE);
    }
}

void Skill_FlameGush(int target) {
    float pos[3];
    Skill_BurnClaw(target);
    GetClientAbsOrigin(g_iBossClient, pos);
    CreateExplosion(pos, WEAPON_TYPE_MOLOTOV);
}

void Skill_CallOfAbyss() {
    SetEntityMoveType(g_iBossClient, MOVETYPE_NONE);
    SetEntProp(g_iBossClient, Prop_Data, "m_takedamage", 0, 1);

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidClient(i) || !IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR) {
            continue;
        }
        EmitSoundToClient(i, SOUND_HOWL);
        ScreenShake(i, 20.0);
    }

    if ((g_iPreviousForm == FORM_FOUR && g_cvEnableAbyss.IntValue == 1) ||
        g_cvEnableAbyss.IntValue == 2) {
        TriggerPanicEvent();
    }

    CreateTimer(5.0, Timer_ResetHowl);
}

// ============================================================================
// Tank Update and Form Management
// ============================================================================

public Action Timer_TankUpdate(Handle timer) {
    if (!IsValidClient(g_iBossClient) || !IsClientInGame(g_iBossClient) || g_iBossClient == FORM_DEAD) {
        return Plugin_Handled;
    }
    if (g_iWaveCount < 2 && g_cvEnablePlugin.IntValue == 3) {
        return Plugin_Handled;
    }

    int health = GetClientHealth(g_iBossClient);
    if (health > g_cvHealthFormTwo.IntValue) {
        if (g_iPreviousForm != FORM_ONE) {
            SetFormParameters(FORM_ONE);
        }
    } else if (g_cvHealthFormTwo.IntValue >= health && health > g_cvHealthFormThree.IntValue) {
        if (g_iPreviousForm != FORM_TWO) {
            SetFormParameters(FORM_TWO);
        }
    } else if (g_cvHealthFormThree.IntValue >= health && health > g_cvHealthFormFour.IntValue) {
        ExtinguishEntity(g_iBossClient);
        if (g_iPreviousForm != FORM_THREE) {
            SetFormParameters(FORM_THREE);
        }
    } else if (g_cvHealthFormFour.IntValue >= health && health > 0) {
        if (g_iPreviousForm != FORM_FOUR) {
            SetFormParameters(FORM_FOUR);
        }
    }
    return Plugin_Continue;
}

void SetFormParameters(int nextForm) {
    int force;
    float speed;
    char color[32];
    g_iPreviousForm = nextForm;

    if (nextForm != FORM_ONE) {
        if (g_cvEnableAbyss.BoolValue) {
            Skill_CallOfAbyss();
        }
        ExtinguishEntity(g_iBossClient);
        AttachParticle(g_iBossClient, PARTICLE_SPAWN);
        for (int i = 1; i <= MaxClients; i++) {
            if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR) {
                continue;
            }
            EmitSoundToClient(i, SOUND_FORM_CHANGE);
            ScreenFade(i, 200, 200, 255, 255, 100, 1);
        }
    }

    switch (nextForm) {
        case FORM_ONE: {
            force = g_cvForceFormOne.IntValue;
            speed = g_cvSpeedFormOne.FloatValue;
            g_cvColorFormOne.GetString(color, sizeof(color));
            if (g_cvEnableWarp.BoolValue) {
                CreateTimer(3.0, Timer_GetSurvivorPosition, _, TIMER_REPEAT);
                CreateTimer(g_cvWarpInterval.FloatValue, Timer_FatalMirror, _, TIMER_REPEAT);
            }
        }
        case FORM_TWO: {
            if (g_cvEnableAnnounce.BoolValue) {
                PrintToChatAll(MESSAGE_FORM_TWO);
            }
            force = g_cvForceFormTwo.IntValue;
            speed = g_cvSpeedFormTwo.FloatValue;
            g_cvColorFormTwo.GetString(color, sizeof(color));
            SetEntityGravity(g_iBossClient, g_cvWeightFormTwo.FloatValue);
        }
        case FORM_THREE: {
            if (g_cvEnableAnnounce.BoolValue) {
                PrintToChatAll(MESSAGE_FORM_THREE);
            }
            force = g_cvForceFormThree.IntValue;
            speed = g_cvSpeedFormThree.FloatValue;
            g_cvColorFormThree.GetString(color, sizeof(color));
            SetEntityGravity(g_iBossClient, 1.0);
            CreateTimer(0.8, Timer_AttachParticle, _, TIMER_REPEAT);
            if (g_cvEnableStealth.BoolValue) {
                CreateTimer(g_cvStealthIntervalFormThree.FloatValue, Timer_Stealth);
            }
        }
        case FORM_FOUR: {
            if (g_cvEnableAnnounce.BoolValue) {
                PrintToChatAll(MESSAGE_FORM_FOUR);
            }
            SetEntityRenderMode(g_iBossClient, RENDER_TRANSCOLOR);
            SetEntityRenderColor(g_iBossClient, _, _, _, 255);
            force = g_cvForceFormFour.IntValue;
            speed = g_cvSpeedFormFour.FloatValue;
            g_cvColorFormFour.GetString(color, sizeof(color));
            SetEntityGravity(g_iBossClient, 1.0);
            IgniteEntity(g_iBossClient, 9999.9);
            if (g_cvEnableJump.BoolValue) {
                CreateTimer(g_cvJumpIntervalFormFour.FloatValue, Timer_Jump, _, TIMER_REPEAT);
            }
        }
    }

    SetConVarInt(FindConVar("z_tank_throw_force"), force, true, true);
    SetEntPropFloat(g_iBossClient, Prop_Send, "m_flLaggedMovementValue", speed);
    SetEntityRenderMode(g_iBossClient, RENDER_NORMAL);
    DispatchKeyValue(g_iBossClient, "rendercolor", color);
}

// ============================================================================
// Timer Callbacks
// ============================================================================

public Action Timer_AttachParticle(Handle timer) {
    if (g_iPreviousForm == FORM_THREE) {
        AttachParticle(g_iBossClient, PARTICLE_FORM_THREE);
    } else if (g_iPreviousForm == FORM_FOUR) {
        AttachParticle(g_iBossClient, PARTICLE_FORM_FOUR);
    } else {
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public Action Timer_ResetGravity(Handle timer, int target) {
    SetEntityGravity(target, 1.0);
    return Plugin_Handled;
}

public Action Timer_Jump(Handle timer) {
    if (g_iPreviousForm == FORM_FOUR && g_iBossClient != FORM_DEAD) {
        AddVelocity(g_iBossClient, g_cvJumpHeightFormFour.FloatValue);
    } else {
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public Action Timer_Stealth(Handle timer) {
    if (g_iPreviousForm == FORM_THREE && g_iBossClient != FORM_DEAD) {
        g_iAlphaRate = 255;
        FadeEntity(g_iBossClient);
    }
    return Plugin_Handled;
}

public Action Timer_DreadFade(Handle timer, int target) {
    g_iVisibility -= 8;
    if (g_iVisibility < 0) {
        g_iVisibility = 0;
    }
    ScreenFade(target, 0, 0, 0, g_iVisibility, 0, 1);
    if (g_iVisibility <= 0) {
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public Action Timer_ResetHowl(Handle timer) {
    if (g_iBossClient != FORM_DEAD) {
        SetEntityMoveType(g_iBossClient, MOVETYPE_WALK);
        SetEntProp(g_iBossClient, Prop_Data, "m_takedamage", 2, 1);
    }
    return Plugin_Handled;
}

public Action Timer_Warp(Handle timer) {
    if (!IsValidClient(g_iBossClient) || !IsClientInGame(g_iBossClient) || g_iBossClient == FORM_DEAD) {
        return Plugin_Stop;
    }

    float pos[3];
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidClient(i) || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SURVIVOR) {
            continue;
        }
        EmitSoundToClient(i, SOUND_WARP);
    }
    GetClientAbsOrigin(g_iBossClient, pos);
    ShowParticle(pos, PARTICLE_WARP, 2.0);
    TeleportEntity(g_iBossClient, g_fTeleportPosition, NULL_VECTOR, NULL_VECTOR);
    ShowParticle(g_fTeleportPosition, PARTICLE_WARP, 2.0);
    SetEntityMoveType(g_iBossClient, MOVETYPE_WALK);
    SetEntProp(g_iBossClient, Prop_Data, "m_takedamage", 2, 1);
    return Plugin_Handled;
}

public Action Timer_GetSurvivorPosition(Handle timer) {
    if (!IsValidClient(g_iBossClient) || !IsClientInGame(g_iBossClient) || g_iBossClient == FORM_DEAD) {
        return Plugin_Stop;
    }

    int count = 0;
    int[] aliveSurvivors = new int[MaxClients + 1];
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidClient(i) || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SURVIVOR) {
            continue;
        }
        aliveSurvivors[count] = i;
        count++;
    }
    if (count == 0) {
        return Plugin_Continue;
    }
    int randomSurvivor = aliveSurvivors[GetRandomInt(0, count - 1)];
    GetClientAbsOrigin(randomSurvivor, g_fTeleportPosition);
    return Plugin_Continue;
}

public Action Timer_FatalMirror(Handle timer) {
    if (!IsValidClient(g_iBossClient) || !IsClientInGame(g_iBossClient) || g_iBossClient == FORM_DEAD) {
        return Plugin_Stop;
    }
    SetEntityMoveType(g_iBossClient, MOVETYPE_NONE);
    SetEntProp(g_iBossClient, Prop_Data, "m_takedamage", 0, 1);
    CreateTimer(1.5, Timer_Warp);
    return Plugin_Continue;
}

// ============================================================================
// Utility Functions
// ============================================================================

void FadeEntity(int entity) {
    if (!IsValidEntity(entity)) {
        return;
    }
    CreateTimer(0.1, Timer_FadeOut, entity, TIMER_REPEAT);
    SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
}

public Action Timer_FadeOut(Handle timer, int entity) {
    if (!IsValidEntity(entity) || g_iPreviousForm != FORM_THREE) {
        return Plugin_Stop;
    }
    g_iAlphaRate -= 2;
    if (g_iAlphaRate < 0) {
        g_iAlphaRate = 0;
    }
    SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
    SetEntityRenderColor(entity, 80, 80, 255, g_iAlphaRate);
    if (g_iAlphaRate <= 0) {
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

void AddVelocity(int client, float zSpeed) {
    if (g_iVelocityOffset == -1) {
        return;
    }
    float vecVelocity[3];
    GetEntDataVector(client, g_iVelocityOffset, vecVelocity);
    vecVelocity[2] += zSpeed;
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vecVelocity);
}

void CreateExplosion(float pos[3], int type) {
    int entity = CreateEntityByName("prop_physics");
    if (!IsValidEntity(entity)) {
        return;
    }
    pos[2] += 10.0;
    DispatchKeyValue(entity, "model", type == WEAPON_TYPE_MOLOTOV ? MODEL_GASCAN : MODEL_PROPANE);
    DispatchSpawn(entity);
    SetEntData(entity, GetEntSendPropOffs(entity, "m_CollisionGroup"), 1, 1, true);
    TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(entity, "break");
}

void Smash(int client, int target, float power, float powHor, float powVec) {
    float headingVector[3], aimVector[3];
    GetClientEyeAngles(client, headingVector);
    aimVector[0] = Cosine(DegToRad(headingVector[1])) * power * powHor;
    aimVector[1] = Sine(DegToRad(headingVector[1])) * power * powHor;

    float current[3], resulting[3];
    GetEntPropVector(target, Prop_Data, "m_vecVelocity", current);
    resulting[0] = current[0] + aimVector[0];
    resulting[1] = current[1] + aimVector[1];
    resulting[2] = power * powVec;
    TeleportEntity(target, NULL_VECTOR, NULL_VECTOR, resulting);
}

void ScreenFade(int target, int red, int green, int blue, int alpha, int duration, int type) {
    Handle msg = StartMessageOne("Fade", target);
    BfWriteShort(msg, 500);
    BfWriteShort(msg, duration);
    BfWriteShort(msg, type == 0 ? (0x0002 | 0x0008) : (0x0001 | 0x0010));
    BfWriteByte(msg, red);
    BfWriteByte(msg, green);
    BfWriteByte(msg, blue);
    BfWriteByte(msg, alpha);
    EndMessage();
}

void ScreenShake(int target, float intensity) {
    Handle msg = StartMessageOne("Shake", target);
    BfWriteByte(msg, 0);
    BfWriteFloat(msg, intensity);
    BfWriteFloat(msg, 10.0);
    BfWriteFloat(msg, 3.0);
    EndMessage();
}

void TriggerPanicEvent() {
    int client = GetAnyClient();
    if (client == -1) {
        return;
    }
    int flags = GetCommandFlags("director_force_panic_event");
    SetCommandFlags("director_force_panic_event", flags & ~FCVAR_CHEAT);
    FakeClientCommand(client, "director_force_panic_event");
}

// ============================================================================
// Particle Functions
// ============================================================================

void ShowParticle(float pos[3], const char[] particleName, float time) {
    int particle = CreateEntityByName("info_particle_system");
    if (!IsValidEdict(particle)) {
        return;
    }
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
    DispatchKeyValue(particle, "effect_name", particleName);
    DispatchKeyValue(particle, "targetname", "particle");
    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "start");
    CreateTimer(time, Timer_DeleteParticle, particle);
}

void AttachParticle(int entity, const char[] particleType) {
    char targetName[64];
    int particle = CreateEntityByName("info_particle_system");
    if (!IsValidEdict(particle)) {
        return;
    }
    float pos[3];
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
    GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
    DispatchKeyValue(particle, "targetname", "tf2particle");
    DispatchKeyValue(particle, "parentname", targetName);
    DispatchKeyValue(particle, "effect_name", particleType);
    DispatchSpawn(particle);
    SetVariantString(targetName);
    AcceptEntityInput(particle, "SetParent", particle, particle, 0);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "start");
}

public Action Timer_DeleteParticle(Handle timer, int particle) {
    if (!IsValidEntity(particle)) {
        return Plugin_Handled;
    }
    char className[64];
    GetEdictClassname(particle, className, sizeof(className));
    if (StrEqual(className, "info_particle_system", false)) {
        RemoveEdict(particle);
    }
    return Plugin_Handled;
}

void PrecacheParticle(const char[] particleName) {
    int particle = CreateEntityByName("info_particle_system");
    if (!IsValidEdict(particle)) {
        return;
    }
    DispatchKeyValue(particle, "effect_name", particleName);
    DispatchKeyValue(particle, "targetname", "particle");
    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "start");
    CreateTimer(0.01, Timer_DeleteParticle, particle);
}

// ============================================================================
// Helper Functions
// ============================================================================

bool IsPlayerIncapacitated(int client) {
    return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) != 0;
}

int GetAnyClient() {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && IsClientInGame(i)) {
            return i;
        }
    }
    return -1;
}

bool IsValidClient(int client) {
    return client > 0 && client <= MaxClients;
}
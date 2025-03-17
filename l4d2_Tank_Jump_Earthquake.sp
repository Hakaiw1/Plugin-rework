#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

// === Constants and Definitions ===

#define SOUND_EXPLODE        "animation/APC_Idle_Loop.wav"
#define SOUND_QUAKE          "player/tank/hit/pound_victim_2.wav"
#define SOUND_BOMBARD        "animation/van_inside_hit_wall.wav"

static const char SOUND_GROWLS[][] = {
    "player/tank/voice/growl/tank_climb_01.wav",
    "player/tank/voice/growl/tank_climb_02.wav",
    "player/tank/voice/growl/tank_climb_03.wav",
    "player/tank/voice/growl/tank_climb_04.wav",
    "player/tank/voice/growl/tank_climb_05.wav"
};

#define MODEL_CONCRETE_CHUNK  "models/props_debris/concrete_chunk01a.mdl"
#define SPRITE_LASERBEAM     "sprites/laserbeam.vmt"
#define SPRITE_GLOW          "sprites/glow01.vmt"

static const char EXPLOSION_PARTICLES[][] = {
    "gas_explosion_initialburst_smoke",
    "gas_explosion_chunks_02",
    "aircraft_destroy_fastFireTrail"
};

#define TEAM_INFECTED        3
#define L4D_Z_MULT           1.6

// === ConVars (Configurable Variables) ===

ConVar g_cvTankJumpDamage;
ConVar g_cvTankJumpHeight;
ConVar g_cvTankJumpInterval;
ConVar g_cvTimescaleValue;
ConVar g_cvTimescaleAcceleration;
ConVar g_cvTimescaleRadius;
ConVar g_cvTimescaleDuration;
ConVar g_cvTankRabiesUpForce;
ConVar g_cvTankRabiesFlingForce;

// === Global Variables ===

bool g_bLeft4DeadTwo;
int g_iVelocityOffset = -1;
int g_iBossBeamSprite = -1;
int g_iBossHaloSprite = -1;
Handle g_hTankTimers[MAXPLAYERS + 1];

// Cached ConVar values for performance
float g_fTankJumpDamage;
float g_fTankJumpHeight;
float g_fTankJumpInterval;
float g_fTimescaleValue;
float g_fTimescaleAcceleration;
float g_fTimescaleRadius;
float g_fTimescaleDuration;
float g_fTankRabiesUpForce;
float g_fTankRabiesFlingForce;

// === Plugin Information ===

public Plugin myinfo = {
    name = "[L4D(2)] Tank Jump Earthquake",
    author = "Moon",
    description = "Allows the Tank to jump and knock back players with an earthquake effect.",
    version = "1.2.5",
    url = "https://forums.alliedmods.net/showthread.php?p=2829549#post2829549"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    EngineVersion engine = GetEngineVersion();
    if (engine == Engine_Left4Dead2) {
        g_bLeft4DeadTwo = true;
    } else if (engine != Engine_Left4Dead) {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
        return APLRes_SilentFailure;
    }
    return APLRes_Success;
}

// === Initialization Functions ===

public void OnPluginStart() {
    // Initialize ConVars
    g_cvTankRabiesUpForce = CreateConVar("g_tank_rabies_upforce", "250.0", "Upward force of Tank's knockback");
    g_cvTankRabiesFlingForce = CreateConVar("g_tank_rabies_flingforce", "600.0", "Fling force away from Tank in knockback");
    g_cvTimescaleValue = CreateConVar("g_timescale_value", "1.0", "The desired slow-motion timescale (0.1 to 1.0)");
    g_cvTimescaleAcceleration = CreateConVar("g_timescale_acceleration", "1.0", "Acceleration for the slow-motion effect");
    g_cvTimescaleDuration = CreateConVar("g_timescale_duration", "3.0", "Duration of the slow-motion effect in seconds");
    g_cvTimescaleRadius = CreateConVar("g_timescale_radius", "1000.0", "Radius of the slow-motion effect in units");
    g_cvTankJumpHeight = CreateConVar("g_tank_jumpheight", "900.0", "Jump height of the tank");
    g_cvTankJumpInterval = CreateConVar("g_tank_jumpinterval", "35.0", "Interval between the tank's jumps");
    g_cvTankJumpDamage = CreateConVar("g_tank_jumpdamage", "20.0", "Damage from tank jump for player (should be less than 100)");

    // Hook ConVar changes
    g_cvTimescaleValue.AddChangeHook(ConVarChanged_Cvars);
    g_cvTimescaleAcceleration.AddChangeHook(ConVarChanged_Cvars);
    g_cvTankRabiesUpForce.AddChangeHook(ConVarChanged_Cvars);
    g_cvTankRabiesFlingForce.AddChangeHook(ConVarChanged_Cvars);
    g_cvTimescaleDuration.AddChangeHook(ConVarChanged_Cvars);
    g_cvTimescaleRadius.AddChangeHook(ConVarChanged_Cvars);
    g_cvTankJumpHeight.AddChangeHook(ConVarChanged_Cvars);
    g_cvTankJumpInterval.AddChangeHook(ConVarChanged_Cvars);
    g_cvTankJumpDamage.AddChangeHook(ConVarChanged_Cvars);

    // Hook game events
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);

    // Retrieve velocity offset for teleporting entities
    g_iVelocityOffset = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
    if (g_iVelocityOffset == -1) {
        LogError("Could not find offset for CBasePlayer::m_vecVelocity[0]");
    }

    // Execute configuration file
    AutoExecConfig(true, "l4d2_tank_jump_earthquake");

    // Cache ConVar values
    GetCvars();
}

public void OnConfigsExecuted() {
    GetCvars();
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue) {
    GetCvars();
}

void GetCvars() {
    g_fTimescaleValue = g_cvTimescaleValue.FloatValue;
    g_fTimescaleAcceleration = g_cvTimescaleAcceleration.FloatValue;
    g_fTankRabiesUpForce = g_cvTankRabiesUpForce.FloatValue;
    g_fTankRabiesFlingForce = g_cvTankRabiesFlingForce.FloatValue;
    g_fTimescaleDuration = g_cvTimescaleDuration.FloatValue;
    g_fTimescaleRadius = g_cvTimescaleRadius.FloatValue;
    g_fTankJumpHeight = g_cvTankJumpHeight.FloatValue;
    g_fTankJumpInterval = g_cvTankJumpInterval.FloatValue;
    g_fTankJumpDamage = g_cvTankJumpDamage.FloatValue;
}

// === Map and Precache Handling ===

public void OnMapStart() {
    PrecacheModel(MODEL_CONCRETE_CHUNK, true);
    g_iBossBeamSprite = PrecacheModel(SPRITE_LASERBEAM, true);
    g_iBossHaloSprite = PrecacheModel(SPRITE_GLOW, true);

    for (int i = 0; i < sizeof(EXPLOSION_PARTICLES); i++) {
        PrecacheParticle(EXPLOSION_PARTICLES[i]);
    }

    PrecacheSound(SOUND_BOMBARD, true);
    PrecacheSound(SOUND_EXPLODE, true);
    for (int i = 0; i < sizeof(SOUND_GROWLS); i++) {
        PrecacheSound(SOUND_GROWLS[i], true);
    }
}

public void OnMapEnd() {
    ClearAllTankTimers();
}

// === Event Handlers ===

void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidTank(client)) {
        return;
    }

    delete g_hTankTimers[client];
    g_hTankTimers[client] = CreateTimer(g_fTankJumpInterval, Timer_TankJump, client, TIMER_REPEAT);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidTank(client)) {
        return;
    }

    delete g_hTankTimers[client];
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    OnMapEnd();
}

// === Tank Jump Logic ===

public Action Timer_TankJump(Handle timer, int client) {
    if (!IsValidTank(client)) {
        g_hTankTimers[client] = null;
        return Plugin_Stop;
    }

    // Apply jump velocity and effects
    AddVelocity(client, g_fTankJumpHeight);
    SpawnEffect(client, EXPLOSION_PARTICLES[2]);

    // Emit random growl sound to nearby survivors
    for (int i = 1; i <= MaxClients; i++) {
        if (IsValidClient(i) && GetClientTeam(i) == 2) {
            EmitSoundToClient(i, SOUND_GROWLS[GetRandomInt(0, sizeof(SOUND_GROWLS) - 1)]);
        }
    }

    // Monitor Tank landing
    CreateTimer(0.1, Timer_CheckTankLanding, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

void AddVelocity(int client, float jumpHeight) {
    if (g_iVelocityOffset == -1) {
        return;
    }

    float velocity[3];
    GetEntDataVector(client, g_iVelocityOffset, velocity);
    velocity[2] += jumpHeight;
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
}

public Action Timer_CheckTankLanding(Handle timer, int client) {
    if (!IsValidTank(client) || !IsClientOnGround(client)) {
        return Plugin_Continue;
    }

    float tankOrigin[3];
    GetClientAbsOrigin(client, tankOrigin);

    // Apply effects and damage
    CreateMeteorRocks(tankOrigin, client);
    CreateSlowMotion(tankOrigin);
    ApplyAreaDamage(tankOrigin, client, g_fTimescaleRadius * g_fTimescaleRadius, g_fTankJumpDamage);

    return Plugin_Stop;
}

// === Area Effects ===

void ApplyAreaDamage(float tankOrigin[3], int attacker, float radiusSq, float damage) {
    float adjustedTankOrigin[3];
    adjustedTankOrigin = tankOrigin;
    adjustedTankOrigin[2] += 20.0; // Adjust wave height

    TE_SetupBeamRingPoint(adjustedTankOrigin, 10.0, 2000.0, g_iBossBeamSprite, g_iBossHaloSprite, 0, 50, 1.0, 88.0, 3.0, {255, 255, 255, 50}, 1000, 0);
    TE_SendToAll();

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidClient(i) || GetClientTeam(i) != 2) {
            continue;
        }

        float victimOrigin[3];
        GetClientAbsOrigin(i, victimOrigin);

        float distanceSq = GetVectorDistanceSq(tankOrigin, victimOrigin);
        if (distanceSq > radiusSq) {
            continue;
        }

        // Apply damage and effects
        SDKHooks_TakeDamage(i, attacker, attacker, damage, DMG_CLUB);
        ScreenShake(i, 60.0);
        EmitSoundToClient(i, SOUND_QUAKE);

        // Apply knockback
        float flingDirection[3];
        MakeVectorFromPoints(tankOrigin, victimOrigin, flingDirection);
        NormalizeVector(flingDirection, flingDirection);
        ScaleVector(flingDirection, g_fTankRabiesFlingForce);
        flingDirection[2] += g_fTankRabiesUpForce;

        if (!g_bLeft4DeadTwo) {
            flingDirection[2] *= L4D_Z_MULT;
            TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, flingDirection);
        } else {
            L4D2_CTerrorPlayer_Fling(i, attacker, flingDirection);
        }
    }
}

// === Effects and Particles ===

void CreateMeteorRocks(float tankOrigin[3], int client) {
    for (int i = 0; i < 2; i++) {
        float randomOffset[3];
        randomOffset[0] = tankOrigin[0] + GetRandomFloat(-100.0, 100.0);
        randomOffset[1] = tankOrigin[1] + GetRandomFloat(-100.0, 100.0);
        randomOffset[2] = tankOrigin[2];

        CreateRock(randomOffset);
        CreateParticles(tankOrigin);
        EmitSoundToAll(SOUND_EXPLODE, client);
    }
}

void CreateRock(float position[3]) {
    int rock = CreateEntityByName("prop_dynamic");
    if (rock == -1) {
        return;
    }

    SetEntityModel(rock, MODEL_CONCRETE_CHUNK);
    DispatchSpawn(rock);

    float angles[3];
    angles[0] = GetRandomFloat(0.0, 360.0);
    angles[1] = GetRandomFloat(0.0, 360.0);
    angles[2] = GetRandomFloat(0.0, 360.0);
    TeleportEntity(rock, position, angles, NULL_VECTOR);

    CreateTimer(5.0, Timer_DeleteEntity, EntIndexToEntRef(rock), TIMER_FLAG_NO_MAPCHANGE);
}

void CreateSlowMotion(float origin[3]) {
    int timescale = CreateEntityByName("func_timescale");
    if (timescale == -1) {
        return;
    }

    DispatchKeyValueFloat(timescale, "desiredTimescale", g_fTimescaleValue);
    DispatchKeyValueFloat(timescale, "acceleration", g_fTimescaleAcceleration);
    DispatchKeyValueFloat(timescale, "minBlendRate", 1.0);
    DispatchKeyValueFloat(timescale, "blendDeltaMultiplier", 2.0);
    DispatchKeyValueVector(timescale, "origin", origin);
    DispatchSpawn(timescale);
    AcceptEntityInput(timescale, "Start");

    CreateTimer(g_fTimescaleDuration, Timer_ResetTimescale, EntIndexToEntRef(timescale), TIMER_FLAG_NO_MAPCHANGE);
}

void CreateParticles(float position[3]) {
    for (int i = 0; i < sizeof(EXPLOSION_PARTICLES); i++) {
        int particle = CreateEntityByName("info_particle_system");
        if (particle == -1) {
            continue;
        }

        DispatchKeyValue(particle, "effect_name", EXPLOSION_PARTICLES[i]);
        DispatchSpawn(particle);
        ActivateEntity(particle);
        TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);
        AcceptEntityInput(particle, "Start");

        CreateTimer(3.0, Timer_DeleteEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
    }
}

void PrecacheParticle(const char[] effectName) {
    static int table = INVALID_STRING_TABLE;
    if (table == INVALID_STRING_TABLE) {
        table = FindStringTable("ParticleEffectNames");
    }

    if (FindStringIndex(table, effectName) == INVALID_STRING_INDEX) {
        bool save = LockStringTables(false);
        AddToStringTable(table, effectName);
        LockStringTables(save);
    }
}

void ScreenShake(int target, float intensity) {
    Handle msg = StartMessageOne("Shake", target);
    BfWriteByte(msg, 0);
    BfWriteFloat(msg, intensity);
    BfWriteFloat(msg, 10.0);
    BfWriteFloat(msg, 3.0);
    EndMessage();
}

void SpawnEffect(int client, const char[] particleName) {
    float position[3];
    GetClientEyePosition(client, position);

    int entity = CreateEntityByName("info_particle_system");
    if (entity == -1) {
        return;
    }

    DispatchKeyValue(entity, "effect_name", particleName);
    DispatchKeyValueVector(entity, "origin", position);
    DispatchSpawn(entity);

    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetParent", client);

    ActivateEntity(entity);
    AcceptEntityInput(entity, "Start");

    SetVariantString("OnUser1 !self:kill::5.0:1");
    AcceptEntityInput(entity, "AddOutput");
    AcceptEntityInput(entity, "FireUser1");
}

// === Cleanup and Utility Functions ===

public Action Timer_ResetTimescale(Handle timer, int entRef) {
    int timescale = EntRefToEntIndex(entRef);
    if (timescale == INVALID_ENT_REFERENCE || !IsValidEntity(timescale)) {
        return Plugin_Continue;
    }

    DispatchKeyValueFloat(timescale, "desiredTimescale", 1.0);
    DispatchKeyValueFloat(timescale, "acceleration", 2.0);
    AcceptEntityInput(timescale, "Start");
    AcceptEntityInput(timescale, "Stop");
    return Plugin_Continue;
}

public Action Timer_DeleteEntity(Handle timer, int entRef) {
    int entity = EntRefToEntIndex(entRef);
    if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity)) {
        AcceptEntityInput(entity, "Kill");
    }
    return Plugin_Continue;
}

void ClearAllTankTimers() {
    for (int i = 1; i <= MaxClients; i++) {
        delete g_hTankTimers[i];
    }
}

// === Validation Functions ===

bool IsValidClient(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}

bool IsClientOnGround(int client) {
    return IsValidClient(client) && GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != -1;
}

bool IsValidTank(int client) {
    if (!IsValidClient(client) || GetClientTeam(client) != TEAM_INFECTED) {
        return false;
    }

    int zombieClass = g_bLeft4DeadTwo ? 8 : 5;
    return GetEntProp(client, Prop_Send, "m_zombieClass") == zombieClass;
}

float GetVectorDistanceSq(const float vec1[3], const float vec2[3]) {
    float dx = vec1[0] - vec2[0];
    float dy = vec1[1] - vec2[1];
    float dz = vec1[2] - vec2[2];
    return dx * dx + dy * dy + dz * dz;
}
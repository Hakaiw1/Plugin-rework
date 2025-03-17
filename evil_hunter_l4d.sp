#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdktools_functions>

// === Constants and Definitions ===

#define PLUGIN_VERSION      "1.5"
#define CVAR_FLAGS          (FCVAR_NOTIFY | FCVAR_SPONLY)

enum HunterAction {
    Action_None = 0,
    Action_StopPounce = 1,
    Action_Move = 2,
    Action_Attack = 3
}

// === ConVars (Configurable Variables) ===

ConVar g_cvPluginEnabled;
ConVar g_cvEvilHunterChance;

// === Global Variables ===

bool g_bHooked = false;
float g_fEvilHunterChance = 0.0;

// Arrays to store hunter state
int g_iHunterVictim[MAXPLAYERS + 1];
int g_iHunterAttacker[MAXPLAYERS + 1];
HunterAction g_iHunterAction[MAXPLAYERS + 1];
int g_iHunterTick[MAXPLAYERS + 1];
float g_fHunterActionTime[MAXPLAYERS + 1];
float g_fHunterAttackDir[MAXPLAYERS + 1][3];

// === Plugin Information ===

public Plugin myinfo = {
    name = "Evil Hunter",
    author = "Pan XiaoHai",
    description = "Modifies hunter behavior to change targets based on chance and helper proximity.",
    version = PLUGIN_VERSION,
    url = "https://forums.alliedmods.net/showthread.php?t=168566"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    EngineVersion engine = GetEngineVersion();
    if (engine != Engine_Left4Dead && engine != Engine_Left4Dead2) {
        strcopy(error, err_max, "This plugin only runs in \"Left 4 Dead(2)\" game");
        return APLRes_SilentFailure;
    }
    return APLRes_Success;
}

// === Initialization Functions ===

public void OnPluginStart() {
    // Initialize ConVars
    CreateConVar("l4d_evil_hunter_version", PLUGIN_VERSION, "Evil Hunter plugin version", CVAR_FLAGS | FCVAR_DONTRECORD);
    g_cvPluginEnabled = CreateConVar("l4d_evil_hunter_on", "1", "Enable/Disable plugin", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_cvEvilHunterChance = CreateConVar("l4d_evil_hunter_chance", "100.0", "Chance of hunter changing target", CVAR_FLAGS);

    // Hook ConVar changes
    g_cvPluginEnabled.AddChangeHook(ConVar_PluginEnabledChanged);
    g_cvEvilHunterChance.AddChangeHook(ConVar_EvilHunterChanceChanged);

    // Execute configuration file
    AutoExecConfig(true, "evil_hunter_l4d");

    // Cache ConVar values
    UpdateConVarCache();
}

public void OnConfigsExecuted() {
    UpdatePluginState();
}

void ConVar_PluginEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    UpdatePluginState();
}

void ConVar_EvilHunterChanceChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    g_fEvilHunterChance = g_cvEvilHunterChance.FloatValue;
}

void UpdateConVarCache() {
    g_fEvilHunterChance = g_cvEvilHunterChance.FloatValue;
}

// === Plugin State Management ===

void UpdatePluginState() {
    bool pluginEnabled = g_cvPluginEnabled.BoolValue;
    if (pluginEnabled && !g_bHooked) {
        g_bHooked = true;
        UpdateConVarCache();
        HookEvents();
    } else if (!pluginEnabled && g_bHooked) {
        g_bHooked = false;
        UnhookEvents();
    }
}

void HookEvents() {
    HookEvent("lunge_pounce", Event_LungePounce);
    HookEvent("pounce_end", Event_PounceEnd);
    HookEvent("round_start", Event_ResetState);
    HookEvent("round_end", Event_ResetState);
    HookEvent("finale_win", Event_ResetState);
    HookEvent("mission_lost", Event_ResetState);
    HookEvent("map_transition", Event_ResetState);
}

void UnhookEvents() {
    UnhookEvent("lunge_pounce", Event_LungePounce);
    UnhookEvent("pounce_end", Event_PounceEnd);
    UnhookEvent("round_start", Event_ResetState);
    UnhookEvent("round_end", Event_ResetState);
    UnhookEvent("finale_win", Event_ResetState);
    UnhookEvent("mission_lost", Event_ResetState);
    UnhookEvent("map_transition", Event_ResetState);
}

// === Map and State Reset ===

public void OnMapStart() {
    ResetAllState();
}

void Event_ResetState(Event event, const char[] name, bool dontBroadcast) {
    ResetAllState();
}

void ResetAllState() {
    for (int i = 0; i <= MaxClients; i++) {
        g_iHunterVictim[i] = 0;
        g_iHunterAttacker[i] = 0;
        g_iHunterAction[i] = Action_None;
        g_iHunterTick[i] = 0;
        g_fHunterActionTime[i] = 0.0;
        g_fHunterAttackDir[i] = {0.0, 0.0, 0.0};
    }
}

// === Event Handlers ===

void Event_LungePounce(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("victim"));
    int attacker = GetClientOfUserId(event.GetInt("userid"));

    if (GetRandomFloat(0.0, 100.0) >= g_fEvilHunterChance) {
        return;
    }

    if (!IsValidHunter(attacker) || !IsValidSurvivor(victim) || !IsFakeClient(attacker)) {
        return;
    }

    g_iHunterVictim[attacker] = victim;
    g_iHunterAttacker[victim] = attacker;
    g_iHunterAction[attacker] = Action_None;
    g_fHunterActionTime[attacker] = GetEngineTime();
    g_iHunterTick[attacker] = 0;
    SetEntityMoveType(attacker, MOVETYPE_WALK);
}

void Event_PounceEnd(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (!IsValidSurvivor(victim)) {
        return;
    }

    int attacker = g_iHunterAttacker[victim];
    if (!IsValidHunter(attacker)) {
        return;
    }

    g_iHunterVictim[attacker] = 0;
    g_iHunterAttacker[victim] = 0;
    SetEntityMoveType(attacker, MOVETYPE_WALK);
}

// === Player Input Handling ===

public Action OnPlayerRunCmd(int client, int &buttons) {
    if (!IsValidHunter(client)) {
        return StopHunter(client);
    }

    switch (g_iHunterAction[client]) {
        case Action_StopPounce: {
            float time = GetEngineTime();
            if (time - g_fHunterActionTime[client] > 0.1) {
                g_iHunterAction[client] = Action_Move;
                SetEntityMoveType(client, MOVETYPE_WALK);
                g_fHunterActionTime[client] = time;
                buttons = 0;
                return Plugin_Changed;
            }
            return Plugin_Continue;
        }
        case Action_Move: {
            float time = GetEngineTime();
            g_iHunterAction[client] = Action_Attack;
            g_fHunterActionTime[client] = time;
            g_iHunterTick[client] = 0;
            buttons |= IN_ATTACK | IN_DUCK;
            TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, g_fHunterAttackDir[client]);
            return Plugin_Changed;
        }
        case Action_Attack: {
            float time = GetEngineTime();
            if (time - g_fHunterActionTime[client] > 3.0) {
                g_iHunterAction[client] = Action_None;
            }

            g_iHunterTick[client]++;
            buttons = 0;
            if ((g_iHunterTick[client] % 2) == 0) {
                buttons |= IN_ATTACK;
            } else {
                buttons &= ~IN_ATTACK;
            }
            buttons |= IN_DUCK;
            return Plugin_Changed;
        }
    }

    int victim = g_iHunterVictim[client];
    if (victim == 0 || !IsValidSurvivor(victim)) {
        return StopHunter(client);
    }

    float time = GetEngineTime();
    if (time - g_fHunterActionTime[client] <= 0.2) {
        return Plugin_Continue;
    }

    g_fHunterActionTime[client] = time;
    if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) {
        if (IsHelperComing(client, victim)) {
            g_iHunterAction[client] = Action_StopPounce;
            SetEntityMoveType(client, MOVETYPE_NOCLIP);
        }
    }

    return Plugin_Continue;
}

Action StopHunter(int client) {
    if (IsValidClient(client)) {
        g_iHunterVictim[client] = 0;
        g_iHunterAttacker[client] = 0;
        g_iHunterAction[client] = Action_None;
        g_iHunterTick[client] = 0;
        g_fHunterActionTime[client] = 0.0;
        g_fHunterAttackDir[client] = {0.0, 0.0, 0.0};
        SetEntityMoveType(client, MOVETYPE_WALK);
    }
    return Plugin_Continue;
}

// === Helper Functions ===

bool IsHelperComing(int hunter, int victim) {
    float hunterPos[3], helperPos[3];
    GetClientEyePosition(hunter, hunterPos);

    for (int client = 1; client <= MaxClients; client++) {
        if (!IsValidSurvivor(client) || client == victim || GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) {
            continue;
        }

        GetClientEyePosition(client, helperPos);
        if (GetVectorDistance(hunterPos, helperPos) < 300.0) {
            g_fHunterAttackDir[hunter][0] = GetRandomFloat(-1.0, 1.0);
            g_fHunterAttackDir[hunter][1] = GetRandomFloat(-1.0, 1.0);
            g_fHunterAttackDir[hunter][2] = 0.5;
            NormalizeVector(g_fHunterAttackDir[hunter], g_fHunterAttackDir[hunter]);
            ScaleVector(g_fHunterAttackDir[hunter], 800.0);
            return true;
        }
    }
    return false;
}

// === Validation Functions ===

bool IsValidClient(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}

bool IsValidHunter(int client) {
    return IsValidClient(client) && GetClientTeam(client) == 3 && IsPlayerAlive(client);
}

bool IsValidSurvivor(int client) {
    return IsValidClient(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client);
}
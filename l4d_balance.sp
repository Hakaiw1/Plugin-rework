#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define ZOMBIECLASS_SURVIVOR 9
#define ZOMBIECLASS_SMOKER   1
#define ZOMBIECLASS_BOOMER   2
#define ZOMBIECLASS_HUNTER   3
#define ZOMBIECLASS_SPITTER  4
#define ZOMBIECLASS_JOCKEY   5
#define ZOMBIECLASS_CHARGER  6

// Constants
int ZOMBIECLASS_TANK;
int GameMode;
bool L4D2Version;

// Debug
bool Debug = false;

public Plugin myinfo = {
    name = "Automatic Difficulty Balance based on Intensity",
    author = "Pan Xiaohai",
    description = "Dynamically adjusts game difficulty based on player intensity",
    version = "1.3",
    url = "https://forums.alliedmods.net/showthread.php?t=166950"
};

bool ShowHud[MAXPLAYERS + 1];
int CurrentAverage;
int PlayerIntensity[MAXPLAYERS + 1];
int PlayerTotalIntensity[MAXPLAYERS + 1];
int PlayerTick[MAXPLAYERS + 1];
bool NeedDrawHud = false;
bool HaveTank = false;
int AllTotalIntensity;
int AllTotalTick = 1;
int CiCount;
int SiCount;
int SurvivorCount;
int MobTick;
int MaxSpecial;
int MaxCommon;
int AdustTick;
int DirectorStopTick;
bool DirectorStoped;

// ConVar handles
ConVar l4d_balance_enable;
ConVar l4d_balance_reaction_time;
ConVar l4d_balance_setting_password;
ConVar l4d_balance_include_bot;
ConVar l4d_balance_difficulty_min;
ConVar l4d_balance_difficulty_max;
ConVar l4d_balance_health_increment;
ConVar l4d_balance_health_witch;
ConVar l4d_balance_health_tank;
ConVar l4d_balance_health_hunter;
ConVar l4d_balance_health_smoker;
ConVar l4d_balance_health_boomer;
ConVar l4d_balance_health_charger;
ConVar l4d_balance_health_jockey;
ConVar l4d_balance_health_spitter;
ConVar l4d_balance_health_zombie;
ConVar l4d_balance_limit_special;
ConVar l4d_balance_limit_special_add;
ConVar l4d_balance_limit_common;
ConVar l4d_balance_limit_common_add;

public void OnPluginStart() {
    GameCheck();
    if (GameMode != 1) return; // Only enable for coop/realism modes

    // Initialize ConVars
    l4d_balance_enable = CreateConVar("l4d_balance_enable", "1", "Enable difficulty balance system (0 = disable, 1 = enable)");
    l4d_balance_reaction_time = CreateConVar("l4d_balance_reaction_time", "30", "Reaction time for balance system [10, 60] seconds");
    l4d_balance_difficulty_min = CreateConVar("l4d_balance_difficulty_min", "25", "Minimum difficulty intensity threshold [0, 100]");
    l4d_balance_difficulty_max = CreateConVar("l4d_balance_difficulty_max", "65", "Maximum difficulty intensity threshold [0, 100]");
    l4d_balance_include_bot = CreateConVar("l4d_balance_include_bot", "1", "Include survivor bots in intensity calculations (0 = ignore, 1 = include)");
    l4d_balance_setting_password = CreateConVar("l4d_balance_setting_password", "1234", "Password for setting difficulty");

    l4d_balance_health_increment = CreateConVar("l4d_balance_health_add", "20", "Health increment percentage per extra player [0, 50]");
    l4d_balance_health_tank = CreateConVar("l4d_balance_health_tank", "8000", "Tank's base health");
    l4d_balance_health_witch = CreateConVar("l4d_balance_health_witch", "1000", "Witch's base health");
    l4d_balance_health_hunter = CreateConVar("l4d_balance_health_hunter", "500", "Hunter's base health");
    l4d_balance_health_smoker = CreateConVar("l4d_balance_health_smoker", "500", "Smoker's base health");
    l4d_balance_health_boomer = CreateConVar("l4d_balance_health_boomer", "500", "Boomer's base health");
    l4d_balance_health_charger = CreateConVar("l4d_balance_health_charger", "500", "Charger's base health");
    l4d_balance_health_jockey = CreateConVar("l4d_balance_health_jockey", "500", "Jockey's base health");
    l4d_balance_health_spitter = CreateConVar("l4d_balance_health_spitter", "500", "Spitter's base health");
    l4d_balance_health_zombie = CreateConVar("l4d_balance_health_zombie", "50", "Common infected's base health");

    l4d_balance_limit_special = CreateConVar("l4d_balance_limit_special", "6", "Special infected limit [0, 20]");
    l4d_balance_limit_special_add = CreateConVar("l4d_balance_limit_special_add", "1", "Special infected limit increment per extra player [0, 5]");
    l4d_balance_limit_common = CreateConVar("l4d_balance_limit_common", "30", "Common infected limit [30, 100]");
    l4d_balance_limit_common_add = CreateConVar("l4d_balance_limit_common_add", "5", "Common infected limit increment per extra player [0, 30]");

    AutoExecConfig(true, "l4d_balance");

    // Register commands
    RegConsoleCmd("sm_balance", Command_Balance, "Toggle HUD visibility");
    RegConsoleCmd("sm_difficulty", Command_Difficulty, "Change difficulty with password");
    RegConsoleCmd("sm_dinfo", Command_DInfo, "Display difficulty and health information");

    // Hook events
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("finale_win", Event_MapTransition);
    HookEvent("mission_lost", Event_RoundEnd);
    HookEvent("map_transition", Event_MapTransition);

    ResetAllState();
}

public Action Command_Balance(int client, int args) {
    if (client <= 0) return Plugin_Handled;
    ShowHud[client] = !ShowHud[client];
    return Plugin_Handled;
}

public Action Command_DInfo(int client, int args) {
    if (client <= 0) return Plugin_Handled;

    char msgstr[500];
    Format(msgstr, sizeof(msgstr), "Survivor Count: %d\n", SurvivorCount);
    Format(msgstr, sizeof(msgstr), "%sTank's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_tank.FloatValue), RoundFloat(FindConVar("z_tank_health").FloatValue));
    Format(msgstr, sizeof(msgstr), "%sWitch's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_witch.FloatValue), RoundFloat(FindConVar("z_witch_health").FloatValue));
    Format(msgstr, sizeof(msgstr), "%sZombie's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_zombie.FloatValue), RoundFloat(FindConVar("z_health").FloatValue));
    Format(msgstr, sizeof(msgstr), "%sSmoker's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_smoker.FloatValue), RoundFloat(FindConVar("z_gas_health").FloatValue));
    Format(msgstr, sizeof(msgstr), "%sHunter's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_hunter.FloatValue), RoundFloat(FindConVar("z_hunter_health").FloatValue));
    Format(msgstr, sizeof(msgstr), "%sBoomer's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_boomer.FloatValue), RoundFloat(FindConVar("z_exploding_health").FloatValue));

    if (L4D2Version) {
        Format(msgstr, sizeof(msgstr), "%sCharger's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_charger.FloatValue), RoundFloat(FindConVar("z_charger_health").FloatValue));
        Format(msgstr, sizeof(msgstr), "%sSpitter's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_spitter.FloatValue), RoundFloat(FindConVar("z_spitter_health").FloatValue));
        Format(msgstr, sizeof(msgstr), "%sJockey's Health: %d to %d\n", msgstr, RoundFloat(l4d_balance_health_jockey.FloatValue), RoundFloat(FindConVar("z_jockey_health").FloatValue));
    }

    Format(msgstr, sizeof(msgstr), "\n%sSpecial infected limit: %d to %d\n", msgstr, l4d_balance_limit_special.IntValue, MaxSpecial);
    Format(msgstr, sizeof(msgstr), "%sz_common_limit: %d to %d\n", msgstr, l4d_balance_limit_common.IntValue, RoundFloat(FindConVar("z_common_limit").FloatValue));
    Format(msgstr, sizeof(msgstr), "%sz_background_limit: %d\n", msgstr, RoundFloat(FindConVar("z_background_limit").FloatValue));
    Format(msgstr, sizeof(msgstr), "%sz_mega_mob_size: %d\n", msgstr, RoundFloat(FindConVar("z_mega_mob_size").FloatValue));

    PrintToChat(client, "Please check console output");
    PrintToConsole(client, msgstr);
    return Plugin_Handled;
}

public Action Command_Difficulty(int client, int args) {
    if (client <= 0) return Plugin_Handled;

    char password[20], arg[20];
    l4d_balance_setting_password.GetString(password, sizeof(password));
    GetCmdArg(1, arg, sizeof(arg));

    if (!StrEqual(arg, password)) {
        PrintToChat(client, "Your password is incorrect");
        PrintToChatAll("The current difficulty is %d", l4d_balance_difficulty_min.IntValue);
        return Plugin_Handled;
    }

    GetCmdArg(2, arg, sizeof(arg));
    int difficulty = StringToInt(arg);

    if (difficulty >= 0 && difficulty <= 100) {
        PrintToChatAll("The difficulty changed from %d to %d", l4d_balance_difficulty_min.IntValue, difficulty);
        l4d_balance_difficulty_min.SetInt(difficulty);
    } else {
        PrintToChat(client, "Value must be between 0 and 100");
    }
    return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;
    ShowHud[client] = false;
    PrintToChat(client, "Type !balance to enable HUD");
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;
    ShowHud[client] = true;
    PrintToChat(client, "Type !balance to disable HUD");
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    ResetAllState();
    ConVar z_max_player_zombies = FindConVar("z_max_player_zombies");
    int flags = z_max_player_zombies.Flags;
    z_max_player_zombies.SetBounds(ConVarBound_Upper, false);
    z_max_player_zombies.Flags = flags & ~FCVAR_NOTIFY;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    ResetAllState();
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == 3 && IsFakeClient(i)) {
            KickClient(i);
        }
    }
}

public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
    int totalAverage = AllTotalIntensity / AllTotalTick;
    PrintToServer("\x04[balance] \x01Map Change");
    PrintToServer("\x04[balance] \x01Server intensity average %d", totalAverage);

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && GetClientTeam(i) == 2) {
            PrintToServer("\x04[balance] \x01%N intensity average %d", i, PlayerTotalIntensity[i] / PlayerTick[i]);
        }
    }
    ResetAllState();
}

void ResetAllState() {
    AllTotalIntensity = 0;
    AllTotalTick = 1;
    DirectorStoped = false;
    AdustTick = l4d_balance_reaction_time.IntValue;
    DirectorStopTick = l4d_balance_reaction_time.IntValue;
    CiCount = 0;
    SiCount = 0;
    NeedDrawHud = false;
    MobTick = 0;
    HaveTank = false;
    SurvivorCount = 1;

    for (int i = 1; i <= MaxClients; i++) {
        PlayerIntensity[i] = 0;
        PlayerTotalIntensity[i] = 0;
        PlayerTick[i] = 1;
    }
}

public void OnMapStart() {
    if (GameMode != 1) return;
    CreateTimer(1.0, Timer_UpdatePlayer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.5, Timer_ShowHud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(30.0, Timer_DelayStartAdjust, _, TIMER_FLAG_NO_MAPCHANGE);
    ResetAllState();
}

public Action Timer_UpdatePlayer(Handle timer) {
    int playerCount = 0;
    int currentAverage = 0;
    int infectedCount = 0;
    int difficulty = l4d_balance_difficulty_min.IntValue;
    bool needDrawHud = false;
    bool haveTank = false;
    int survivorCount = 0;
    bool includeBot = l4d_balance_include_bot.BoolValue;

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i)) {
            PlayerIntensity[i] = 0;
            continue;
        }

        if (GetClientTeam(i) == 2) { // Survivors
            bool isBot = IsFakeClient(i);
            if (!includeBot && isBot) continue;

            if (IsPlayerAlive(i)) {
                PlayerIntensity[i] = GetEntProp(i, Prop_Send, "m_clientIntensity");
                PlayerTotalIntensity[i] += PlayerIntensity[i];
                currentAverage += PlayerIntensity[i];
            } else {
                PlayerIntensity[i] = difficulty;
                PlayerTotalIntensity[i] += PlayerIntensity[i];
                currentAverage += PlayerIntensity[i];
            }
            PlayerTick[i]++;
            playerCount++;
            if (ShowHud[i] && !isBot) needDrawHud = true;
            survivorCount++;
        } else if (IsPlayerAlive(i)) { // Infected
            infectedCount++;
            if (IsInfected(i, ZOMBIECLASS_TANK)) haveTank = true;
        }
    }

    SurvivorCount = survivorCount;
    HaveTank = haveTank;
    NeedDrawHud = needDrawHud;
    CurrentAverage = playerCount > 0 ? currentAverage / playerCount : 0;
    AllTotalIntensity += CurrentAverage;
    AllTotalTick++;

    SiCount = infectedCount;
    int reactionTime = l4d_balance_reaction_time.IntValue;

    if (CurrentAverage < difficulty) AdustTick--;
    else AdustTick++;
    AdustTick = Clamp(AdustTick, 0, reactionTime);

    if (HaveTank) AdustTick = reactionTime;

    if (CurrentAverage > l4d_balance_difficulty_max.IntValue) DirectorStopTick--;
    else DirectorStopTick++;
    DirectorStopTick = Clamp(DirectorStopTick, 0, reactionTime);

    if (Debug) {
        int totalAverage = AllTotalIntensity / AllTotalTick;
        PrintToServer("\x04[balance] \x01Current intensity %d, average %d", CurrentAverage, totalAverage);
    }

    return Plugin_Continue;
}

public Action Timer_Adjust(Handle timer) {
    if (!l4d_balance_enable.BoolValue) return Plugin_Continue;

    int siNeed = 0;
    int ciNeed = 0;
    int mobNeed = 0;
    int reactionTime = l4d_balance_reaction_time.IntValue;

    UpdateSettings();

    if (DirectorStopTick == 0) {
        if (!DirectorStoped) PrintToServer("Director Stopped");
        FindConVar("director_no_specials").SetInt(1);
        FindConVar("director_no_mobs").SetInt(1);
        DirectorStoped = true;
    } else {
        if (DirectorStoped) PrintToServer("Director Started");
        FindConVar("director_no_specials").SetInt(0);
        FindConVar("director_no_mobs").SetInt(0);
        DirectorStoped = false;
    }

    CiCount = GetInfectedCount();

    if (AdustTick == 0) {
        FindConVar("z_max_player_zombies").SetInt(32);
        if (SiCount < MaxSpecial) siNeed = 1;
        MobTick += 2;

        if (CiCount < MaxCommon) {
            ciNeed = 0;
            if (MobTick >= reactionTime) mobNeed = 1;
        }

        if (siNeed > 0 || ciNeed > 0 || mobNeed > 0) Z_Spawn(siNeed, ciNeed, mobNeed);
    } else {
        MobTick = 0;
    }

    return Plugin_Continue;
}

void UpdateSettings() {
    float inc = l4d_balance_health_increment.FloatValue / 100.0;
    int survivorCount = SurvivorCount < 4 ? 4 : SurvivorCount;
    inc *= (survivorCount - 4);

    SetConVarFloat(FindConVar("z_health"), l4d_balance_health_zombie.FloatValue * (1.0 + inc));
    SetConVarFloat(FindConVar("z_hunter_health"), l4d_balance_health_hunter.FloatValue * (1.0 + inc));
    SetConVarFloat(FindConVar("z_gas_health"), l4d_balance_health_smoker.FloatValue * (1.0 + inc));
    SetConVarFloat(FindConVar("z_exploding_health"), l4d_balance_health_boomer.FloatValue * (1.0 + inc));

    if (L4D2Version) {
        SetConVarFloat(FindConVar("z_charger_health"), l4d_balance_health_charger.FloatValue * (1.0 + inc));
        SetConVarFloat(FindConVar("z_spitter_health"), l4d_balance_health_spitter.FloatValue * (1.0 + inc));
        SetConVarFloat(FindConVar("z_jockey_health"), l4d_balance_health_jockey.FloatValue * (1.0 + inc));
    }

    SetConVarFloat(FindConVar("z_witch_health"), l4d_balance_health_witch.FloatValue * (1.0 + inc));
    SetConVarFloat(FindConVar("z_tank_health"), l4d_balance_health_tank.FloatValue * (1.0 + inc));

    MaxSpecial = l4d_balance_limit_special.IntValue + l4d_balance_limit_special_add.IntValue * (survivorCount - 4);
    MaxCommon = l4d_balance_limit_common.IntValue + l4d_balance_limit_common_add.IntValue * (survivorCount - 4);

    SetConVarFloat(FindConVar("z_common_limit"), MaxCommon * 1.0);
    SetConVarFloat(FindConVar("z_background_limit"), MaxCommon * 0.5);
    SetConVarFloat(FindConVar("z_mega_mob_size"), MaxCommon * 1.0);
}

public Action Timer_DelayStartAdjust(Handle timer) {
    CreateTimer(2.0, Timer_Adjust, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_ShowHud(Handle timer) {
    if (!NeedDrawHud) return Plugin_Continue;

    Handle pInfHUD = CreatePanel(GetMenuStyleHandle(MenuStyle_Default));
    SetPanelTitle(pInfHUD, "Difficulty Balance System");

    char buffer[65];
    Format(buffer, sizeof(buffer), "Intensity Statistics, Difficulty is (%d - %d)", l4d_balance_difficulty_min.IntValue, l4d_balance_difficulty_max.IntValue);
    DrawPanelItem(pInfHUD, buffer, ITEMDRAW_RAWLINE);
    DrawPanelItem(pInfHUD, " ", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);

    Format(buffer, sizeof(buffer), "Current: %d", CurrentAverage);
    DrawPanelItem(pInfHUD, buffer);

    int totalAverage = AllTotalIntensity / AllTotalTick;
    Format(buffer, sizeof(buffer), "Average: %d", totalAverage);
    DrawPanelItem(pInfHUD, buffer);

    Format(buffer, sizeof(buffer), AdustTick == 0 ? "Increasing difficulty" : "Countdown to increase difficulty: %d", AdustTick);
    DrawPanelItem(pInfHUD, buffer);

    Format(buffer, sizeof(buffer), DirectorStopTick == 0 ? "Decreasing difficulty" : "Countdown to decrease difficulty: %d", DirectorStopTick);
    DrawPanelItem(pInfHUD, buffer);

    DrawPanelItem(pInfHUD, " ", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
    DrawPanelItem(pInfHUD, "Infected", ITEMDRAW_RAWLINE);

    Format(buffer, sizeof(buffer), "Special infected (%d): %d", MaxSpecial, SiCount);
    DrawPanelItem(pInfHUD, buffer);
    Format(buffer, sizeof(buffer), "Common infected (%d): %d", MaxCommon, CiCount);
    DrawPanelItem(pInfHUD, buffer);

    DrawPanelItem(pInfHUD, " ", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);
    DrawPanelItem(pInfHUD, "Survivor Intensity");
    DrawPanelItem(pInfHUD, " ", ITEMDRAW_SPACER | ITEMDRAW_RAWLINE);

    bool includeBot = l4d_balance_include_bot.BoolValue;
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || GetClientTeam(i) == 3 || (!includeBot && IsFakeClient(i))) continue;
        int average = PlayerTotalIntensity[i] / PlayerTick[i];
        Format(buffer, sizeof(buffer), "%N (%d): %d", i, average, PlayerIntensity[i]);
        DrawPanelItem(pInfHUD, buffer, ITEMDRAW_RAWLINE);
    }

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i) || !ShowHud[i]) continue;
        if (GetClientMenu(i) == MenuSource_RawPanel || GetClientMenu(i) == MenuSource_None) {
            SendPanelToClient(pInfHUD, i, Menu_InfHUDPanel, 1);
        }
    }

    CloseHandle(pInfHUD);
    return Plugin_Continue;
}

public void Menu_InfHUDPanel(Handle menu, MenuAction action, int param1, int param2) {}

void Z_Spawn(int siCount, int ciCount, int mob) {
    int bot = CreateFakeClient("Monster");
    if (bot <= 0) return;

    ChangeClientTeam(bot, 3);

    for (int i = 0; i < siCount; i++) {
        int random = GetRandomInt(1, L4D2Version ? 6 : 3);
        switch (random) {
            case 1: SpawnCommand(bot, "z_spawn", "smoker auto");
            case 2: SpawnCommand(bot, "z_spawn", "boomer auto");
            case 3: SpawnCommand(bot, "z_spawn", "hunter auto");
            case 4: SpawnCommand(bot, "z_spawn", "spitter auto");
            case 5: SpawnCommand(bot, "z_spawn", "jockey auto");
            case 6: SpawnCommand(bot, "z_spawn", "charger auto");
        }
    }

    for (int i = 0; i < ciCount; i++) {
        SpawnCommand(bot, "z_spawn", "auto");
    }

    if (mob > 0) {
        SpawnCommand(bot, "z_spawn", "mob");
        MobTick = 0;
    }

    KickClient(bot);
}

void SpawnCommand(int client, const char[] command, const char[] arguments = "") {
    if (client <= 0) return;
    int flags = GetCommandFlags(command);
    SetCommandFlags(command, flags & ~FCVAR_CHEAT);
    FakeClientCommand(client, "%s %s", command, arguments);
    SetCommandFlags(command, flags);
}

int GetInfectedCount() {
    int ent = -1, count = 0;
    while ((ent = FindEntityByClassname(ent, "infected")) != -1) {
        count++;
    }
    return count;
}

void GameCheck() {
    char gameName[16];
    FindConVar("mp_gamemode").GetString(gameName, sizeof(gameName));

    if (StrEqual(gameName, "survival", false)) {
        GameMode = 3;
    } else if (StrEqual(gameName, "versus", false) || StrEqual(gameName, "teamversus", false) ||
               StrEqual(gameName, "scavenge", false) || StrEqual(gameName, "teamscavenge", false)) {
        GameMode = 2;
    } else if (StrEqual(gameName, "coop", false) || StrEqual(gameName, "realism", false)) {
        GameMode = 1;
    } else {
        GameMode = 0;
    }

    GetGameFolderName(gameName, sizeof(gameName));
    if (StrEqual(gameName, "left4dead2", false)) {
        ZOMBIECLASS_TANK = 8;
        L4D2Version = true;
    } else {
        ZOMBIECLASS_TANK = 5;
        L4D2Version = false;
    }
}

bool IsInfected(int client, int type) {
    return GetEntProp(client, Prop_Send, "m_zombieClass") == type;
}

int Clamp(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

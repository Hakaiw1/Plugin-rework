/**
 * Change Log:
 * 1.0.1 (18-March-2025)
 *     - Fixed permanent fade issue by ensuring fade is cleared on ride end and client disconnect.
 * 1.0.0 (19-July-2022)
 *     - Initial release.
 */

#define PLUGIN_NAME                   "[L4D2] Jockey Ride Screen Fade"
#define PLUGIN_AUTHOR                 "Mart"
#define PLUGIN_DESCRIPTION            "Applies a screen fade effect during a Jockey ride in Left 4 Dead 2."
#define PLUGIN_VERSION                "1.0.1"
#define PLUGIN_URL                    "https://forums.alliedmods.net/showthread.php?t=338664"

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version     = PLUGIN_VERSION,
    url         = PLUGIN_URL
};

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define CVAR_FLAGS                    FCVAR_NOTIFY
#define CVAR_FLAGS_VERSION            FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY
#define CONFIG_FILENAME               "l4d2_ride_screen_fade"

#define FFADE_IN                      0x0001
#define FFADE_OUT                     0x0002
#define FFADE_STAYOUT                 0x0008
#define FFADE_PURGE                   0x0010
#define SCREENFADE_FRACBITS           (1 << 9)      // 512

ConVar g_cvEnabled;
ConVar g_cvColor;
ConVar g_cvAlpha;
ConVar g_cvFadeOutDuration;
ConVar g_cvFadeInDuration;
ConVar g_cvBlock;

bool g_bEventsHooked;
bool g_bEnabled;
bool g_bRandomColor;
bool g_bBlockFade;
int g_iColor[3];
int g_iAlpha;
int g_iFadeOutDuration;
int g_iFadeInDuration;
float g_fFadeOutDuration;
float g_fFadeInDuration;
char g_sColor[12];
UserMsg g_umFade;
bool g_bClientFade[MAXPLAYERS + 1];
int g_iClientColor[MAXPLAYERS + 1][3];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, errMax, "This plugin is exclusively compatible with Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    g_umFade = GetUserMessageId("Fade");

    CreateConVar("l4d2_ride_screen_fade_version", PLUGIN_VERSION, "Plugin version.", CVAR_FLAGS_VERSION);
    g_cvEnabled         = CreateConVar("l4d2_ride_screen_fade_enable", "1", "Enable the plugin. 0 = Disabled, 1 = Enabled.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_cvColor           = CreateConVar("l4d2_ride_screen_fade_color", "20 0 0", "Fade color. Use 'random' for random colors or specify RGB values (0-255) separated by spaces.", CVAR_FLAGS);
    g_cvAlpha           = CreateConVar("l4d2_ride_screen_fade_alpha", "245", "Fade transparency. 0 = Invisible, 255 = Fully visible.", CVAR_FLAGS, true, 0.0, true, 255.0);
    g_cvFadeOutDuration = CreateConVar("l4d2_ride_screen_fade_out_duration", "0.5", "Fade-out duration in seconds.", CVAR_FLAGS, true, 0.0);
    g_cvFadeInDuration  = CreateConVar("l4d2_ride_screen_fade_in_duration", "0.5", "Fade-in duration in seconds.", CVAR_FLAGS, true, 0.0);
    g_cvBlock           = CreateConVar("l4d2_ride_screen_fade_block", "1", "Block other fade effects during plugin fade. 0 = Disabled, 1 = Enabled.", CVAR_FLAGS, true, 0.0, true, 1.0);

    g_cvEnabled.AddChangeHook(OnConVarChanged);
    g_cvColor.AddChangeHook(OnConVarChanged);
    g_cvAlpha.AddChangeHook(OnConVarChanged);
    g_cvFadeOutDuration.AddChangeHook(OnConVarChanged);
    g_cvFadeInDuration.AddChangeHook(OnConVarChanged);
    g_cvBlock.AddChangeHook(OnConVarChanged);

    AutoExecConfig(true, CONFIG_FILENAME);
}

public void OnConfigsExecuted()
{
    UpdateConVarCache();
    ManageEventHooks();
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateConVarCache();
    ManageEventHooks();

    if (!g_bEnabled)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (IsValidClient(client) && !IsFakeClient(client))
                ClearFade(client);
        }
    }
}

void UpdateConVarCache()
{
    g_bEnabled = g_cvEnabled.BoolValue;
    g_cvColor.GetString(g_sColor, sizeof(g_sColor));
    TrimString(g_sColor);
    StringToLowerCase(g_sColor);
    g_bRandomColor = StrEqual(g_sColor, "random");
    g_iColor = ConvertRGBStringToArray(g_sColor);
    g_iAlpha = g_cvAlpha.IntValue;
    g_fFadeOutDuration = g_cvFadeOutDuration.FloatValue;
    g_iFadeOutDuration = RoundFloat(g_fFadeOutDuration * SCREENFADE_FRACBITS);
    g_fFadeInDuration = g_cvFadeInDuration.FloatValue;
    g_iFadeInDuration = RoundFloat(g_fFadeInDuration * SCREENFADE_FRACBITS);
    g_bBlockFade = g_cvBlock.BoolValue;
}

void ManageEventHooks()
{
    if (g_bEnabled && !g_bEventsHooked)
    {
        g_bEventsHooked = true;
        HookEvent("jockey_ride", OnJockeyRide);
        HookEvent("jockey_ride_end", OnJockeyRideEnd);
        HookEvent("player_death", OnPlayerDeath);
        HookUserMessage(g_umFade, OnFadeMessage, true);
    }
    else if (!g_bEnabled && g_bEventsHooked)
    {
        g_bEventsHooked = false;
        UnhookEvent("jockey_ride", OnJockeyRide);
        UnhookEvent("jockey_ride_end", OnJockeyRideEnd);
        UnhookEvent("player_death", OnPlayerDeath);
        UnhookUserMessage(g_umFade, OnFadeMessage, true);
    }
}

public void OnClientDisconnect(int client)
{
    if (g_bClientFade[client])
        ClearFade(client);
    g_bClientFade[client] = false;
    g_iClientColor[client] = {0, 0, 0};
}

Action OnFadeMessage(UserMsg msgId, BfRead bf, const int[] players, int playerCount, bool reliable, bool init)
{
    if (!g_bBlockFade || playerCount != 1)
        return Plugin_Continue;

    int client = players[0];
    if (!IsValidClient(client) || IsFakeClient(client))
        return Plugin_Continue;

    if (g_bClientFade[client])
    {
        g_bClientFade[client] = false;
        return Plugin_Continue;
    }

    if (GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") == -1)
        return Plugin_Continue;

    return Plugin_Handled;
}

void OnJockeyRide(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("victim"));
    if (client != 0)
        ApplyFadeOut(client);
}

void OnJockeyRideEnd(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("victim"));
    if (client != 0)
        ApplyFadeIn(client);
}

void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim == 0 || !IsClientInGame(victim) || GetClientTeam(victim) != 3)
        return;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidClient(client) && !IsFakeClient(client) && GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") == victim)
            ApplyFadeIn(client);
    }
}

void ApplyFadeOut(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    if (g_bRandomColor)
    {
        g_iClientColor[client][0] = GetRandomInt(0, 255);
        g_iClientColor[client][1] = GetRandomInt(0, 255);
        g_iClientColor[client][2] = GetRandomInt(0, 255);
    }
    else
    {
        g_iClientColor[client] = g_iColor;
    }

    g_bClientFade[client] = true;
    PerformScreenFade(client, g_iFadeOutDuration, SCREENFADE_FRACBITS, FFADE_PURGE | FFADE_OUT | FFADE_STAYOUT,
                      g_iClientColor[client][0], g_iClientColor[client][1], g_iClientColor[client][2], g_iAlpha);
}

void ApplyFadeIn(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    g_bClientFade[client] = true;
    PerformScreenFade(client, g_iFadeInDuration, SCREENFADE_FRACBITS, FFADE_PURGE | FFADE_IN,
                      g_iClientColor[client][0], g_iClientColor[client][1], g_iClientColor[client][2], g_iAlpha);
}

void ClearFade(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    g_bClientFade[client] = true;
    PerformScreenFade(client, 0, 0, FFADE_PURGE | FFADE_IN, 0, 0, 0, 0);
}

bool IsValidClient(int client)
{
    return (client >= 1 && client <= MaxClients && IsClientInGame(client));
}

void StringToLowerCase(char[] input)
{
    for (int i = 0; i < strlen(input); i++)
        input[i] = CharToLower(input[i]);
}

int[] ConvertRGBStringToArray(const char[] colorString)
{
    int color[3];
    if (colorString[0] == '\0')
        return color;

    char colors[3][4];
    int count = ExplodeString(colorString, " ", colors, sizeof(colors), sizeof(colors[]));
    if (count >= 1) color[0] = StringToInt(colors[0]);
    if (count >= 2) color[1] = StringToInt(colors[1]);
    if (count == 3) color[2] = StringToInt(colors[2]);
    return color;
}

void PerformScreenFade(int client, int delay, int duration, int type, int red, int green, int blue, int alpha)
{
    Handle msg = StartMessageOne("Fade", client);
    BfWrite bf = UserMessageToBfWrite(msg);
    bf.WriteShort(delay);
    bf.WriteShort(duration);
    bf.WriteShort(type);
    bf.WriteByte(red);
    bf.WriteByte(green);
    bf.WriteByte(blue);
    bf.WriteByte(alpha);
    EndMessage();
}

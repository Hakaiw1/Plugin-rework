#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

// Plugin metadata
public Plugin myinfo = {
	name = "Boomer Vomit Effects", 
	author = "Alexander Mirny", 
	description = "Hides the HUD and inflicts damage when a Boomer vomits on a player.", 
	version = "1.0", 
	url = "https://vk.com/id602817125"
};

// Constant for hiding all HUD elements
#define HIDEHUD_ALL 127

// Initialize plugin and hook events
public void OnPluginStart() {
	HookEvent("player_now_it", Event_PlayerNowIt, EventHookMode_Post);
}

// Handle Boomer vomit event
public void Event_PlayerNowIt(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	// Validate victim client and ensure they are alive
	if (!IsValidClient(victim) || !IsPlayerAlive(victim)) { return; }
	
	// Apply random damage based on predefined cases
	ApplyRandomDamage(victim, attacker);
	
	// Hide HUD and store original HUD state
	int originalHideHUD = GetEntProp(victim, Prop_Send, "m_iHideHUD");
	SetEntProp(victim, Prop_Send, "m_iHideHUD", HIDEHUD_ALL);
	
	// Create data pack for HUD restoration
	DataPack dataPack = new DataPack();
	dataPack.WriteCell(victim);
	dataPack.WriteCell(originalHideHUD);
	
	// Set timer to restore HUD after 8 seconds
	CreateTimer(8.0, Timer_RestoreHUD, dataPack);
}

// Apply random damage to the victim
void ApplyRandomDamage(int victim, int attacker) {
	int damage;
	char message[64];
	
	// Determine damage amount and corresponding message
	switch (GetRandomInt(0, 5)) {
		case 0: { damage = 15; Format(message, sizeof(message), "Boomer vomit is toxic -15HP"); }
		case 1: { damage = 20; Format(message, sizeof(message), "Boomer vomit is toxic -20HP"); }
		case 2: { damage = 35; Format(message, sizeof(message), "Boomer vomit is toxic -35HP"); }
		case 3: { damage = 46; Format(message, sizeof(message), "Boomer vomit is toxic -46HP"); }
		case 4: { damage = 51; Format(message, sizeof(message), "Boomer vomit is toxic -51HP"); }
	}
	
	// Notify victim of damage
	PrintToChat(victim, "\x04%s", message);
	
	// Create data pack for damage application
	DataPack dataPack = new DataPack();
	dataPack.WriteCell(damage);
	dataPack.WriteCell(victim);
	dataPack.WriteCell(attacker);
	
	// Apply damage after a short delay
	CreateTimer(0.1, Timer_ApplyDamage, dataPack);
}

// Timer callback to restore HUD
public Action Timer_RestoreHUD(Handle timer, DataPack dataPack) {
	dataPack.Reset();
	int client = dataPack.ReadCell();
	int originalHUD = dataPack.ReadCell();
	delete dataPack;
	
	// Restore HUD if client is valid
	if (IsValidClient(client)) {
		SetEntProp(client, Prop_Send, "m_iHideHUD", originalHUD);
	}
	
	return Plugin_Stop;
}

// Timer callback to apply damage
public Action Timer_ApplyDamage(Handle timer, DataPack dataPack) {
	dataPack.Reset();
	int damage = dataPack.ReadCell();
	int victim = dataPack.ReadCell();
	int attacker = dataPack.ReadCell();
	delete dataPack;
	
	// Validate victim client
	if (!IsValidClient(victim)) { return Plugin_Stop; }
	
	// Prepare damage application
	float victimPos[3];
	char strDamage[16], strDamageTarget[16];
	GetClientEyePosition(victim, victimPos);
	IntToString(damage, strDamage, sizeof(strDamage));
	Format(strDamageTarget, sizeof(strDamageTarget), "hurtme%d", victim);
	
	// Create point_hurt entity for damage
	int entPointHurt = CreateEntityByName("point_hurt");
	if (entPointHurt == -1) { return Plugin_Stop; }
	
	// Configure point_hurt entity
	DispatchKeyValue(victim, "targetname", strDamageTarget);
	DispatchKeyValue(entPointHurt, "DamageTarget", strDamageTarget);
	DispatchKeyValue(entPointHurt, "Damage", strDamage);
	DispatchSpawn(entPointHurt);
	
	// Apply damage
	TeleportEntity(entPointHurt, victimPos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(entPointHurt, "Hurt", (IsValidClient(attacker)) ? attacker : -1);
	
	// Clean up
	DispatchKeyValue(entPointHurt, "classname", "point_hurt");
	DispatchKeyValue(victim, "targetname", "null");
	RemoveEdict(entPointHurt);
	
	return Plugin_Stop;
}

// Check if client is valid and in-game
bool IsValidClient(int client) {
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
} 
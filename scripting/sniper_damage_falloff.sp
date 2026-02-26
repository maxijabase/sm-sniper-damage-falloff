#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <autoexecconfig>

#define PLUGIN_VERSION "1.0"

ConVar g_cvEnabled;
ConVar g_cvFalloffStart;
ConVar g_cvDropRate;
ConVar g_cvMinDamage;

bool g_bWizard[MAXPLAYERS + 1];
Handle g_hWizardTimer[MAXPLAYERS + 1];
Handle g_hHudSync;

int g_iBeamSprite;
int g_iHaloSprite;

public Plugin myinfo =
{
	name        = "Sniper Rifle Damage Falloff",
	author      = "ampere",
	description = "Configurable sniper rifle damage falloff with visual wizard",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/maxijabase/sm-sniper-damage-falloff",
};

public void OnPluginStart()
{
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("sniper_damage_falloff");

	g_cvEnabled      = AutoExecConfig_CreateConVar("sm_sniper_falloff_enabled", "1",     "Enable sniper rifle damage falloff", _, true, 0.0, true, 1.0);
	g_cvFalloffStart = AutoExecConfig_CreateConVar("sm_sniper_falloff_start",   "512.0", "Distance (units) where damage starts falling off", _, true, 0.0);
	g_cvDropRate     = AutoExecConfig_CreateConVar("sm_sniper_falloff_rate",    "5.0",   "Percentage points of damage lost per 100 units past start distance", _, true, 0.0, true, 100.0);
	g_cvMinDamage    = AutoExecConfig_CreateConVar("sm_sniper_falloff_mindmg",  "50.0",  "Minimum damage as a percentage of base (damage floor)", _, true, 0.0, true, 100.0);

	AutoExecConfig_CleanFile();
	AutoExecConfig_ExecuteFile();

	RegAdminCmd("sm_sniper_wizard", Cmd_Wizard, ADMFLAG_CONFIG, "Toggle the sniper damage falloff visual wizard");

	g_hHudSync = CreateHudSynchronizer();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	g_bWizard[client] = false;

	if (g_hWizardTimer[client] != null)
	{
		KillTimer(g_hWizardTimer[client]);
		g_hWizardTimer[client] = null;
	}
}

// ────────────────────────────────────────────
// Damage formula
// ────────────────────────────────────────────

float CalcMultiplier(float dist)
{
	float start = g_cvFalloffStart.FloatValue;
	if (dist <= start)
		return 1.0;

	float rate    = g_cvDropRate.FloatValue;
	float minMult = g_cvMinDamage.FloatValue / 100.0;

	// Linear drop: lose (rate)% of base damage per 100 units past the start distance
	float mult = 1.0 - ((dist - start) * rate / 10000.0);

	if (mult < minMult)
		mult = minMult;

	return mult;
}

// ────────────────────────────────────────────
// Damage hook
// ────────────────────────────────────────────

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (!g_cvEnabled.BoolValue)
		return Plugin_Continue;

	if (attacker <= 0 || victim == attacker)
		return Plugin_Continue;

	if (!IsValidEdict(weapon))
		return Plugin_Continue;

	char classname[64];
	GetEdictClassname(weapon, classname, sizeof(classname));

	if (StrContains(classname, "tf_weapon_sniperrifle", false) == -1)
		return Plugin_Continue;

	float vec1[3], vec2[3];
	GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vec1);
	GetEntPropVector(victim,   Prop_Send, "m_vecOrigin", vec2);

	damage *= CalcMultiplier(GetVectorDistance(vec1, vec2));
	return Plugin_Changed;
}

// ────────────────────────────────────────────
// Wizard command
// ────────────────────────────────────────────

public Action Cmd_Wizard(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] This command can only be used in-game.");
		return Plugin_Handled;
	}

	g_bWizard[client] = !g_bWizard[client];

	if (g_bWizard[client])
	{
		g_hWizardTimer[client] = CreateTimer(0.1, Timer_Wizard, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		PrintToChat(client, "\x04[Sniper Wizard]\x01 Enabled. Aim around to visualize damage falloff.");
		PrintToChat(client, "\x04[Sniper Wizard]\x01 \x0EYellow ring\x01 = falloff starts | \x02Red ring\x01 = minimum damage reached");
	}
	else
	{
		if (g_hWizardTimer[client] != null)
		{
			KillTimer(g_hWizardTimer[client]);
			g_hWizardTimer[client] = null;
		}

		ClearSyncHud(client, g_hHudSync);
		PrintToChat(client, "\x04[Sniper Wizard]\x01 Disabled.");
	}

	return Plugin_Handled;
}

// ────────────────────────────────────────────
// Wizard tick
// ────────────────────────────────────────────

public Action Timer_Wizard(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client <= 0 || !IsClientInGame(client) || !g_bWizard[client])
	{
		if (client > 0)
		{
			g_bWizard[client] = false;
			g_hWizardTimer[client] = null;
		}
		return Plugin_Stop;
	}

	if (!IsPlayerAlive(client))
	{
		SetHudTextParams(-1.0, 0.25, 0.15, 200, 200, 200, 255);
		ShowSyncHudText(client, g_hHudSync, "Sniper Wizard: respawn to use");
		return Plugin_Continue;
	}

	// Trace from eye position to wherever the player is aiming
	float eyePos[3], eyeAng[3], endPos[3];
	GetClientEyePosition(client, eyePos);
	GetClientEyeAngles(client, eyeAng);

	Handle trace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SHOT, RayType_Infinite, TraceFilter_NoPlayers, client);
	bool hit = TR_DidHit(trace);
	if (hit)
		TR_GetEndPosition(endPos, trace);
	delete trace;

	if (!hit)
	{
		float fwd[3];
		GetAngleVectors(eyeAng, fwd, NULL_VECTOR, NULL_VECTOR);
		for (int i = 0; i < 3; i++)
			endPos[i] = eyePos[i] + fwd[i] * 4000.0;
	}

	// Distance from player origin to aim point (matches how OnTakeDamage measures it)
	float playerPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", playerPos);
	float dist = GetVectorDistance(playerPos, endPos);

	float mult   = CalcMultiplier(dist);
	float start  = g_cvFalloffStart.FloatValue;
	float rate   = g_cvDropRate.FloatValue;
	float minPct = g_cvMinDamage.FloatValue;

	// ── Beam color: green (full dmg) → yellow → red (min dmg) ──
	int beamColor[4];
	GetFalloffColor(mult, minPct / 100.0, beamColor);

	// Laser beam from eye to aim point
	TE_SetupBeamPoints(eyePos, endPos, g_iBeamSprite, g_iHaloSprite,
		0, 30, 0.12, 1.5, 1.5, 0, 0.0, beamColor, 0);
	TE_SendToClient(client);

	// Small ring at the aim point as a target marker
	TE_SetupBeamRingPoint(endPos, 10.0, 20.0, g_iBeamSprite, g_iHaloSprite,
		0, 30, 0.12, 3.0, 0.0, beamColor, 0, 0);
	TE_SendToClient(client);

	// ── Ground rings around the player ──
	float ringPos[3];
	ringPos[0] = playerPos[0];
	ringPos[1] = playerPos[1];
	ringPos[2] = playerPos[2] + 10.0;

	// Yellow ring: falloff start distance
	if (start > 0.0)
	{
		int yellow[4] = {255, 255, 0, 200};
		TE_SetupBeamRingPoint(ringPos, start * 2.0, start * 2.0 + 0.1, g_iBeamSprite, g_iHaloSprite,
			0, 30, 0.12, 4.0, 0.0, yellow, 0, 0);
		TE_SendToClient(client);
	}

	// Red ring: distance where minimum damage floor is reached
	if (rate > 0.0 && minPct < 100.0)
	{
		float maxDist = start + ((100.0 - minPct) / rate) * 100.0;
		if (maxDist > start)
		{
			int red[4] = {255, 0, 0, 200};
			TE_SetupBeamRingPoint(ringPos, maxDist * 2.0, maxDist * 2.0 + 0.1, g_iBeamSprite, g_iHaloSprite,
				0, 30, 0.12, 4.0, 0.0, red, 0, 0);
			TE_SendToClient(client);
		}
	}

	// ── HUD display ──
	float dmgBody    = 50.0  * mult;
	float dmgCharged = 150.0 * mult;
	float dmgHeadshot = 450.0 * mult;

	SetHudTextParams(-1.0, 0.22, 0.15, beamColor[0], beamColor[1], beamColor[2], 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(client, g_hHudSync,
		"== Sniper Falloff Wizard ==\n \
Distance: %.0f u  |  Damage: %.0f%%\n \
Noscope: %.0f / 50  |  Charged: %.0f / 150  |  Headshot: %.0f / 450\n \
[Start: %.0fu  |  Rate: %.1f%%/100u  |  Min: %.0f%%]",
		dist, mult * 100.0,
		dmgBody, dmgCharged, dmgHeadshot,
		start, rate, minPct);

	return Plugin_Continue;
}

// ────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────

void GetFalloffColor(float mult, float minMult, int color[4])
{
	// Normalize multiplier into 0..1 range where 0 = min damage, 1 = full damage
	float t;
	if (minMult >= 1.0)
		t = 1.0;
	else
		t = (mult - minMult) / (1.0 - minMult);

	if (t > 1.0) t = 1.0;
	if (t < 0.0) t = 0.0;

	// Green (1.0) → Yellow (0.5) → Red (0.0)
	if (t >= 0.5)
	{
		color[0] = RoundToFloor((1.0 - t) * 2.0 * 255.0);
		color[1] = 255;
	}
	else
	{
		color[0] = 255;
		color[1] = RoundToFloor(t * 2.0 * 255.0);
	}
	color[2] = 0;
	color[3] = 255;
}

public bool TraceFilter_NoPlayers(int entity, int contentsMask, int client)
{
	return entity != client && (entity < 1 || entity > MaxClients);
}

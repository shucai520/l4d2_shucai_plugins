#pragma semicolon 1
#pragma newdecls required
//#define DEBUG 0
// 头文件
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <l4d2_playtime_interface>

ConVar ReturnBlood, g_hTeleportSi, g_hTeleportDistance, g_hTeleportTankTime;

Handle hCvarCoop = INVALID_HANDLE;
Handle hCvarLeftSafeArea = INVALID_HANDLE;
Handle hCvarLeftSafeAreaGivePills = INVALID_HANDLE;

//是否出门
bool isLeftSafeArea = false;

// 传送
bool g_bTeleportSi;
Handle g_hTeleHandle = INVALID_HANDLE;
float g_fTeleportDistance;
// 特感种类
#define ZC_SPITTER 4
#define ZC_TANK 8
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
// Ints
int g_iTeleCount[MAXPLAYERS + 1] = {0}, g_iTeleportTankTime = 20,g_iSurvivors[MAXPLAYERS + 1] = {0},g_iSurvivorNum = 0, g_iTargetSurvivor = -1;

//存玩家时长
int client_time[MAXPLAYERS + 1][2];
//存玩家是否输出过时长
bool client_printTime[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name 			= "牛牛杂项设置",
	author 			= "蔬菜",
	description 	= "自杀,死门",
	version 		= "0.0.1",
	url 			= ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("l4d2_playtime_interface");
	//g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
    //RegAdminCmd("sm_recfg", Cmd_ReCfg, ADMFLAG_ROOT, "重新载入");
    //RM_Match_Load();
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("map_transition", Event_RoundStart);
	HookEvent("player_death", Event_PlayerDeath);

	ReturnBlood = CreateConVar("ReturnBlood", "0", "杀特感回血 - 0关闭, 有值则一次回多少", FCVAR_NONE, true, -1.0, true, 50.0);

	g_hTeleportSi = CreateConVar("inf_TeleportSi", "1", "是否开启特感距离生还者一定距离将其传送至生还者周围", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hTeleportDistance = CreateConVar("inf_TeleportDistance", "800.0", "特感落后于最近的生还者超过这个距离则将它们传送", FCVAR_NOTIFY, true, 0.0);
	g_hTeleportTankTime = CreateConVar("l4d_TeleportTank_time", "30", "Tank看不见传送的时间", FCVAR_NOTIFY, true, 0.0);
	g_hTeleportSi.AddChangeHook(TeleportSiChanged_Cvars);
	g_hTeleportDistance.AddChangeHook(TeleportSiChanged_Cvars);

	TeleportSiChanged_Cvars(INVALID_HANDLE, NULL_STRING, NULL_STRING);

	HookConVarChange(FindConVar("mp_gamemode"), Cvar_GameMode);

	//自杀
	RegConsoleCmd("sm_zs", Suicide);
	RegConsoleCmd("sm_kill", Suicide);
	//死门
	HookEvent("player_incapacitated_start",Incapacitated_Event);
	HookEvent("player_incapacitated",Incapacitated_Event);

	//HookEvent("player_team", Event_PlayerTeam);
	hCvarCoop = CreateConVar("coopmode", "0");
	//通关,出门 回血
	hCvarLeftSafeArea  = CreateConVar("sc_give_hp", "0");
	//出门给药包 1=药 2=包 3=都要
	hCvarLeftSafeAreaGivePills  = CreateConVar("sc_give_pills", "0");

	//rygive
	RegConsoleCmd("sm_r", RygiveEasyConsole);
	//rygive
	//RegConsoleCmd("sm_sc", GetTimeConsole);

	//没人重启服
	HookEvent("player_disconnect", PlayerDisconnect_Event);
}

void TeleportSiChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_fTeleportDistance = g_hTeleportDistance.FloatValue;
	g_iTeleportTankTime = g_hTeleportTankTime.IntValue;
	g_bTeleportSi = g_hTeleportSi.BoolValue;
	if(!g_bTeleportSi)
	{
		if (g_hTeleHandle != INVALID_HANDLE)
		{
			delete g_hTeleHandle;
			g_hTeleHandle = INVALID_HANDLE;
		}
	}
}

public void L4D2_OnGetPlaytime(const char[] auth, bool real, int value)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && !IsFakeClient(i))
		{
			char authId[65];
			GetClientAuthId(i, AuthId_Steam2, authId, sizeof(authId));

			//LogMessage("%s %s", auth, authId);
			if(strcmp(auth, authId) == 0)
			{
				client_time[i][real ? 1 : 0] = value;
				LogMessage("%N log获取 auth: %s 时间类型: %d, 获取结果: %d", i, auth, real, value);
				break;
			}
		}
	}
	
}

//玩家连接.
public void OnClientAuthorized(int client, const char[] auth)
{
	if(!IsFakeClient(client))
	{
		client_printTime[client] = false;
		L4D2_GetTotalPlaytime(auth, true);
		L4D2_GetTotalPlaytime(auth, false);

		//LogMessage("111获取: %N 时间类型: %d, 获取结果: %d", client, true, readltime);
		//LogMessage("111获取:%s 时间类型: %d, 获取结果: %d", auth, false, time);
		//CreateTimer(20.0, PrintClientTime, client);
	}
}

public void OnClientPutInServer(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	if(client && IsClientConnected(client) && IsClientInGame(client)&& !IsFakeClient(client))
	{
		if(GetConVarBool(hCvarLeftSafeArea))
		{
			BypassAndExecuteCommand(client, "give", "health");
			SetEntPropFloat(client, Prop_Send, "m_healthBuffer", 0.0);
			SetEntProp(client, Prop_Send, "m_currentReviveCount", 0);
			SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 0);
		}
		
		if(!client_printTime[client])
		{
			client_printTime[client] = true; 
			CreateTimer(5.0, PrintClientTime, client);
		}
	}
}

public Action PrintClientTime(Handle timer, int client)
{
	//char authId64[65];
	//GetClientAuthId(client, AuthId_Steam2, authId64, sizeof(authId64));
	//int realtime1 = L4D2_GetTotalPlaytime(authId64, true);
	//int time1 = L4D2_GetTotalPlaytime(authId64, false);
	//LogMessage("获取: %N 时间类型: %d, 获取结果: %d", client, true, realtime1);
	//LogMessage("获取 auth: %s 时间类型: %d, 获取结果: %d", authId64, false, time1);

	int time = client_time[client][0];
	int realtime = client_time[client][1];

	char timestr[16];
	if(time > 0)
	{
		FormatEx(timestr, sizeof(timestr), "%d 小时", time / 60 / 60);
	}
	else
	{
		timestr = "未知";
	}

	char realstr[16];
	if(realtime > 0)
	{
		FormatEx(realstr, sizeof(realstr), "%d 小时", realtime / 60 / 60);
	}
	else
	{
		realstr = "未知";
	}

	char result[128];
	FormatEx(result, sizeof(result), "\x03%N\x01 游戏时长: \x04%s  \x01-  实际时长: \x04%s", client, timestr, realstr);
	
	PrintToChatAll("%s", result);
	LogMessage("%s", result);
	return Plugin_Handled;
}

public void Cvar_GameMode(Handle cvar, const char[] oldValue, const char[] newValue) 
{
	if(strcmp(newValue, "mutation4") == 0)
	{
		ServerCommand("exec vote/si/mutation_8.cfg");
	}
	else if(strcmp(newValue, "community1") == 0)
	{
		ServerCommand("exec vote/si/mutation_8.cfg");
	}
}

public void OnMapStart()
{
	//ServerCommand("sm plugins load_unlock");
	//ServerCommand("sm plugins reload left4dhooks.smx");
	//ServerCommand("sm plugins load_lock");

    isLeftSafeArea = false;
}

public Action RygiveEasyConsole(int client, int args)
{
	ExecuteCommand(client, "sm_rygive");
	return Plugin_Handled;
}

//  public Action GetTimeConsole(int client, int args)
//  {
//  	char authId64[65];
//  	GetClientAuthId(client, AuthId_SteamID64, authId64, sizeof(authId64));
//  	int time = L4D2_GetTotalPlaytime(authId64, true);
//  	PrintToChat(client, "获取 auth: %s 时间类型: %d, 获取结果: %d", authId64, true, time);
//  	CreateTimer(1.0, PrintClientTime, client);
//  	return Plugin_Handled;
//  }


public Action Suicide(int client, int args)
{
	ForcePlayerSuicide(client);
	return Plugin_Handled;
}


//倒地
public void Incapacitated_Event(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(GetConVarBool(hCvarCoop) && isLeftSafeArea)
	{
		ForcePlayerSuicide(client);
	}
}

//导演模式的最大特感
// public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal){
// 	if( strcmp(key, "MaxSpecials") == 0 ){
// 		retVal = 16;
// 		return Plugin_Handled;
// 	}
// 	return Plugin_Continue;
// }

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if(IsSurvivor(victim) && (IsSi(attacker) && !IsFakeClient(attacker)))
	{
		float newDamage = (damage / 5.0);
		if(newDamage < 1.0)
		{
			newDamage = 1.0;
		}
		damage = newDamage;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (1 <= victim <= MaxClients && IsClientInGame(victim) && GetClientTeam(victim) == 3)
	{
		if (IsSurvivor(attacker) && IsPlayerAlive(attacker))
		{
			// if (!IsFakeClient(attacker))
			// {
				int hp = ReturnBlood.IntValue;
				if (hp != 0)
				{
					int maxhp = GetEntProp(attacker, Prop_Data, "m_iMaxHealth");
					int targetHealth = GetEntProp(attacker, Prop_Send, "m_iHealth");

					if (0 > hp)
					{
						//负数就随机
						hp = GetRandomInt(5, 30);
					}
					targetHealth += hp;
					
					if (targetHealth > maxhp)
					{
						targetHealth = maxhp;
					}
					//没有倒地才加血
					int isIncapacitated = GetEntProp(attacker, Prop_Send, "m_isIncapacitated");
					if (!isIncapacitated)
					{
						SetEntProp(attacker, Prop_Send, "m_iHealth", targetHealth);
					}
				}
			//}
		}
	}
	return Plugin_Continue;
}

public void PlayerDisconnect_Event(Event event, const char[] name, bool dontBroadcast)
{
	// 不显示玩家退出信息
	//SetEventBroadcast(event, true);
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && client <= MaxClients)
	{
		// 是否需要重启服务器
		if (!CheckHasAnyPlayer(client))
		{
			LogMessage("服务器中最后一位玩家：%N 已离开服务器，正在重启服务器...", client);
			RestartServer();
		}
	}
}

//出门刷
public Action L4D_OnFirstSurvivorLeftSafeArea(int client)
{
	isLeftSafeArea = true;
	// 加血给药
	LeftSafeAreaDo(true);
	PrintToChatAll("\x04[提示]\x05!cm 或 !vote 可以设置模式、难度、功能.");

	if(g_bTeleportSi && g_hTeleHandle == INVALID_HANDLE)
	{
		g_hTeleHandle = CreateTimer(0.2, Timer_PositionSi, _, TIMER_REPEAT);
	}

	return Plugin_Continue;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	isLeftSafeArea = false;
	// 加血
	LeftSafeAreaDo(false);

	if (g_hTeleHandle != INVALID_HANDLE)
	{
		delete g_hTeleHandle;
		g_hTeleHandle = INVALID_HANDLE;
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	isLeftSafeArea = false;
	if (g_hTeleHandle != INVALID_HANDLE)
	{
		delete g_hTeleHandle;
		g_hTeleHandle = INVALID_HANDLE;
	}
}


stock bool IsSurvivor(int client)
{
	return BaseJudge(client) && GetClientTeam(client) == 2;
}

stock bool IsSi(int client)
{
    return BaseJudge(client) && GetClientTeam(client) == 3;
}

stock bool BaseJudge(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}

// 回血
void LeftSafeAreaDo(bool isLeftSafeAreaFlag)
{
	bool give_hp = GetConVarBool(hCvarLeftSafeArea);
	int give_pills = GetConVarInt(hCvarLeftSafeAreaGivePills);
	if(give_hp || give_pills > 0)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsSurvivor(client) && IsPlayerAlive(client))
			{
				if(give_hp)
				{
					BypassAndExecuteCommand(client, "give", "health");
					SetEntPropFloat(client, Prop_Send, "m_healthBuffer", 0.0);
					SetEntProp(client, Prop_Send, "m_currentReviveCount", 0);
					SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 0);
				}

				if((give_pills == 1 || give_pills == 3) && isLeftSafeAreaFlag)
				{
					BypassAndExecuteCommand(client, "give", "pain_pills");
				}

				if((give_pills == 2 || give_pills == 3) && isLeftSafeAreaFlag)
				{
					BypassAndExecuteCommand(client, "give", "first_aid_kit");
				}
			}
		}
	}
}

// 是否还有玩家
bool CheckHasAnyPlayer(int client)
{
	for (int player = 1; player <= MaxClients; player++)
	{
		if (IsClientConnected(player) && !IsFakeClient(player) && player != client)
		{
			return true;
		}
	}
	return false;
}

// 重启服务器
void RestartServer()
{
	SetCommandFlags("crash", GetCommandFlags("crash") & ~ FCVAR_CHEAT);
	SetCommandFlags("sv_crash", GetCommandFlags("sv_crash") & ~ FCVAR_CHEAT);
	ServerCommand("crash");
	ServerCommand("sv_crash");
}

public void BypassAndExecuteCommand(int client, char[] strCommand, char[] strParam1)
{
	int flags = GetCommandFlags(strCommand);
	SetCommandFlags(strCommand, flags & ~ FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", strCommand, strParam1);
	SetCommandFlags(strCommand, flags);
}

stock void ExecuteCommand(int client, const char[] sCommand)
{
	int iFlags = GetCommandFlags(sCommand);
	SetCommandFlags(sCommand, iFlags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s", sCommand);
	SetCommandFlags(sCommand, iFlags);
}

//5秒内以0.1s检测一次，49次没被看到，就可以传送了
//tank 30s
public Action Timer_PositionSi(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if(CanBeTeleportTank(client)){
			float fSelfPos[3] = {0.0};
			GetClientEyePosition(client, fSelfPos);
			
			if (!PlayerVisibleTo(fSelfPos))
			{
				bool isTank = GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_TANK;
				if ((!isTank && g_iTeleCount[client] > 49) || (isTank && g_iTeleCount[client] > (g_iTeleportTankTime * 10)))
				{
					//Debug_Print("%N开始传送",client);
					//PrintToChatAll("%N开传", client);
					if ((!PlayerVisibleTo(fSelfPos) || isTank) && !IsPinningSomeone(client))
					{
						if(isTank)
						{
							PrintHintTextToAll("Tank开始传送到生还者附近.");
						}
						SDKHook(client, SDKHook_PostThinkPost, SDK_UpdateThink);
						g_iTeleCount[client] = 0;
					}
				}
				g_iTeleCount[client] += 2;
			}
			else{
				g_iTeleCount[client] = 0;
			}
		}
		
	}
	return Plugin_Continue;
}

// 传送落后特感
public void SDK_UpdateThink(int client)
{
	if (IsInfectedBot(client) && IsPlayerAlive(client))
	{
		g_iTeleCount[client] = 0;
		HardTeleMode(client);
	}
}

void HardTeleMode(int client)
{
	static float fEyePos[3] = {0.0}, fSelfEyePos[3] = {0.0};
	GetClientEyePosition(client, fEyePos);
	if (!TeleportPlayerVisibleTo(fEyePos) && !IsPinningSomeone(client))
	{
		float fSpawnPos[3] = {0.0}, fSurvivorPos[3] = {0.0}, fDirection[3] = {0.0}, fEndPos[3] = {0.0}, fMins[3] = {0.0}, fMaxs[3] = {0.0};
		HasAnyCountFull();
		if (IsValidSurvivor(g_iTargetSurvivor))
		{
			//PrintToChatAll("传送2 循环 - %N", client);
			GetClientEyePosition(g_iTargetSurvivor, fSurvivorPos);
			GetClientEyePosition(client, fSelfEyePos);
			fMins[0] = fSurvivorPos[0] - 500;
			fMaxs[0] = fSurvivorPos[0] + 500;
			fMins[1] = fSurvivorPos[1] - 500;
			fMaxs[1] = fSurvivorPos[1] + 500;
			fMaxs[2] = fSurvivorPos[2] + 500;
			fDirection[0] = 90.0;
			fDirection[1] = fDirection[2] = 0.0;
			fSpawnPos[0] = GetRandomFloat(fMins[0], fMaxs[0]);
			fSpawnPos[1] = GetRandomFloat(fMins[1], fMaxs[1]);
			fSpawnPos[2] = GetRandomFloat(fSurvivorPos[2], fMaxs[2]);
//			fVisiblePos[0] =fSpawnPos[0];
//			fVisiblePos[1] =fSpawnPos[1];
//			fVisiblePos[2] =fSpawnPos[2];
			int count2=0;
			
			while (TeleportPlayerVisibleTo(fSpawnPos) || !IsOnValidMesh(fSpawnPos) || IsPlayerStuck(fSpawnPos))
			{
				count2 ++;
				if(count2 > 50)
				{
					break;
				}
				fSpawnPos[0] = GetRandomFloat(fMins[0], fMaxs[0]);
				fSpawnPos[1] = GetRandomFloat(fMins[1], fMaxs[1]);
				fSpawnPos[2] = GetRandomFloat(fSurvivorPos[2], fMaxs[2]);
				TR_TraceRay(fSpawnPos, fDirection, MASK_NPCSOLID_BRUSHONLY, RayType_Infinite);
				if(TR_DidHit())
				{
					TR_GetEndPosition(fEndPos);
					if(!IsOnValidMesh(fEndPos))
					{
						fSpawnPos[2] = fSurvivorPos[2] + 20.0;
						TR_TraceRay(fSpawnPos, fDirection, MASK_NPCSOLID_BRUSHONLY, RayType_Infinite);
						if(TR_DidHit())
						{
							TR_GetEndPosition(fEndPos);
							fSpawnPos = fEndPos;
							fSpawnPos[2] += 20.0;
						}
					}
					else
					{
						fSpawnPos = fEndPos;
						fSpawnPos[2] += 20.0;
					}
				}
			}
			if (count2<=50)
			{
				//PrintToChatAll("传送次数:%d - %N", count2, client);
				for (int count = 0; count < g_iSurvivorNum; count++)
				{
					int index = g_iSurvivors[count];
					if (IsClientInGame(index))
					{
						GetClientEyePosition(index, fSurvivorPos);
						fSurvivorPos[2] -= 60.0;
						if (L4D2_VScriptWrapper_NavAreaBuildPath(fSpawnPos, fSurvivorPos, g_fTeleportDistance, false, false, TEAM_INFECTED, false) && GetVectorDistance(fSelfEyePos, fSpawnPos) > 300 )//g_fSpawnDistanceMin)
						{
							//PrintToChatAll("成功 - %N", client);
							TeleportEntity(client, fSpawnPos, NULL_VECTOR, NULL_VECTOR);
							SDKUnhook(client, SDKHook_PostThinkPost, SDK_UpdateThink);
							return;
						}
					}
				}
			}
		}
	}
}

bool IsOnValidMesh(float fReferencePos[3])
{
	Address pNavArea = L4D2Direct_GetTerrorNavArea(fReferencePos);
	if (pNavArea != Address_Null)
	{
		return true;
	}
	else
	{
		return false;
	}
}

//判断该坐标是否可以看到生还或者距离小于300码(传送专属)
bool TeleportPlayerVisibleTo(float spawnpos[3])
{
	float pos[3];
	g_iSurvivorNum = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidSurvivor(i) && IsPlayerAlive(i))
		{
			g_iSurvivors[g_iSurvivorNum] = i;
			g_iSurvivorNum++;
			GetClientEyePosition(i, pos);
			if(PosIsVisibleTo(i, spawnpos) || GetVectorDistance(spawnpos, pos) < 300.0)
			{
				return true;
			}
		}	
	}
	return false;
}

int HasAnyCountFull()
{
	int  iSurvivors[4] = {0}, iSurvivorIndex = 0, FurthestAlivePlayer=0;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidSurvivor(client) && IsPlayerAlive(client) && !IsPinned(client) && !L4D_IsPlayerIncapacitated(client))
		{
			//g_bIsLate = true;
			if (iSurvivorIndex < 4)
			{
				if(FurthestAlivePlayer==0)
					FurthestAlivePlayer=client;
				else if(L4D2Direct_GetFlowDistance(client)>L4D2Direct_GetFlowDistance(FurthestAlivePlayer))
					FurthestAlivePlayer=client;
				iSurvivors[iSurvivorIndex] = client;
				iSurvivorIndex += 1;
			}
		}
	}
	if (iSurvivorIndex > 0)
	{
		g_iTargetSurvivor = iSurvivors[GetRandomInt(0, iSurvivorIndex - 1)];
	}
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidSurvivor(client) && IsPlayerAlive(client))
		{
			if(client == FurthestAlivePlayer)
				continue;
			if(FurthestAlivePlayer == 0)
				break;
			float abs[3],abs2[3];
			GetClientAbsOrigin(client,abs);
			GetClientAbsOrigin(FurthestAlivePlayer,abs2);
			if(GetVectorDistance(abs,abs2) > 1500.0)
			{
				g_iTargetSurvivor = FurthestAlivePlayer;
				break;
			}
		}
	}
	return 0;
}

//判断该坐标是否可以看到生还或者距离小于200码
bool PlayerVisibleTo(float spawnpos[3])
{
	float pos[3];
	g_iSurvivorNum = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidSurvivor(i) && IsPlayerAlive(i))
		{
			g_iSurvivors[g_iSurvivorNum] = i;
			g_iSurvivorNum++;
			GetClientEyePosition(i, pos);
			if(PosIsVisibleTo(i, spawnpos) || GetVectorDistance(spawnpos, pos) < 250.0)
			{
				return true;
			}
		}	
	}
	return false;
}

//包含tank
bool CanBeTeleportTank(int client)
{
	if (IsInfectedBot(client) && IsClientInGame(client)&& IsPlayerAlive(client))
	{
		return true;
	}
	else
	{
		return false;
	}
}

bool IsInfectedBot(int client)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_INFECTED)
	{
		return true;
	}
	else
	{
		return false;
	}
}

bool IsValidSurvivor(int client)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR)
	{
		return true;
	}
	else
	{
		return false;
	}
}

bool IsPinningSomeone(int client)
{
	bool bIsPinning = false;
	if (IsInfectedBot(client))
	{
		if (GetEntPropEnt(client, Prop_Send, "m_tongueVictim") > 0) bIsPinning = true;
		if (GetEntPropEnt(client, Prop_Send, "m_jockeyVictim") > 0) bIsPinning = true;
		if (GetEntPropEnt(client, Prop_Send, "m_pounceVictim") > 0) bIsPinning = true;
		if (GetEntPropEnt(client, Prop_Send, "m_pummelVictim") > 0) bIsPinning = true;
		if (GetEntPropEnt(client, Prop_Send, "m_carryVictim") > 0) bIsPinning = true;
	}
	return bIsPinning;
}

bool IsPlayerStuck(float fSpawnPos[3])
{
	bool IsStuck = true;
	float fMins[3] = {0.0}, fMaxs[3] = {0.0}, fNewPos[3] = {0.0};
	fNewPos = fSpawnPos;
	fNewPos[2] += 35.0;
	fMins[0] = fMins[1] = -16.0;
	fMins[2] = 0.0;
	fMaxs[0] = fMaxs[1] = 16.0;
	fMaxs[2] = 35.0;
	TR_TraceHullFilter(fSpawnPos, fNewPos, fMins, fMaxs, 147467, TraceFilter, _);
	IsStuck = TR_DidHit();
	return IsStuck;
}


bool TraceFilter(int entity, int contentsMask)
{
	if (entity || entity <= MaxClients || !IsValidEntity(entity))
	{
		return false;
	}
	else
	{
		static char sClassName[9];
		GetEntityClassname(entity, sClassName, sizeof(sClassName));
		if (strcmp(sClassName, "infected") == 0 || strcmp(sClassName, "witch") == 0|| strcmp(sClassName, "prop_physics") == 0)
		{
			return false;
		}
	}
	return true;
}

bool IsPinned(int client)
{
	bool bIsPinned = false;
	if (IsValidSurvivor(client) && IsPlayerAlive(client))
	{
		if(GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0) bIsPinned = true;
		if(GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0) bIsPinned = true;
		if(GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0) bIsPinned = true;
		if(GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0) bIsPinned = true;
		if(GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0) bIsPinned = true;
	}		
	return bIsPinned;
}

//判断从该坐标发射的射线是否击中目标
bool PosIsVisibleTo(int client, const float targetposition[3])
{
	float position[3], vAngles[3], vLookAt[3], spawnPos[3];
	GetClientEyePosition(client, position);
	MakeVectorFromPoints(targetposition, position, vLookAt);
	GetVectorAngles(vLookAt, vAngles);
	Handle trace = TR_TraceRayFilterEx(targetposition, vAngles, MASK_VISIBLE, RayType_Infinite, TraceFilter, client);
	bool isVisible;
	isVisible = false;
	if(TR_DidHit(trace))
	{
		static float vStart[3];
		TR_GetEndPosition(vStart, trace);
		if((GetVectorDistance(targetposition, vStart, false) + 75.0) >= GetVectorDistance(position, targetposition))
		{
			isVisible = true;
		}
		else
		{
			spawnPos = targetposition;
			spawnPos[2] += 40.0;
			MakeVectorFromPoints(spawnPos, position, vLookAt);
			GetVectorAngles(vLookAt, vAngles);
			Handle trace2 = TR_TraceRayFilterEx(spawnPos, vAngles, MASK_VISIBLE, RayType_Infinite, TraceFilter, client);
			if(TR_DidHit(trace2))
			{
				TR_GetEndPosition(vStart, trace2);
				if((GetVectorDistance(spawnPos, vStart, false) + 75.0) >= GetVectorDistance(position, spawnPos))
				isVisible = true;
			}
			else
			{
				isVisible = true;
			}
			delete trace2;
//			CloseHandle(trace2);
		}
	}
	else
	{
		isVisible = true;
	}
	delete trace;
//	CloseHandle(trace);
	return isVisible;
}
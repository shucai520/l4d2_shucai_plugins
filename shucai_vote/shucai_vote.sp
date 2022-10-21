#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <builtinvotes>

#define FILE_PATH		"configs/cfgs.txt"
#define FILE_PATH_MODE	"configs/cfgs_mode.txt"
#define CONFIG_PATH "configs/cfgname.txt"

Handle g_hVote = INVALID_HANDLE;
Handle g_hVoteKick = INVALID_HANDLE;
ConVar g_hCmDubug;

KeyValues g_hCfgsKV = null;
KeyValues g_hTitleKV = null;

char g_sCfg[32];
char kickplayerinfo[MAX_NAME_LENGTH];
char kickplayername[MAX_NAME_LENGTH];

bool g_bDebug  = true;

#define MAX_BUTTONS 25
int g_LastButtons[MAXPLAYERS + 1];

#define MAX_OPTIONS 32

char convar_Arr[MAX_OPTIONS][64];
char c_InfoArr[MAX_OPTIONS][64];

char c_Value_SelectArr[MAX_OPTIONS][MAX_OPTIONS][64];
char c_Value_MessageArr[MAX_OPTIONS][MAX_OPTIONS][64];
char c_Value_ExecArr[MAX_OPTIONS][MAX_OPTIONS][255];

int c_Value_Can_Select[MAX_OPTIONS];
int c_Value_NowArr[MAX_OPTIONS];
char c_Vaule_Default[MAX_OPTIONS][64];
bool c_After_Reboot[MAX_OPTIONS][MAX_OPTIONS];
bool c_After_ReRead[MAX_OPTIONS][MAX_OPTIONS];

int title_Num = 0;

bool client_selecting[MAXPLAYERS + 1];
int client_selecting_line[MAXPLAYERS + 1];
bool client_showMenu[MAXPLAYERS + 1];
int client_change[MAXPLAYERS + 1][MAX_OPTIONS];

int changeMode_client = 0;


#define TITLE_STR "WS上下选择 AD切换内容:\n \n"

public Plugin myinfo = 
{
	name 			= "vote动态菜单投票模式",
	author 			= "蔬菜,HazukiYuro",
	description 	= "vote动态菜单投票模式 , 部分代码来自HazukiYuro vote投票",
	version 		= "0.1",
	url 			= ""
}

public void OnPluginStart()
{
	char sBuffer[128];
	GetGameFolderName(sBuffer, sizeof(sBuffer));
	if (!StrEqual(sBuffer, "left4dead2", false))
	{
		SetFailState("该插件只支持 求生之路2!");
	}

	reloadCfg();

	RegConsoleCmd("sm_vote", CommondVote);
	RegConsoleCmd("sm_votekick", Command_Voteskick);

	RegConsoleCmd("sm_cm", Command_Changemode);
	RegConsoleCmd("sm_serverhp", Command_ServerHp, _, ADMFLAG_KICK);

	RegAdminCmd("sm_reloadcfg", Cmd_ReloadCfg, ADMFLAG_GENERIC, "重新加载cfg");

	HookConVarChange(FindConVar("mp_gamemode"), Cvar_GameMode);

	g_hCmDubug = CreateConVar("cm_debug", "1", "日志查看加载情况", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hCmDubug, Cvar_Debug);
}

public void Cvar_GameMode(Handle cvar, const char[] oldValue, const char[] newValue) 
{
	Cmd_ReloadCfg(0, 0);
}

public void Cvar_Debug(Handle cvar, const char[] oldValue, const char[] newValue) 
{
	g_bDebug = g_hCmDubug.BoolValue;
	LogMessage("debug: %d", g_bDebug);
}

public Action Cmd_ReloadCfg(int client, int args)
{
	reloadCfg();
	readCfgTitle();
	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
	readCfgTitle();
}

public void reloadCfg()
{
	g_hCfgsKV = CreateKeyValues("Cfgs");
	g_hTitleKV = CreateKeyValues("title");

	char sBuffer[128];
	char sBufferMode[128];

	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), CONFIG_PATH);

	bool flag = false;
	char new_filepath[128];
	char new_filepath_mode[128];
	if(FileExists(filePath))
	{
		KeyValues kv_cfgname = new KeyValues("cfgname");
		if (!kv_cfgname.ImportFromFile(filePath))
		{
			LogMessage("动态导入 %s 失败！", filePath);
		}
		else
		{
			char port[16];
			GetConVarString(FindConVar("hostport"), port, sizeof(port));
			LogMessage("端口: %s", port);

			if(KvJumpToKey(kv_cfgname, port))
			{
				char newName[128];
				KvGetString(kv_cfgname, "name", newName, sizeof(newName));

				Format(new_filepath, sizeof(new_filepath), "configs/cfgs_%s.txt", newName);
				Format(new_filepath_mode, sizeof(new_filepath_mode), "configs/cfgs_mode_%s.txt", newName);

				flag = true;
			}
			else
			{
				LogMessage("没有对应的端口");
			}
		}
	}

		
	BuildPath(Path_SM, sBuffer, sizeof(sBuffer), flag ? new_filepath : FILE_PATH);
	BuildPath(Path_SM, sBufferMode, sizeof(sBufferMode), flag ? new_filepath_mode : FILE_PATH_MODE);
	if (!FileToKeyValues(g_hCfgsKV, sBuffer) || !FileToKeyValues(g_hTitleKV, sBufferMode))
	{
		SetFailState("无法加载cfgs.txt文件!");
	}
}

public void readCfgTitle()
{
	KvRewind(g_hTitleKV);

	char createCV[4];
	char defaultValue[64];
	char rebootChar[16];

	int i = 0;
    	if (KvGotoFirstSubKey(g_hTitleKV)) 
    {
        do {
            KvGetSectionName(g_hTitleKV, convar_Arr[i], sizeof(convar_Arr[]));
				LogMessage("开始加载: %s", convar_Arr[i]);

			KvGetString(g_hTitleKV, "info", c_InfoArr[i], sizeof(c_InfoArr[]));

			KvGetString(g_hTitleKV, "default", defaultValue, sizeof(defaultValue));

			KvGetString(g_hTitleKV, "create", createCV, sizeof(createCV));

			if (KvJumpToKey(g_hTitleKV, "condition"))
			{
				if(KvGotoFirstSubKey(g_hTitleKV))
				{
					bool includeFlag = CheckInclude();

					KvGoBack(g_hTitleKV);
					if(!includeFlag)
					{
						char test[64];
            			KvGetSectionName(g_hTitleKV, test, sizeof(test));
	            				LogMessage("条件全部不符合: %s", test);
						continue;
					}
				}
				else
				{
					KvGoBack(g_hTitleKV);
				}
			}

            char test[64];
            KvGetSectionName(g_hTitleKV, test, sizeof(test));
            	LogMessage("执行完条件后的位置: %s", test);

			if (!KvJumpToKey(g_hTitleKV, "value"))
			{
				LogMessage("%s 没找到Value kEY", convar_Arr[i]);
				KvGoBack(g_hTitleKV);
				convar_Arr[i] = "";
				c_InfoArr[i] = "";
				continue;
			}
			
			if(!KvGotoFirstSubKey(g_hTitleKV))
			{
				LogMessage("%s 没找到选项值", convar_Arr[i]);
				KvGoBack(g_hTitleKV);
				convar_Arr[i] = "";
				c_InfoArr[i] = "";
				continue;
			}

			ConVar cv = FindConVar(convar_Arr[i]);
			if(cv == INVALID_HANDLE)
			{
					LogMessage("找不到CV: %s", convar_Arr[i]);
				if(createCV[0] == '1')
				{
					CreateConVar(convar_Arr[i], defaultValue);
						LogMessage("创建CV: %s", convar_Arr[i]);
				}
				else
				{
					KvGoBack(g_hTitleKV);
					KvGoBack(g_hTitleKV);
					continue;
				}
			}

			c_Vaule_Default[i] = defaultValue;

			int select_i = 0;
			do
			{
				KvGetSectionName(g_hTitleKV, c_Value_SelectArr[i][select_i], sizeof(c_Value_SelectArr[][]));
				KvGetString(g_hTitleKV, "message", c_Value_MessageArr[i][select_i], sizeof(c_Value_MessageArr[][]));
				KvGetString(g_hTitleKV, "exec", c_Value_ExecArr[i][select_i], sizeof(c_Value_ExecArr[][]));
				KvGetString(g_hTitleKV, "after", rebootChar, sizeof(rebootChar));
				if(strcmp(rebootChar, "reboot") == 0)
				{
					c_After_Reboot[i][select_i] = true;
				}
				else if(strcmp(rebootChar, "reread") == 0)
				{
					c_After_ReRead[i][select_i] = true;
				}
				
				select_i++;
			}while(KvGotoNextKey(g_hTitleKV));

			c_Value_Can_Select[i] = select_i;

			KvGoBack(g_hTitleKV);
			KvGoBack(g_hTitleKV);

			i++;
        } while (KvGotoNextKey(g_hTitleKV));

		char test[64];
        KvGetSectionName(g_hTitleKV, test, sizeof(test));
        	LogMessage("执行完毕: %s", test);

		title_Num = i;
	}
}

bool CheckInclude()
{
	char includeCV[64];
	char includeCVValue[64];
	ConVar tempCV = INVALID_HANDLE;
	char tempCVValue[64];
	int includeCVValueType;
	bool result = true;
	bool conditionResult = false;

	do
	{
		KvGetSectionName(g_hTitleKV, includeCV, sizeof(includeCV));
		tempCV = FindConVar(includeCV);
		if(tempCV == INVALID_HANDLE)
		{
			continue;
		}

		if(!KvGotoFirstSubKey(g_hTitleKV, false))
		{
			KvGoBack(g_hTitleKV);
			continue;
		}
		GetConVarString(tempCV, tempCVValue, sizeof(tempCVValue));

		bool conformOne = false;

		do
		{
			KvGetSectionName(g_hTitleKV, includeCVValue, sizeof(includeCVValue));
			includeCVValueType = KvGetNum(g_hTitleKV, NULL_STRING, -1);

			if(includeCVValueType == 0 && strcmp(tempCVValue, includeCVValue) != 0)
			{
				LogMessage("类型: eq %s - %s 不相等", tempCVValue, includeCVValue);
				conditionResult = false;
				break;
			}
			else if(conformOne || (!conformOne && includeCVValueType == 1 && strcmp(tempCVValue, includeCVValue) == 0))
			{
				LogMessage("类型: in %s - %s 包含", tempCVValue, includeCVValue);
				conformOne = true;
				conditionResult = true;
				continue;
			}
			else if(includeCVValueType == 2 && strcmp(tempCVValue, includeCVValue) == 0)
			{
				LogMessage("类型: neq %s - %s 相等", tempCVValue, includeCVValue);
				conditionResult = false;
				break;
			}
			
		} while (KvGotoNextKey(g_hTitleKV, false));

        KvGoBack(g_hTitleKV);
		if(!conditionResult)
		{
			result = false;
			break;
		}

	}while(KvGotoNextKey(g_hTitleKV));

    KvGoBack(g_hTitleKV);
	return result;
}

stock void CheatCommand(int Client, const char[] command, const char[] arguments)
{
	int admindata = GetUserFlagBits(Client);
	SetUserFlagBits(Client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(Client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
	SetUserFlagBits(Client, admindata);
}

public Action Command_ServerHp(int client, int args)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			CheatCommand(i, "give", "health");
		}
	}
	PrintToChatAll("\x03投票回血通过");
	ReplyToCommand(client, "done");
	return Plugin_Handled;
}

public Action CommondVote(int client, int args)
{
	if (!client) return Plugin_Handled;
	if (args > 0)
	{
		char sCfg[64];
		char sBuffer[256];
		GetCmdArg(1, sCfg, sizeof(sCfg));
		BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "../../cfg/%s", sCfg);
		if (DirExists(sBuffer))
		{
			FindConfigName(sCfg, sBuffer, sizeof(sBuffer));
			if (StartVote(client, sBuffer))
			{
				strcopy(g_sCfg, sizeof(g_sCfg), sCfg);
				FakeClientCommand(client, "Vote Yes");
			}
			return Plugin_Handled;
		}
	}
	
	ShowVoteMenu(client);
	
	return Plugin_Handled;
}

bool FindConfigName(const char[] cfg, char []message, int maxlength)
{
	KvRewind(g_hCfgsKV);
	if (KvGotoFirstSubKey(g_hCfgsKV))
	{
		do
		{
			if (KvJumpToKey(g_hCfgsKV, cfg))
			{
				KvGetString(g_hCfgsKV, "message", message, maxlength);
				return true;
			}
		} while (KvGotoNextKey(g_hCfgsKV));
	}
	return false;
}

void ShowVoteMenu(int client)
{
	Menu hMenu = CreateMenu(VoteMenuHandler);
	SetMenuTitle(hMenu, "选择:");
	char sBuffer[64];
	KvRewind(g_hCfgsKV);
	if (KvGotoFirstSubKey(g_hCfgsKV))
	{
		do
		{
			KvGetSectionName(g_hCfgsKV, sBuffer, sizeof(sBuffer));
			AddMenuItem(hMenu, sBuffer, sBuffer);
		} while (KvGotoNextKey(g_hCfgsKV));
	}
	DisplayMenu(hMenu, client, 20);
}

public int VoteMenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[64], sBuffer[64], admin[8];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

		KvRewind(g_hCfgsKV);
		if(KvJumpToKey(g_hCfgsKV, sInfo) && KvGotoFirstSubKey(g_hCfgsKV))
		{
			char temp[64];
			KvGetSectionName(g_hCfgsKV, temp, sizeof(temp));
			if(StrEqual(temp, "sm_cm"))
			{
				Command_Changemode(param1, 1);
				return;
			}
		}


		KvRewind(g_hCfgsKV);
		if (KvJumpToKey(g_hCfgsKV, sInfo) && KvGotoFirstSubKey(g_hCfgsKV))
		{
			Menu hMenu = CreateMenu(ConfigsMenuHandler);
			Format(sBuffer, sizeof(sBuffer), "选择 %s :", sInfo);
			SetMenuTitle(hMenu, sBuffer);
			do
			{
				KvGetSectionName(g_hCfgsKV, sInfo, sizeof(sInfo));
				KvGetString(g_hCfgsKV, "message", sBuffer, sizeof(sBuffer));
				KvGetString(g_hCfgsKV, "admin", admin, sizeof(admin));
				if(!admin)
				{
					AddMenuItem(hMenu, sInfo, sBuffer);
				}
				else if(GetUserAdmin(param1))
				{
					AddMenuItem(hMenu, sInfo, sBuffer);
				}
			} while (KvGotoNextKey(g_hCfgsKV));
			DisplayMenu(hMenu, param1, 20);
		}
		else
		{
			PrintToChat(param1, "没有相关的文件存在.");
			ShowVoteMenu(param1);
		}
	}
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public int ConfigsMenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[64];
		char sBuffer[64];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo), _, sBuffer, sizeof(sBuffer));
		strcopy(g_sCfg, sizeof(g_sCfg), sInfo);
		
		if(!StrEqual(g_sCfg, "sm_votekick"))
		{
			if(StrEqual(g_sCfg, "sm_reloadcfg"))
			{
				Cmd_ReloadCfg(0,0);
				return;
			}

			if (StartVote(param1, sBuffer))
			{
				FakeClientCommand(param1, "Vote Yes");
			}
			else
			{
				ShowVoteMenu(param1);
			}
		}
		else
		{
			FakeClientCommand(param1, "sm_votekick");
		}
	}
	if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	if (action == MenuAction_Cancel)
	{
		ShowVoteMenu(param1);
	}
}

bool StartVote(int client, const char[] cfgname)
{
	if (!IsBuiltinVoteInProgress()) 
	{
		int iNumPlayers;
		int iPlayers[MAXPLAYERS + 1];
		
		for (int i = 1; i <= MAXPLAYERS + 1; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}
			iPlayers[iNumPlayers++] = i;
		}
		char sBuffer[64];
		g_hVote = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		Format(sBuffer, sizeof(sBuffer), "执行 '%s' ?", cfgname);
		SetBuiltinVoteArgument(g_hVote, sBuffer);
		SetBuiltinVoteInitiator(g_hVote, client);
		SetBuiltinVoteResultCallback(g_hVote, VoteResultHandler);
		DisplayBuiltinVoteToAll(g_hVote, 20);
		PrintToChatAll("\x04%N \x03发起了一个投票", client);
		return true;
	}
	PrintToChat(client, "已经有一个投票正在进行.");
	return false;
}

public void VoteActionHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action)
	{
		case BuiltinVoteAction_End:
		{
			g_hVote = INVALID_HANDLE;
			CloseHandle(vote);
		}
		case BuiltinVoteAction_Cancel:
		{
			DisplayBuiltinVoteFail(vote, BuiltinVoteFailReason:param1);
		}
	}
}

public void VoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++)
	{
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
		{
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] >= (num_clients * 0.6))
			{
				if (vote == g_hVote)
				{
					DisplayBuiltinVotePass(vote, "cfg文件正在加载...");
					ServerCommand("%s", g_sCfg);
					return;
				}
				else if(vote == g_hVoteKick)
				{
					ServerCommand("sm_kick %s 投票踢出", kickplayername);
					return;
				}
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public Action Command_Changemode(int client, int args)
{
	if(client != 0 && client <= MaxClients) 
	{
		client_selecting[client] = false;
		client_selecting_line[client] = -1;
		for(int i = 0; i < MAX_OPTIONS; i++)
		{
			client_change[client][i] = -1;
		}
		client_showMenu[client] = true;

		CreateVoteModeMenu(client);
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

void CreateVoteModeMenu(int client)
{	
	Menu menu = CreateMenu(Menu_VotesMode);		
	char tips[2048];
	char select[32];

	Format(tips, sizeof(tips), TITLE_STR);

	for(int i = 0; i < title_Num; i++)
	{
		ConVar tempCv = FindConVar(convar_Arr[i]);
		if(tempCv == INVALID_HANDLE)
		{
			continue;
		}
		GetConVarString(tempCv, select, sizeof(select));

		int select_i = 0;
		bool default_flag = false;
		for(int z = 0; z < c_Value_Can_Select[i]; z++)
		{
			if(strcmp(select, c_Value_SelectArr[i][z]) == 0)
			{
				select_i = z;
				break;
			}

			if(!default_flag && strcmp(select, c_Vaule_Default[i]) == 0)
			{
				default_flag = true;
				select_i = z;
			}
		}
		c_Value_NowArr[i] = select_i;

		if(client_showMenu[client])
		{
			client_change[client][i] = select_i;
		}

		char arrow[4] = "   ";
		if(i == client_selecting_line[client])
			Format(arrow, sizeof(arrow), "➢");

		char message[64];
		int changeIndex = client_change[client][i];
		if(changeIndex != c_Value_NowArr[i])
		{
			Format(message, sizeof(message), "● %s", c_Value_MessageArr[i][changeIndex]);
		}
		else
		{
			Format(message, sizeof(message), "○ %s", c_Value_MessageArr[i][changeIndex]);
		}

		Format(tips, sizeof(tips), "%s%s%s:  %s\n", tips, arrow, c_InfoArr[i], message);
	}
	client_showMenu[client] = false;

	SetMenuTitle(menu, "%s\n ", tips);

	char selectStr[16];
	Format(selectStr, sizeof(selectStr), "%s", client_selecting[client] ? "关闭选择" : "进入选择");
	AddMenuItem(menu, "1", selectStr);

	AddMenuItem(menu, "2", "重置菜单");

	int menuStyle = client_selecting[client] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;

	AddMenuItem(menu, "3", "保存模式", menuStyle);

	if(GetUserFlagBits(client) != 0)
	{
		AddMenuItem(menu, "4", "管理员保存", menuStyle);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 0);
}

public int Menu_VotesMode(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		if(item == 0)
		{
			client_selecting[client] = !client_selecting[client];
			client_selecting_line[client] = client_selecting[client] ? 0 : -1;
			CreateVoteModeMenu(client);
		}
		else if(item == 1)
		{
			client_showMenu[client] = true;
			CreateVoteModeMenu(client);
		}
		else if(item == 2)
		{
			client_selecting[client] = false;
			changeMode_client = client;
			if(ChangeModeVote(client))
			{
				FakeClientCommand(client, "Vote Yes");
			}
		}
		else if(item == 3)
		{
			client_selecting[client] = false;
			changeMode_client = client;
			ExecCommand();
		}
	}
}

bool ChangeModeVote(int client)
{
	if (!IsBuiltinVoteInProgress())
	{
		g_hVote = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		
		char sBuffer[256];
		Format(sBuffer, sizeof(sBuffer), "执行 ");

		int changeNum = 0;
		for(int i = 0; i < title_Num; i++)
		{
			int nowIndex = c_Value_NowArr[i];
			int newIndex = client_change[changeMode_client][i];
			if(nowIndex != newIndex)
			{
				changeNum++;
				Format(sBuffer, sizeof(sBuffer), "%s  %s : %s , ", sBuffer, c_InfoArr[i], c_Value_MessageArr[i][newIndex]);
			}
		}
		if(changeNum == 0)
		{
			PrintToChat(changeMode_client, "模式没有改动");
			return false;
		}

		SetBuiltinVoteArgument(g_hVote, sBuffer);
		SetBuiltinVoteInitiator(g_hVote, client);
		SetBuiltinVoteResultCallback(g_hVote, ModeVoteResultHandler);
		DisplayBuiltinVoteToAll(g_hVote, 20);
		PrintToChatAll("\x04%N \x03发起了一个投票", client);
		return true;
	}
	PrintToChat(client, "已经有一个投票正在进行.");
	return false;
}

public void ModeVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	int success = 0;
	for (int i = 0; i < num_items; i++)
	{
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
		{
			success++;
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] >= (num_clients * 0.6))
			{
				DisplayBuiltinVotePass(vote, "模式正在更改");
				ExecCommand();
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

void ExecCommand()
{
	bool rebootFlag = false;
	bool rereadFlag = false;
	for(int i = 0; i < title_Num; i++)
	{
		int nowIndex = c_Value_NowArr[i]; 		int newIndex = client_change[changeMode_client][i]; 		if(nowIndex != newIndex)
		{
			if(!rebootFlag && (c_After_Reboot[i][newIndex] || c_After_Reboot[i][nowIndex]))
			{
				rebootFlag = true;
			}
			if(!rereadFlag && c_After_ReRead[i][newIndex])
			{
				rereadFlag = true;
			}
			ServerCommand("%s", c_Value_ExecArr[i][newIndex]);
			PrintToChatAll("\x03[提示] \x01%s:  \x05%s\x01 -> \x04%s", c_InfoArr[i], c_Value_MessageArr[i][nowIndex], c_Value_MessageArr[i][newIndex]);
		}
	}
	if(rebootFlag)
	{
        PrintToChatAll("\x05本关5s后重启...");
        CreateTimer(5.0, Timer_Reboot);
	}
	if(rereadFlag)
	{
        CreateTimer(0.1, Timer_ReRead);
	}
}

public Action Timer_Reboot(Handle timer)
{
    char sMapName[256];
	GetCurrentMap(sMapName, sizeof(sMapName));
	ServerCommand("changelevel %s", sMapName);
    return Plugin_Continue;
}

public Action Timer_ReRead(Handle timer)
{
    Cmd_ReloadCfg(0,0);
	PrintToChatAll("\x05!cm已刷新...");
    return Plugin_Continue;
}

public void OnClientDisconnect_Post(int client)
{
    g_LastButtons[client] = 0;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if(client_selecting[client])
	{
		for (int i = 0; i < MAX_BUTTONS; i++)
		{
			int button = (1 << i);

			if((buttons & button) && !(g_LastButtons[client] & button))
			{
				int line = client_selecting_line[client];
				int maxLine = title_Num - 1;
				if(buttons & IN_FORWARD)
				{
					if(line == 0)
					{
						line = maxLine;
					}
					else
					{
						line--;
					}
				}
				else if(buttons & IN_BACK)
				{
					if(line == maxLine)
					{
						line = 0;
					}
					else
					{
						line++;
					}
				}
				else if(buttons & IN_MOVELEFT)
				{
					if(client_change[client][line] == 0)
					{
							client_change[client][line] = c_Value_Can_Select[line] - 1;
					}
					else
					{
						client_change[client][line]--;
					}
				}
				else if(buttons & IN_MOVERIGHT)
				{
					if(client_change[client][line] == c_Value_Can_Select[line] - 1)
					{
							client_change[client][line] = 0;
					}
					else
					{
						client_change[client][line]++;
					}
				}

				client_selecting_line[client] = line;
				CreateVoteModeMenu(client);
				break;
			}
		}

		g_LastButtons[client] = buttons;
	}
	return Plugin_Continue;
}



public Action Command_Voteskick(int client, int args)
{
	if(client != 0 && client <= MaxClients) 
	{
		CreateVotekickMenu(client);
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

void CreateVotekickMenu(int client)
{	
	Menu menu = CreateMenu(Menu_Voteskick);		
	char name[MAX_NAME_LENGTH];
	char info[MAX_NAME_LENGTH + 6];
	char playerid[32];
	SetMenuTitle(menu, "选择踢出玩家");
	for(int i = 1;i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			Format(playerid,sizeof(playerid),"%i",GetClientUserId(i));
			if(GetClientName(i,name,sizeof(name)))
			{
				Format(info, sizeof(info), "%s",  name);
				AddMenuItem(menu, playerid, info);
			}
		}		
	}
	DisplayMenu(menu, client, 30);
}

public int Menu_Voteskick(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		char name[32];
		GetMenuItem(menu, param2, info, sizeof(info), _, name, sizeof(name));
		kickplayerinfo = info;
		kickplayername = name;
		PrintToChatAll("\x04%N 发起投票踢出 \x05 %s", param1, kickplayername);
		if(DisplayVoteKickMenu(param1)) FakeClientCommand(param1, "Vote Yes");
		
	}
}

public bool DisplayVoteKickMenu(int client)
{
	if (!IsBuiltinVoteInProgress())
	{
		int iNumPlayers;
		int iPlayers[MAXPLAYERS + 1];
		
		for (int i = 1; i <= MAXPLAYERS + 1; i++)
		{
			if (IsValidEntity(i) || !IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}
			iPlayers[iNumPlayers++] = i;
		}
		char sBuffer[64];
		g_hVoteKick = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		Format(sBuffer, sizeof(sBuffer), "踢出 '%s' ?", kickplayername);
		SetBuiltinVoteArgument(g_hVoteKick, sBuffer);
		SetBuiltinVoteInitiator(g_hVoteKick, client);
		SetBuiltinVoteResultCallback(g_hVoteKick, VoteResultHandler);
		DisplayBuiltinVoteToAll(g_hVoteKick, 20);
		PrintToChatAll("\x04%N \x03发起了一个投票", client);
		return true;
	}
	PrintToChat(client, "已经有一个投票正在进行.");
	return false;
}
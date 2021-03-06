/*
 * shavit's Timer - Player Stats
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#include <sourcemod>
#include <cstrike>
#include <geoip>

#undef REQUIRE_PLUGIN
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

// macros
#define MAPSDONE 0
#define MAPSLEFT 1

// modules
bool gB_Rankings = false;

// database handle
Database gH_SQL = null;

// table prefix
char gS_MySQLPrefix[32];

// cache
int gI_MapType[MAXPLAYERS+1];
BhopStyle gBS_Style[MAXPLAYERS+1];
char gS_TargetAuth[MAXPLAYERS+1][32];
char gS_TargetName[MAXPLAYERS+1][MAX_NAME_LENGTH];
int gI_WRAmount[MAXPLAYERS+1];

bool gB_Late = false;

// cvars
ConVar gCV_MVPRankOnes = null;

// cached cvars
int gI_MVPRankOnes = 2;

// timer settings
int gI_Styles = 0;
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

public Plugin myinfo =
{
	name = "[shavit] Player Stats",
	author = "shavit",
	description = "Player stats for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// natives
	CreateNative("Shavit_OpenStatsMenu", Native_OpenStatsMenu);
	CreateNative("Shavit_GetWRCount", Native_GetWRConut);

	RegPluginLibrary("shavit-stats");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("shavit-wr"))
	{
		SetFailState("shavit-wr is required for the plugin to work.");
	}

	gB_Rankings = LibraryExists("shavit-rankings");
}

public void OnPluginStart()
{
	// player commands
	RegConsoleCmd("sm_profile", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");
	RegConsoleCmd("sm_stats", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");

	// translations
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-stats.phrases");

	// hooks
	HookEvent("player_spawn", Player_Event);
	HookEvent("player_team", Player_Event);

	// cvars
	gCV_MVPRankOnes = CreateConVar("shavit_stats_mvprankones", "2", "Set the players' amount of MVPs to the amount of #1 times they have.\n0 - Disabled\n1 - Enabled, for all styles.\n2 - Enabled, for default style only.", 0, true, 0.0, true, 2.0);

	gCV_MVPRankOnes.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// database connections
	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();
}

public void OnMapStart()
{
	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(view_as<BhopStyle>(i), gA_StyleSettings[i]);
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sStyleName, gS_StyleStrings[i][sStyleName], 128);
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sShortName, gS_StyleStrings[i][sShortName], 128);
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		Shavit_GetChatStrings(i, gS_ChatStrings[i], 128);
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_MVPRankOnes = gCV_MVPRankOnes.IntValue;
}

public void OnClientPutInServer(int client)
{
	gI_WRAmount[client] = 0;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

Action SetSQLInfo()
{
	if(gH_SQL == null)
	{
		Shavit_GetDB(gH_SQL);

		CreateTimer(0.5, CheckForSQLInfo);
	}

	else
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void SQL_SetPrefix()
{
	char[] sFile = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	else
	{
		char[] sLine = new char[PLATFORM_MAX_PATH*2];

		while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
		{
			TrimString(sLine);
			strcopy(gS_MySQLPrefix, 32, sLine);

			break;
		}
	}

	delete fFile;
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsValidClient(client) && !IsFakeClient(client))
	{
		UpdateWRs(client);
	}
}

public void Shavit_OnFinish_Post(int client)
{
	UpdateWRs(client);
}

public void Shavit_OnWorldRecord(int client)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i, true))
		{
			UpdateWRs(i);
		}
	}
}

void UpdateWRs(int client)
{
	if(gH_SQL == null)
	{
		return;
	}

	char[] sAuthID = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID, 32))
	{
		char[] sQuery = new char[256];

		if(gI_MVPRankOnes == 2)
		{
			FormatEx(sQuery, 256, "SELECT COUNT(*) FROM (SELECT s.auth FROM (SELECT style, auth, MIN(time) FROM %splayertimes GROUP BY map, style) s WHERE style = 0) ss WHERE ss.auth = '%s' LIMIT 1;", gS_MySQLPrefix, sAuthID);

		}

		else
		{
			FormatEx(sQuery, 256, "SELECT COUNT(*) FROM (SELECT s.auth FROM (SELECT auth, MIN(time) FROM %splayertimes GROUP BY map, style) s) ss WHERE ss.auth = '%s' LIMIT 1;", gS_MySQLPrefix, sAuthID);
		}

		gH_SQL.Query(SQL_GetWRs_Callback, sQuery, GetClientSerial(client));
	}
}

public void SQL_GetWRs_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get WR amount) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0 || !results.FetchRow())
	{
		return;
	}

	int iWRs = results.FetchInt(0);

	if(gI_MVPRankOnes > 0)
	{
		CS_SetMVPCount(client, iWRs);
	}

	gI_WRAmount[client] = iWRs;
}

public Action Command_Profile(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	int target = client;

	if(args > 0)
	{
		char[] sArgs = new char[64];
		GetCmdArgString(sArgs, 64);

		target = FindTarget(client, sArgs, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	GetClientAuthId(target, AuthId_Steam3, gS_TargetAuth[client], 32);

	return OpenStatsMenu(client, gS_TargetAuth[client]);
}

Action OpenStatsMenu(int client, const char[] authid)
{
	// big ass query, looking for optimizations
	char[] sQuery = new char[2048];

	if(gB_Rankings)
	{
		FormatEx(sQuery, 2048, "SELECT a.clears, b.maps, c.wrs, d.name, d.country, d.lastlogin, d.points, e.rank FROM " ...
				"(SELECT COUNT(*) clears FROM (SELECT id FROM %splayertimes WHERE auth = '%s' GROUP BY map) s LIMIT 1) a " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT id FROM %smapzones GROUP BY map) s LIMIT 1) b " ...
				"JOIN (SELECT COUNT(*) wrs FROM (SELECT s.auth FROM (SELECT style, auth, MIN(time) FROM %splayertimes GROUP BY map, style) s WHERE style = 0) ss WHERE ss.auth = '%s' LIMIT 1) c " ...
				"JOIN (SELECT name, country, lastlogin, points FROM %susers WHERE auth = '%s' LIMIT 1) d " ...
				"JOIN (SELECT COUNT(*) rank FROM %susers WHERE points >= (SELECT points FROM %susers WHERE auth = '%s' LIMIT 1) ORDER BY points DESC LIMIT 1) e " ...
			"LIMIT 1;", gS_MySQLPrefix, authid, gS_MySQLPrefix, gS_MySQLPrefix, authid, gS_MySQLPrefix, authid, gS_MySQLPrefix, gS_MySQLPrefix, authid);
	}

	else
	{
		FormatEx(sQuery, 2048, "SELECT a.clears, b.maps, c.wrs, d.name, d.country, d.lastlogin FROM " ...
				"(SELECT COUNT(*) clears FROM (SELECT id FROM %splayertimes WHERE auth = '%s' GROUP BY map) s LIMIT 1) a " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT id FROM %smapzones GROUP BY map) s LIMIT 1) b " ...
				"JOIN (SELECT COUNT(*) wrs FROM (SELECT s.auth FROM (SELECT style, auth, MIN(time) FROM %splayertimes GROUP BY map, style) s WHERE style = 0) ss WHERE ss.auth = '%s' LIMIT 1) c " ...
				"JOIN (SELECT name, country, lastlogin FROM %susers WHERE auth = '%s' LIMIT 1) d " ...
			"LIMIT 1;", gS_MySQLPrefix, authid, gS_MySQLPrefix, gS_MySQLPrefix, authid, gS_MySQLPrefix, authid);
	}

	gH_SQL.Query(OpenStatsMenuCallback, sQuery, GetClientSerial(client));

	return Plugin_Handled;
}

public void OpenStatsMenuCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (statsmenu) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		// create variables
		int iClears = results.FetchInt(0);
		int iTotalMaps = results.FetchInt(1);
		int iWRs = results.FetchInt(2);
		results.FetchString(3, gS_TargetName[client], MAX_NAME_LENGTH);

		char[] sCountry = new char[64];
		results.FetchString(4, sCountry, 64);

		int iLastLogin = results.FetchInt(5);
		char[] sLastLogin = new char[32];
		FormatTime(sLastLogin, 32, "%Y-%m-%d %H:%M:%S", iLastLogin);
		Format(sLastLogin, 32, "%T: %s", "LastLogin", client, (iLastLogin != -1)? sLastLogin:"N/A");

		int iRank = -1;
		float fPoints = -1.0;

		if(gB_Rankings)
		{
			fPoints = results.FetchFloat(6);
			iRank = results.FetchInt(7);
		}

		char[] sRankingString = new char[64];

		if(gB_Rankings)
		{
			if(iRank > 0 && fPoints > 0.0)
			{
				FormatEx(sRankingString, 64, "\n%T: #%d/%d\n%T: %.02f", "Rank", client, iRank, Shavit_GetRankedPlayers(), "Points", client, fPoints);
			}

			else
			{
				FormatEx(sRankingString, 64, "\n%T: %T", "Rank", client, "PointsUnranked", client);
			}
		}

		if(iClears > iTotalMaps)
		{
			iClears = iTotalMaps;
		}

		char[] sClearString = new char[128];
		FormatEx(sClearString, 128, "%T: %d/%d (%.01f%%)", "MapCompletions", client, iClears, iTotalMaps, ((float(iClears) / iTotalMaps) * 100.0));

		Menu m = new Menu(MenuHandler_ProfileHandler);
		m.SetTitle("%s's %T. %s\n%T: %s\n%s\n%s\n[%s] %T: %d%s\n", gS_TargetName[client], "Profile", client, gS_TargetAuth[client], "Country", client, sCountry, sLastLogin, sClearString, gS_StyleStrings[0][sStyleName], "WorldRecords", client, iWRs, sRankingString);

		for(int i = 0; i < gI_Styles; i++)
		{
			if(gA_StyleSettings[i][bUnranked])
			{
				continue;
			}

			char[] sInfo = new char[4];
			IntToString(i, sInfo, 4);

			m.AddItem(sInfo, gS_StyleStrings[i][sStyleName]);
		}

		// should NEVER happen
		if(m.ItemCount == 0)
		{
			char[] sMenuItem = new char[64];
			FormatEx(sMenuItem, 64, "%T", "NoRecords", client);
			m.AddItem("-1", sMenuItem);
		}

		m.ExitButton = true;
		m.Display(client, 20);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "StatsMenuFailure", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
	}
}

public int MenuHandler_ProfileHandler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[32];
		char[] sMenuItem = new char[64];

		m.GetItem(param2, sInfo, 32);

		gBS_Style[param1] = view_as<BhopStyle>(StringToInt(sInfo));

		Menu menu = new Menu(MenuHandler_TypeHandler);
		menu.SetTitle("%T", "MapsMenu", param1, gS_StyleStrings[gBS_Style[param1]][sShortName]);

		FormatEx(sMenuItem, 64, "%T", "MapsDone", param1);
		menu.AddItem("0", sMenuItem);
		FormatEx(sMenuItem, 64, "%T", "MapsLeft", param1);
		menu.AddItem("1", sMenuItem);

		menu.ExitBackButton = true;
		menu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public int MenuHandler_TypeHandler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);
		gI_MapType[param1] = StringToInt(sInfo);

		ShowMaps(param1);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStatsMenu(param1, gS_TargetAuth[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public Action Timer_DBFailure(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return Plugin_Stop;
	}

	ShowMaps(client);

	return Plugin_Stop;
}

void ShowMaps(int client)
{
	// database not found, display with a 3 seconds delay
	if(gH_SQL == null)
	{
		CreateTimer(3.0, Timer_DBFailure, GetClientSerial(client));

		return;
	}

	char[] sQuery = new char[512];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sQuery, 512, "SELECT a.map, a.time, a.jumps, a.id, COUNT(b.map) + 1 rank, a.points FROM %splayertimes a LEFT JOIN %splayertimes b ON a.time > b.time AND a.map = b.map AND a.style = b.style WHERE a.auth = '%s' AND a.style = %d GROUP BY a.map ORDER BY a.%s;", gS_MySQLPrefix, gS_MySQLPrefix, gS_TargetAuth[client], view_as<int>(gBS_Style[client]), (gB_Rankings)? "points":"map");
	}

	else
	{
		FormatEx(sQuery, 512, "SELECT DISTINCT m.map FROM %smapzones m LEFT JOIN %splayertimes r ON r.map = m.map AND r.auth = '%s' AND r.style = %d WHERE r.map IS NULL ORDER BY m.map;", gS_MySQLPrefix, gS_MySQLPrefix, gS_TargetAuth[client], view_as<int>(gBS_Style[client]));
	}

	gH_SQL.Query(ShowMapsCallback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void ShowMapsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (ShowMaps SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	int rows = results.RowCount;

	char[] sTitle = new char[64];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sTitle, 64, "%T", "MapsDoneFor", client, gS_StyleStrings[gBS_Style[client]][sShortName], gS_TargetName[client], rows);
	}

	else
	{
		FormatEx(sTitle, 64, "%T", "MapsLeftFor", client, gS_StyleStrings[gBS_Style[client]][sShortName], gS_TargetName[client], rows);
	}

	Menu m = new Menu(MenuHandler_ShowMaps);
	m.SetTitle(sTitle);

	while(results.FetchRow())
	{
		char[] sMap = new char[192];
		results.FetchString(0, sMap, 192);
		GetMapDisplayName(sMap, sMap, 192);

		char[] sRecordID = new char[16];
		char[] sDisplay = new char[256];

		if(gI_MapType[client] == MAPSDONE)
		{
			float fTime = results.FetchFloat(1);
			int iJumps = results.FetchInt(2);
			int iRank = results.FetchInt(4);

			char[] sTime = new char[32];
			FormatSeconds(fTime, sTime, 32);

			float fPoints = results.FetchFloat(5);

			if(gB_Rankings && fPoints > 0.0)
			{
				FormatEx(sDisplay, 192, "[#%d] %s - %s (%.03f %T)", iRank, sMap, sTime, fPoints, "MapsPoints", client);
			}

			else
			{
				FormatEx(sDisplay, 192, "[#%d] %s - %s (%d %T)", iRank, sMap, sTime, iJumps, "MapsJumps", client);
			}

			int iRecordID = results.FetchInt(3);
			IntToString(iRecordID, sRecordID, 16);
		}

		else
		{
			strcopy(sDisplay, 192, sMap);
			strcopy(sRecordID, 16, "nope");
		}

		m.AddItem(sRecordID, sDisplay);
	}

	if(m.ItemCount == 0)
	{
		char[] sMenuItem = new char[64];
		FormatEx(sMenuItem, 64, "%T", "NoResults", client);
		m.AddItem("nope", sMenuItem);
	}

	m.ExitBackButton = true;

	m.Display(client, 60);
}

public int MenuHandler_ShowMaps(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[16];
		m.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "nope"))
		{
			OpenStatsMenu(param1, gS_TargetAuth[param1]);

			return 0;
		}

		char[] sQuery = new char[512];
		FormatEx(sQuery, 512, "SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map, p.strafes, p.sync, p.points FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.id = '%s' LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, sInfo);

		gH_SQL.Query(SQL_SubMenu_Callback, sQuery, GetClientSerial(param1));
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStatsMenu(param1, gS_TargetAuth[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (STATS SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Menu m = new Menu(SubMenu_Handler);

	char[] sName = new char[MAX_NAME_LENGTH];
	char[] sAuthID = new char[32];
	char[] sMap = new char[256];

	if(results.FetchRow())
	{
		// 0 - name
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		// 1 - time
		float fTime = results.FetchFloat(1);
		char[] sTime = new char[16];
		FormatSeconds(fTime, sTime, 16);

		char[] sDisplay = new char[128];
		FormatEx(sDisplay, 128, "%T: %s", "Time", client, sTime);
		m.AddItem("-1", sDisplay);

		// 2 - jumps
		int iJumps = results.FetchInt(2);
		FormatEx(sDisplay, 128, "%T: %d", "Jumps", client, iJumps);
		m.AddItem("-1", sDisplay);

		// 3 - style
		BhopStyle bsStyle = view_as<BhopStyle>(results.FetchInt(3));
		FormatEx(sDisplay, 128, "%T: %s", "Style", client, gS_StyleStrings[bsStyle][sStyleName]);
		m.AddItem("-1", sDisplay);

		// 4 - steamid3
		results.FetchString(4, sAuthID, 32);

		// 6 - map
		results.FetchString(6, sMap, 256);

		float fPoints = results.FetchFloat(9);

		if(gB_Rankings && fPoints > 0.0)
		{
			FormatEx(sDisplay, 192, "%T: %.03f", "Points", client, fPoints);
			m.AddItem("-1", sDisplay);
		}

		// 5 - date
		char[] sDate = new char[32];
		results.FetchString(5, sDate, 32);

		if(sDate[4] != '-')
		{
			FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", StringToInt(sDate));
		}

		FormatEx(sDisplay, 128, "%T: %s", "Date", client, sDate);
		m.AddItem("-1", sDisplay);

		int iStrafes = results.FetchInt(7);
		float fSync = results.FetchFloat(8);

		if(iJumps > 0 || iStrafes > 0)
		{
			FormatEx(sDisplay, 128, (fSync > 0.0)? "%T: %d (%.02f%%)":"%T: %d", "Strafes", client, iStrafes, fSync, "Strafes", client, iStrafes);
			m.AddItem("-1", sDisplay);
		}

		GetMapDisplayName(sMap, sMap, 256);
	}

	char[] sFormattedTitle = new char[256];
	FormatEx(sFormattedTitle, 256, "%s %s\n--- %s:", sName, sAuthID, sMap);

	m.SetTitle(sFormattedTitle);

	m.ExitBackButton = true;
	m.Display(client, 20);
}

public int SubMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowMaps(param1);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public int Native_OpenStatsMenu(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	GetNativeString(2, gS_TargetAuth[client], 32);

	OpenStatsMenu(client, gS_TargetAuth[client]);
}

public int Native_GetWRConut(Handle handler, int numParams)
{
	return gI_WRAmount[GetNativeCell(1)];
}

public void Shavit_OnDatabaseLoaded(Database db)
{
	gH_SQL = db;
}

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <clientprefs>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

//Define version number in a needlessly complex way
#define MAJOR	"1"
#define MINOR	"0"
#define PATCH	"0"
#define PLUGIN_VERSION	MAJOR..."."...MINOR..."."...PATCH

//Debug "Mode"
// #define DEBUG	//Uncomment for "debug" stuff. Just some 'PrintToChatAll's here and there.

//Enums
enum PadCond (<<= 1)	//Custom Conditions - Use Pad_IsPlayerInCond() to see if a Custom Condition is active on a player.
{
	PadCond_None = 0,		// 0 << 0 = 0
	PadCond_Boost = 1,		// 1 << 0 = 1
	PadCond_NoFallDmg,		// 1 << 1 = 2
	PadCond_DelayResponse	// 1 << 2 = 4
}

enum //Custom ObjectType
{
	PadType_None = 0,
	PadType_Boost,
	PadType_Jump
}

enum //Teleporter states
{
	TELEPORTER_STATE_BUILDING = 0,				// Building, not active yet
	TELEPORTER_STATE_IDLE,						// Does not have a matching teleporter yet
	TELEPORTER_STATE_READY,						// Found match, charged and ready
	TELEPORTER_STATE_SENDING,					// Teleporting a player away
	TELEPORTER_STATE_RECEIVING,					
	TELEPORTER_STATE_RECEIVING_RELEASE,
	TELEPORTER_STATE_RECHARGING,				// Waiting for recharge
	TELEPORTER_STATE_UPGRADING					// Upgrading
}

enum //CvarName
{
	PadsEnabled,
	PadsAnnounce,
	PadSize,
	PadHealth,
	JumpSpeed,
	JumpHeight,
	JumpCrouchSpeedMult,
	JumpCrouchHeightMult,
	JumpBlockSnipers,
	JumpCooldown,
	BoostDuration,
	BoostSpeed,
	BoostBlockAiming,
	BoostCooldown,
	BotsCanBuild,
	BlockEureka,
	VersionNumber
}

enum //Plugin Enabled states
{
	EngiPads_Disabled,
	EngiPads_Enabled,
	EngiPads_BoostOnly,
	EngiPads_JumpOnly
}

enum //Menu Exit Enable states
{
	EngiPads_MenuExitOff,
	EngiPads_MenuExitOn
}

/* Global vars */
static int g_iPadType[2048];
static int g_iObjectParticle[2048];
static PadCond g_fPadCondFlags[MAXPLAYERS + 1];

static char g_szOffsetStartProp[64];
static int g_iOffsetMatchingTeleporter = -1;

static Handle g_hPadCookie;
static Handle g_hPadTimerAnnounce;

/* Global bool */
bool g_bMenuExitEnabled = false;

/* Convars */
ConVar cvarPads[VersionNumber + 1];


public Plugin myinfo =
{
	name 			= "[TF2] Engineer Pads",
	author 			= "Starblaster 64",
	description 	= "Custom Teleporter building replacements.",
	version 		= PLUGIN_VERSION,
	url 			= "https://forums.alliedmods.net/showthread.php?t=304025"
};

//Initialise gamedata to be used for getting/setting Teleporter pairs.
void InitGamedata()
{
	Handle hGameConf = LoadGameConfigFile("tf2.teleporters");
	if (hGameConf == INVALID_HANDLE)
	{
		SetFailState("[EngiPads] Unable to load gamedata file 'tf2.teleporters.txt'");
	}
	
	bool bFoundProp = GameConfGetKeyValue(hGameConf, "StartProp", g_szOffsetStartProp, sizeof(g_szOffsetStartProp));
	g_iOffsetMatchingTeleporter = GameConfGetOffset(hGameConf, "m_hMatchingTeleporter");
	
	if (!bFoundProp || g_iOffsetMatchingTeleporter < 0)
	{
		SetFailState("[EngiPads] Unable to get m_hMatchingTeleporter offset from 'tf2.teleporters.txt'. Check gamedata!");
	}
	
	CloseHandle(hGameConf);
}

public void OnPluginStart()
{
	InitGamedata();
	
	RegConsoleCmd("sm_pad", TogglePadsMenuCmd);
	RegConsoleCmd("sm_pads", TogglePadsMenuCmd);
	RegConsoleCmd("sm_pad_help", ShowPadsInfoCmd);
	RegConsoleCmd("sm_padhelp", ShowPadsInfoCmd);
	
	AddCommandListener(EurekaTeleport, "eureka_teleport");
	
	cvarPads[VersionNumber] = CreateConVar("pads_version", PLUGIN_VERSION, "EngiPads version number. Don't touch this!", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_CHEAT);
	cvarPads[PadsEnabled] = CreateConVar("pads_enabled", "1", "Enables/Disables the plugin. (2 - BoostPads only, 3 - JumpPads only)", FCVAR_NOTIFY, true, 0.0, true, 3.0);
	cvarPads[PadsAnnounce] = CreateConVar("pads_announce", "347.0", "Interval between chat announcements about the plugin. 0.0 to disable.", FCVAR_NOTIFY, true, 0.0);
	
	cvarPads[PadSize] = CreateConVar("pads_size", "0.7", "Pad size multiplier.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	cvarPads[PadHealth] = CreateConVar("pads_health", "100", "How much HP Pads will have.", FCVAR_NOTIFY, true, 1.0);
	cvarPads[JumpSpeed] = CreateConVar("pads_jump_speed", "700.0", "How fast players will be launched horizontally by Jump Pads.", FCVAR_NOTIFY, true, 0.0);
	cvarPads[JumpHeight] = CreateConVar("pads_jump_height", "700.0", "How fast players will be launched vertically by Jump Pads.", FCVAR_NOTIFY, true, 0.0);
	cvarPads[JumpCrouchSpeedMult] = CreateConVar("pads_jump_crouch_speed_mult", "1.0", "Multiply crouching players' speed by this much when using Jump Pads.", FCVAR_NOTIFY, true, 0.0);
	cvarPads[JumpCrouchHeightMult] = CreateConVar("pads_jump_crouch_height_mult", "1.0", "Multiply crouching players' height by this much when using Jump Pads.", FCVAR_NOTIFY, true, 0.0);
	cvarPads[JumpBlockSnipers] = CreateConVar("pads_jump_block_snipers", "1", "If enabled, prevents Snipers from scoping in while using Jump Pads.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvarPads[JumpCooldown] = CreateConVar("pads_jump_cooldown", "3.0", "How long, in seconds, should Jump Pads take to recharge?", FCVAR_NOTIFY, true, 0.1);
	cvarPads[BoostDuration] = CreateConVar("pads_boost_duration", "5.0", "How long, in seconds, should Boost Pads boost players for?", FCVAR_NOTIFY, true, 0.0);
	cvarPads[BoostSpeed] = CreateConVar("pads_boost_speed", "520.0", "What minimum speed should players be boosted to when using Boost Pads?", FCVAR_NOTIFY, true, 0.0);
	cvarPads[BoostBlockAiming] = CreateConVar("pads_boost_block_aiming", "1", "Set to 1 to prevent scoped-in/revved up players from being speed boosted.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvarPads[BoostCooldown] = CreateConVar("pads_boost_cooldown", "3.0", "How long in seconds should Boost Pads take to recharge?", FCVAR_NOTIFY, true, 0.1);
	cvarPads[BotsCanBuild] = CreateConVar("pads_bots_can_build", "0", "If enabled, Bots will build Boost Pads instead of Teleporters.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvarPads[BlockEureka] = CreateConVar("pads_block_eureka", "1", "Toggle blocking Eureka Effect from teleporting to Pads that are Exits.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	cvarPads[MenuExit] = CreateConVar("pads_menu_exit_type", "0", "Provides the option for servers to display or hide the exit button.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	AutoExecConfig(true, "engipads");
	LoadTranslations("engipads.phrases");
	
	//Cookies
	g_hPadCookie = RegClientCookie("engipads_toggle", "Client's EngiPads toggle preference.", CookieAccess_Protected);
	
	//Hooks
	cvarPads[VersionNumber].AddChangeHook(CvarChange);
	cvarPads[PadsEnabled].AddChangeHook(CvarChange);
	cvarPads[PadsAnnounce].AddChangeHook(CvarChange);
	cvarPads[MenuExit].AddChangeHook(CvarChange);
	
	HookEvent("player_death", PlayerDeath, EventHookMode_Post);
	
	HookEvent("player_builtobject", ObjectBuilt, EventHookMode_Post);
	HookEvent("player_sapped_object", ObjectSapped, EventHookMode_Post);
	HookEvent("player_carryobject", ObjectDestroyed, EventHookMode_Post);
	
	HookEvent("object_destroyed", ObjectDestroyed, EventHookMode_Post);
	HookEvent("object_removed", ObjectDestroyed, EventHookMode_Post);
	
	AddNormalSoundHook(HookSound);
}

public void OnPluginEnd()
{
	ConvertAllPadsToTeleporters(); //Convert all Pads back to teleporters if the plugin is unloaded.
}

public void OnConfigsExecuted()
{
	/* Version checker taken from VSH */
	static char szOldVersion[12];
	cvarPads[VersionNumber].GetString(szOldVersion, sizeof(szOldVersion));
	if (!StrEqual(szOldVersion, PLUGIN_VERSION))
		cvarPads[VersionNumber].SetString(PLUGIN_VERSION, false, true);
	
	if (cvarPads[PadsEnabled].IntValue > EngiPads_Disabled && cvarPads[PadsAnnounce].FloatValue > 0.0)
	{
		g_hPadTimerAnnounce = CreateTimer(cvarPads[PadsAnnounce].FloatValue, Timer_PadsAnnounce, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	if (cvarPads[MenuExit].IntValue == EngiPads_MenuExitOff)
		g_bMenuExitEnabled = false;

	if (cvarPads[MenuExit].IntValue == EngiPads_MenuExitOn || cvarPads[MenuExit].IntValue > EngiPads_MenuExitOn)
		g_bMenuExitEnabled = true;
}

public void CvarChange(ConVar cvar, const char[] szOldValue, const char[] szNewValue)
{
	if (cvar == cvarPads[VersionNumber])
	{
		if (!StrEqual(szNewValue, PLUGIN_VERSION))
			cvarPads[VersionNumber].SetString(PLUGIN_VERSION);	//If config version number does not match plugin, plugin will override it.
	}
	else if (cvar == cvarPads[PadsEnabled])
	{
		if (RoundToFloor(StringToFloat(szNewValue)) == EngiPads_Disabled && RoundToFloor(StringToFloat(szOldValue)) > EngiPads_Disabled)
		{
			ConvertAllPadsToTeleporters();
			ClearTimer(g_hPadTimerAnnounce);
		}
		else if (cvarPads[PadsAnnounce].FloatValue > 0.0 && RoundToFloor(StringToFloat(szOldValue)) == EngiPads_Disabled)
		{
			ClearTimer(g_hPadTimerAnnounce);
			g_hPadTimerAnnounce = CreateTimer(cvarPads[PadsAnnounce].FloatValue, Timer_PadsAnnounce, _, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	else if (cvar == cvarPads[PadsAnnounce])
	{
		if (StringToFloat(szNewValue) > 0.0 && cvarPads[PadsEnabled].IntValue > EngiPads_Disabled)
		{
			ClearTimer(g_hPadTimerAnnounce);
			g_hPadTimerAnnounce = CreateTimer(cvarPads[PadsAnnounce].FloatValue, Timer_PadsAnnounce, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		else if (StringToFloat(szNewValue) <= 0.0)
		{
			ClearTimer(g_hPadTimerAnnounce);
		}
	}
	
	else if (cvar == cvarPads[MenuExit])
	{
		if (StringToInt(szNewValue) == EngiPads_MenuExitOn && StringToInt(szOldValue) == EngiPads_MenuExitOff)
			g_bMenuExitEnabled = true;

		else if (StringToInt(szNewValue) == EngiPads_MenuExitOff && StringToInt(szOldValue) == EngiPads_MenuExitOn)
			g_bMenuExitEnabled = false;

		else if (StringToInt(szNewValue) > EngiPads_MenuExitOn)
			g_bMenuExitEnabled = true;
	}
}

public Action Timer_PadsAnnounce(Handle hTimer)
{
	if (cvarPads[PadsEnabled].IntValue == EngiPads_Disabled || cvarPads[PadsAnnounce].FloatValue <= 0.0)
	{
		g_hPadTimerAnnounce = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	int iAnnouncement = GetRandomInt(0, 5);
	
	switch (iAnnouncement)
	{
		case 0:
		{
			CPrintToChatAll("{orange}[EngiPads]{default} %t", "padphrase_announcement1", PLUGIN_VERSION);
		}
		default:
		{
			CPrintToChatAll("{orange}[EngiPads]{default} %t", "padphrase_announcement2");
		}
	}
	
	g_hPadTimerAnnounce = CreateTimer(cvarPads[PadsAnnounce].FloatValue, Timer_PadsAnnounce, _, TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Handled;
}

public void OnMapStart()
{
	g_hPadTimerAnnounce = INVALID_HANDLE;
	
	/* Precache Sounds */
	PrecacheSound(")items/powerup_pickup_haste.wav", true);	//For some reason, using PrecacheScriptSound doesn't work for this sound.
	PrecacheScriptSound("Passtime.BallSmack");
	//The other gamesounds I emit should already be precached by the game
	
	/* Precache Particles */
	PrecacheParticleSystem("powerup_icon_haste_red");
	PrecacheParticleSystem("powerup_icon_haste_blue");
	
	PrecacheParticleSystem("powerup_icon_agility_red");
	PrecacheParticleSystem("powerup_icon_agility_blue");
}

public void OnMapEnd()
{
	ClearTimer(g_hPadTimerAnnounce);
}

public void OnClientPostAdminCheck(int iClient)
{
	//Reset players' custom conditions on connect
	Pad_SetConds(iClient, PadCond_None);
}

public void OnClientDisconnect(int iClient)
{
	Pad_SetConds(iClient, PadCond_None);
}

public void PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	Pad_SetConds(iClient, PadCond_None);
}

public void ObjectBuilt(Event event, const char[] name, bool dontBroadcast)
{
	if (view_as<TFObjectType>(event.GetInt("object")) != TFObject_Teleporter)
		return;
	
	int iBuilder = GetClientOfUserId(event.GetInt("userid"));
	int iObj = event.GetInt("index");
	
	if (!GetClientPadsEnabled(iBuilder) || cvarPads[PadsEnabled].IntValue == EngiPads_Disabled || !CheckCommandAccess(iBuilder, "sm_engipads_override", 0))
	{
		if (g_iPadType[iObj])
		{
			ConvertPadToTeleporter(iObj);
		}
		if (TF2_GetMatchingTeleporter(iObj) == iObj)
		{
			TF2_SetMatchingTeleporter(iObj, -1);	//Reset m_hMatchingTeleporter if the buidling is no longer a Pad.
		}
		return;
	}
	
	ConvertTeleporterToPad(iObj, GetPadType(iObj), GetEntProp(iObj, Prop_Send, "m_bCarryDeploy") ? false : true);
	
	PrintPadTypeNameToClient(g_iPadType[iObj], iBuilder);
}

public void ObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
	int iObj = event.GetInt("index");
	if ((view_as<TFObjectType>(event.GetInt("object")) != TFObject_Teleporter && view_as<TFObjectType>(event.GetInt("objecttype")) != TFObject_Teleporter) || !g_iPadType[iObj])
		return;
	
	int iObjParti = EntRefToEntIndex(g_iObjectParticle[iObj]);
	if (IsValidEntity(iObjParti))
		AcceptEntityInput(iObjParti, "Kill");
	g_iObjectParticle[iObj] = -1;
	
	#if defined DEBUG
	PrintToChatAll("%i Destroyed!", iObj);
	#endif
	
	if (!StrEqual(name, "player_carryobject"))
		g_iPadType[iObj] = PadType_None;
}

public void ObjectSapped(Event event, const char[] name, bool dontBroadcast)
{
	int iSapper = event.GetInt("sapperid");
	int iObj = GetEntPropEnt(iSapper, Prop_Send, "m_hBuiltOnEntity");
	
	if (view_as<TFObjectType>(event.GetInt("object")) != TFObject_Teleporter || !g_iPadType[iObj])
		return;
	
	SetVariantInt(GetEntProp(iSapper, Prop_Send, "m_iMaxHealth") * 2);
	AcceptEntityInput(iSapper, "SetHealth", iSapper); //Double Sapper HP. Since I set the Tele's matching Tele to itself, Sappers take 2 instances of damage per hit.
	
	SetEntPropFloat(iSapper, Prop_Send, "m_flModelScale", cvarPads[PadSize].FloatValue);	//Scale down Sapper to match Pad size.
}

public Action HookSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
		int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
		char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (IsValidEntity(entity))
	{
		char className[64];
		GetEntityClassname(entity, className, sizeof(className));
	
		if (StrEqual(className, "obj_attachment_sapper") && TF2_GetObjectType(entity) == TFObject_Sapper && channel == SNDCHAN_STATIC)
		{
			if (GetEntPropEnt(entity, Prop_Send, "m_hBuiltOnEntity") == -1)
			{
				if (StrEqual(sample, "weapons/sapper_timer.wav") || StrContains(sample, "spy_tape") != -1)
				{
					return Plugin_Handled;	//I need to block the duplicate sapping sound otherwise it'll loop forever.
				}
			}
		}
	}
		
	return Plugin_Continue;
}

public Action EurekaTeleport(int iClient, const char[] szCommand, int nArgs)
{
	if (cvarPads[PadsEnabled].IntValue == EngiPads_Disabled || !cvarPads[BlockEureka].BoolValue)
		return Plugin_Continue;
	
	if (IsValidClient(iClient) && IsPlayerAlive(iClient))
	{
		char arg[8]; GetCmdArg(1, arg, sizeof(arg));
		int iDest = StringToInt(arg);
		
		if (iDest != 1 || !GetCmdArgs())	//If teleport destination is not 1 or unspecified (Spawn)
			return Plugin_Continue;
		
		int i = -1;
		while ((i = FindEntityByClassname2(i, "obj_teleporter")) != -1)
		{
			if (IsValidEntity(i) && g_iPadType[i] && TF2_GetObjectMode(i) == TFObjectMode_Exit)
			{
				EmitGameSoundToClient(iClient, "Player.UseDeny", iClient);
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public void OnGameFrame()
{
	if (cvarPads[PadsEnabled].IntValue == EngiPads_Disabled)
		return;
	
	int i = -1;
	while ((i = FindEntityByClassname2(i, "obj_teleporter")) != -1)
	{
		if (IsValidEntity(i))
		{
			if (g_iPadType[i])
				OnPadThink(i);
			
			else if (g_iPadType[i] == PadType_None && !GetEntProp(i, Prop_Send, "m_bWasMapPlaced"))
			{
				int iMatch = TF2_GetMatchingTeleporter(i);
				if (IsValidEntity(iMatch))
				{
					if ((g_iPadType[iMatch] || iMatch == i) && !GetEntProp(i, Prop_Send, "m_bDisabled"))
					{
						TF2_DisableObject(i);	//Disable Teleporters that are matched with Pads.
						if (iMatch != i)
							TF2_SetMatchingTeleporter(i, i);	//Unlink them so upgrades/sappers don't transfer over.
					}
				}
			}
		}
	}
}

void OnPadThink(int iPad)
{
	float flConstructed = GetEntPropFloat(iPad, Prop_Send, "m_flPercentageConstructed");
	bool bBuilding = view_as<bool>(GetEntProp(iPad, Prop_Send, "m_bBuilding"));
	bool bCarried = view_as<bool>(GetEntProp(iPad, Prop_Send, "m_bCarried"));
	bool bPlacing = view_as<bool>(GetEntProp(iPad, Prop_Send, "m_bPlacing"));
	bool bDisabled = view_as<bool>(GetEntProp(iPad, Prop_Send, "m_bDisabled"));
	bool bSapped = view_as<bool>(GetEntProp(iPad, Prop_Send, "m_bHasSapper"));
	
	if (bBuilding && flConstructed < 1.0)
	{
		if (TF2_GetBuildingState(iPad) != TELEPORTER_STATE_BUILDING)
			TF2_SetBuildingState(iPad, TELEPORTER_STATE_BUILDING);
		if (GetEntProp(iPad, Prop_Send, "m_iUpgradeLevel") != 3 && !bSapped)
		{
			SetEntProp(iPad, Prop_Send, "m_iHighestUpgradeLevel", 3);
			SetEntProp(iPad, Prop_Send, "m_iUpgradeLevel", 3);
		}
		return;
	}
	
	int iObjParti = EntRefToEntIndex(g_iObjectParticle[iPad]);
	
	if (bCarried || bPlacing || bDisabled)
	{
		if (bSapped)
		{
			if (GetEntProp(iPad, Prop_Send, "m_iUpgradeLevel") > 1)
			{
				SetEntProp(iPad, Prop_Send, "m_iUpgradeLevel", 1);	//Prevents the Red-Tape Recorder having to downgrade Pads before deconstructing.
				SetEntProp(iPad, Prop_Send, "m_iHighestUpgradeLevel", 1);
			}
		}
		if (IsValidEntity(iObjParti) && GetEntProp(iObjParti, Prop_Send, "m_bActive"))
			AcceptEntityInput(iObjParti, "Stop");
		return;
	}
	
	if (TF2_GetBuildingState(iPad) > TELEPORTER_STATE_BUILDING && TF2_GetBuildingState(iPad) < TELEPORTER_STATE_UPGRADING)
	{
		if (TF2_GetBuildingState(iPad) != TELEPORTER_STATE_READY && GetEntPropFloat(iPad, Prop_Send, "m_flRechargeTime") <= GetGameTime())
		{
			TF2_SetBuildingState(iPad, TELEPORTER_STATE_READY);	//Make sure the Pad always re-activates when it's supposed to.
			
			#if defined DEBUG
			PrintToChatAll("%i Ready!", iPad);
			#endif
		}
		if (TF2_GetBuildingState(iPad) == TELEPORTER_STATE_READY && IsValidEntity(iObjParti) && !GetEntProp(iObjParti, Prop_Send, "m_bActive"))
			AcceptEntityInput(iObjParti, "Start");
	}
	
	float flCooldown;
	switch (g_iPadType[iPad])
	{
		case PadType_Boost:	flCooldown = cvarPads[BoostCooldown].FloatValue;
		case PadType_Jump:	flCooldown = cvarPads[JumpCooldown].FloatValue;
	}
	SetEntPropFloat(iPad, Prop_Send, "m_flCurrentRechargeDuration", flCooldown);
	
	SetEntPropFloat(iPad, Prop_Send, "m_flYawToExit", GetEntPropFloat(iPad, Prop_Send, "m_flYawToExit") + 10.0);	//Make the arrow spin for fun, and to indicate its not a Teleporter (but mostly for fun)
	if (GetEntPropFloat(iPad, Prop_Send, "m_flYawToExit") > 360.0)
		SetEntPropFloat(iPad, Prop_Send, "m_flYawToExit", 0.0);
}

public Action OnPadTouch(int iPad, int iToucher)
{
	if (IsValidClient(iToucher))
	{		
		if (TF2_GetBuildingState(iPad) != TELEPORTER_STATE_READY)
			return Plugin_Continue;
		
		int iPadTeam = GetEntProp(iPad, Prop_Data, "m_iTeamNum");
		int iPadBuilder = GetEntPropEnt(iPad, Prop_Send, "m_hBuilder");
		
		if ((GetClientTeam(iToucher) == iPadTeam ||
			(TF2_GetPlayerClass(iToucher) == TFClass_Spy && TF2_IsPlayerInCondition(iToucher, TFCond_Disguised) && GetEntProp(iToucher, Prop_Send, "m_nDisguiseTeam") == iPadTeam)) &&
			GetEntPropEnt(iToucher, Prop_Send, "m_hGroundEntity") == iPad)
		{
			switch(g_iPadType[iPad])
			{
				case PadType_Boost:
				{
					if (!Pad_AddCond(iToucher, PadCond_Boost))
						return Plugin_Handled;	//Ignore players who already have a boost
					
					float flDur = cvarPads[BoostDuration].FloatValue;
					
					TF2_AddCondition(iToucher, TFCond_SpeedBuffAlly, flDur);
					TF2_AddCondition(iToucher, TFCond_TeleportedGlow, flDur);
					Pad_AddCond(iToucher, PadCond_DelayResponse);
					
					SDKHook(iToucher, SDKHook_PreThink, PreThink);
					CreateTimer(flDur, Timer_EndBoostEffect, EntIndexToEntRef(iToucher), TIMER_FLAG_NO_MAPCHANGE);
					
					TF2_SetBuildingState(iPad, TELEPORTER_STATE_RECEIVING_RELEASE);
					
					SetEntPropFloat(iPad, Prop_Send, "m_flRechargeTime", GetGameTime() + cvarPads[BoostCooldown].FloatValue);
					
					AcceptEntityInput(EntRefToEntIndex(g_iObjectParticle[iPad]), "Stop");
					
					EmitGameSoundToAll("Powerup.PickUpHaste", iToucher);
					EmitGameSoundToAll("Building_Teleporter.Send", iPad);
					
					#if defined DEBUG
					PrintToChatAll("%N Boosted!", iToucher);
					#endif
				}
				case PadType_Jump:
				{
					if (!Pad_AddCond(iToucher, PadCond_NoFallDmg))	//Wait for launched players to be unhooked before re-launching them
						return Plugin_Handled;
					
					TF2_AddCondition(iToucher, TFCond_TeleportedGlow, 5.0);
					Pad_AddCond(iToucher, PadCond_DelayResponse);
					
					RequestFrame(LaunchPlayer, iToucher);
					
					TF2_SetBuildingState(iPad, TELEPORTER_STATE_RECEIVING_RELEASE);
					
					SetEntPropFloat(iPad, Prop_Send, "m_flRechargeTime", GetGameTime() + cvarPads[JumpCooldown].FloatValue);
					
					AcceptEntityInput(EntRefToEntIndex(g_iObjectParticle[iPad]), "Stop");
					
					EmitGameSoundToAll("Passtime.BallSmack", iPad);
					EmitGameSoundToAll("TFPlayer.AirBlastImpact", iPad);
					EmitGameSoundToAll("Building_Teleporter.Send", iPad);
					
					#if defined DEBUG
					PrintToChatAll("%N Launched!", iToucher);
					#endif
				}
			}
			if (iToucher != iPadBuilder)
			{
				SetEntProp(iPad, Prop_Send, "m_iTimesUsed", GetEntProp(iPad, Prop_Send, "m_iTimesUsed") + 1);
				
				if (!(GetEntProp(iPad, Prop_Send, "m_iTimesUsed") % 6)) //Add +2 points every 6 uses
				{
					Event event = CreateEvent("player_escort_score", true);	//Using player_teleported unfortunately does not work.
					if (event != null)
					{
						event.SetInt("player", iPadBuilder);
						event.SetInt("points", 1);	//Not sure why this is adding double points
						event.Fire();
					}
				}
			}
			#if defined DEBUG
			PrintToChatAll("Conds: %i", view_as<int>(Pad_GetConds(iToucher)));
			#endif
		}
		return Plugin_Handled;	//Block client touch events to prevent enemy spies messing stuff up.
	}
	return Plugin_Continue;
}

/* Boost Pad Effects */
public void PreThink(int iClient)
{
	if (!Pad_IsPlayerInCond(iClient, PadCond_Boost))
	{
		if (IsPlayerAlive(iClient))
		{
			TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, 0.01);	//Recalc player's speed so they don't keep the boost forever
			
			if (Pad_IsPlayerInCond(iClient, PadCond_DelayResponse))
			{
				if (!Pad_IsPlayerInCond(iClient, PadCond_NoFallDmg)) //If player is still going to negate fall dmg, they'll need to say thanks later.
				{
					Pad_RemoveCond(iClient, PadCond_DelayResponse);
					TF2_SayTeleportResponse(iClient);
				}
			}
		}
		SDKUnhook(iClient, SDKHook_PreThink, PreThink);
	}
	
	else if (Pad_IsPlayerInCond(iClient, PadCond_Boost))
	{
		float flBoostSpeed = cvarPads[BoostSpeed].FloatValue;
		if (flBoostSpeed && (!TF2_IsPlayerInCondition(iClient, TFCond_Slowed) || !cvarPads[BoostBlockAiming].BoolValue))	//Don't apply speed boost to Revved/Aiming players
		{
			if (GetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed") < flBoostSpeed)
				SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", flBoostSpeed);
		}
	}
}

public Action Timer_EndBoostEffect(Handle hTimer, any iRef)
{
	int iClient = EntRefToEntIndex(iRef);
	
	Pad_RemoveCond(iClient, PadCond_Boost);
	
	return Plugin_Handled;
}

/* Jump Pad Effects */
void LaunchPlayer(int iClient)
{
	float vVel[3], vVel2[3];
	float flMaxSpeed = GetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed");
	float flJumpSpeed = cvarPads[JumpSpeed].FloatValue;
	float flJumpHeight = cvarPads[JumpHeight].FloatValue;
	float flRatio = flJumpSpeed / flMaxSpeed;
	
	GetEntPropVector(iClient, Prop_Data, "m_vecAbsVelocity", vVel);
	
	ScaleVector(vVel, flRatio);  //This ensures all classes will have the same launch distance.
	
	/* Get the horizontal vectors */
	vVel2[0] = vVel[0];
	vVel2[1] = vVel[1];
	
	float flHorizontalSpeed = GetVectorLength(vVel2);
	if (flHorizontalSpeed > flJumpSpeed)
		ScaleVector(vVel, flJumpSpeed / flHorizontalSpeed);
	
	vVel[2] = flJumpHeight;
	if (GetEntityFlags(iClient) & FL_DUCKING)
	{
		ScaleVector(vVel, cvarPads[JumpCrouchSpeedMult].FloatValue);
		vVel[2] = flJumpHeight * cvarPads[JumpCrouchHeightMult].FloatValue;
	}
	
	#if defined DEBUG
	PrintToChatAll("Speed: %.2f (%.0f%%)", flHorizontalSpeed / flRatio, flHorizontalSpeed / flJumpSpeed * 100);
	PrintToChatAll("SpeedLaunch: %.2f", flHorizontalSpeed);
	PrintToChatAll("ScaleVector: %.2f", flJumpSpeed / flHorizontalSpeed);
	PrintToChatAll("Height: %.2f", vVel[2]);
	#endif
	
	if (vVel[2] < 300.0)	//Teleport the player up slightly to allow 'flJumpHeight' values lower than 300.0.
	{
		float vPos[3];
		GetClientAbsOrigin(iClient, vPos);
		vPos[2] += 20.0;
		SetEntPropVector(iClient, Prop_Data, "m_vecAbsOrigin", vPos);
	}
	
	SetEntPropVector(iClient, Prop_Data, "m_vecAbsVelocity", vVel);
	SetEntProp(iClient, Prop_Send, "m_bJumping", cvarPads[JumpBlockSnipers].IntValue);
	
	TF2_AddCondition(iClient, TFCond_GrapplingHookSafeFall, TFCondDuration_Infinite);
	
	SDKHook(iClient, SDKHook_OnTakeDamage, OnPlayerTakeDamage);
}

public Action OnPlayerTakeDamage(int iClient, int &iAttacker, int &iInflictor, float &flDamage, int &iDamageType, int &iWeapon, float flDamageForce[3], float flDamagePosition[3], int iDamageCustom)
{
	if (!IsValidClient(iClient))
		return Plugin_Continue;
	
	if (iDamageType & DMG_FALL && Pad_IsPlayerInCond(iClient, PadCond_NoFallDmg))
	{			
		if (Pad_IsPlayerInCond(iClient, PadCond_DelayResponse))
		{
			if (!Pad_IsPlayerInCond(iClient, PadCond_Boost)) //If player is still being boosted, they'll need to say thanks later.
			{
				Pad_RemoveCond(iClient, PadCond_DelayResponse);
				TF2_SayTeleportResponse(iClient);
			}
		}
		
		TF2_AddCondition(iClient, TFCond_PasstimeInterception, 0.01);
		
		SDKUnhook(iClient, SDKHook_OnTakeDamage, OnPlayerTakeDamage);
		
		#if defined DEBUG
		PrintToChatAll("%N's Fall Damage negated!", iClient);
		#endif
		
		// return Plugin_Handled; //Returning Plugin_Handled causes fall damage sound+blood, which I don't want
	}
	
	return Plugin_Continue;
}

public void TF2_OnConditionRemoved(int iClient, TFCond iCond)
{
	switch (iCond)
	{
		case TFCond_GrapplingHookSafeFall:
		{
			if (Pad_RemoveCond(iClient, PadCond_NoFallDmg))
			{
				SDKUnhook(iClient, SDKHook_OnTakeDamage, OnPlayerTakeDamage);
				
				if (Pad_IsPlayerInCond(iClient, PadCond_DelayResponse))
				{
					if (!Pad_IsPlayerInCond(iClient, PadCond_Boost)) //If player is still being boosted, they'll need to say thanks later.
					{
						Pad_RemoveCond(iClient, PadCond_DelayResponse);
						TF2_SayTeleportResponse(iClient);
					}
				}
				#if defined DEBUG
				PrintToChatAll("%N OTD Unhooked!", iClient);
				#endif
			}
		}
	}
}

/* Pad Creation/Revertion */
void ConvertTeleporterToPad(int iEnt, int iPadType, bool bAddHealth)
{
	g_iPadType[iEnt] = iPadType;
	
	// SetEntityModel(iEnt, "MODEL_PAD");	//Coming soon™, maybe...
	
	SetEntProp(iEnt, Prop_Send, "m_iHighestUpgradeLevel", 3);	//Set Pads to level 3 for cosmetic reasons related to recharging
	SetEntProp(iEnt, Prop_Send, "m_iUpgradeLevel", 3);
	SetEntProp(iEnt, Prop_Send, "m_bMiniBuilding", true);			//Prevent upgrades and metal from gibs
	SetEntProp(iEnt, Prop_Send, "m_iMaxHealth", cvarPads[PadHealth].IntValue);			//Max HP reduced to 100
	if (bAddHealth)
	{
		SetVariantInt(RoundFloat(cvarPads[PadHealth].IntValue * 0.5));
		AcceptEntityInput(iEnt, "AddHealth", iEnt); //Spawns at 50% HP.
		SetEntProp(iEnt, Prop_Send, "m_iTimesUsed", 0);
	}
	
	SetEntProp(iEnt, Prop_Send, "m_nBody", 2);	//Give the arrow to Exits as well.
	SetEntPropFloat(iEnt, Prop_Send, "m_flModelScale", cvarPads[PadSize].FloatValue);
	RequestFrame(ResetSkin, iEnt); //Setting m_bMiniBuilding tries to set the skin to a 'mini' skin. Since teles don't have one, reset the skin.
	
	g_iObjectParticle[iEnt] = EntIndexToEntRef(CreatePadParticle(iEnt));
	
	TF2_SetMatchingTeleporter(iEnt, iEnt); //Set its matching Teleporter to itself.
	
	SDKHook(iEnt, SDKHook_Touch, OnPadTouch);
}

void ConvertPadToTeleporter(int iEnt)
{
	g_iPadType[iEnt] = PadType_None;
	
	SetEntProp(iEnt, Prop_Send, "m_iHighestUpgradeLevel", 1);
	SetEntProp(iEnt, Prop_Send, "m_iUpgradeLevel", 1);
	SetEntProp(iEnt, Prop_Send, "m_bMiniBuilding", false);
	SetVariantInt(150);
	AcceptEntityInput(iEnt, "SetHealth", iEnt);
	
	SetEntProp(iEnt, Prop_Send, "m_iTimesUsed", 0);
	
	SetEntProp(iEnt, Prop_Send, "m_nBody", 1);
	SetEntPropFloat(iEnt, Prop_Send, "m_flModelScale", 1.0);
	RequestFrame(ResetSkin, iEnt);
	
	int iObjParti = EntRefToEntIndex(g_iObjectParticle[iEnt]);
	if (IsValidEntity(iObjParti))
	{
		AcceptEntityInput(iObjParti, "Kill");
	}
	g_iObjectParticle[iEnt] = -1;
	
	SDKUnhook(iEnt, SDKHook_Touch, OnPadTouch);
}

void ConvertAllPadsToTeleporters()
{
	int i = -1;
	while ((i = FindEntityByClassname2(i, "obj_teleporter")) != -1)
	{
		if (IsValidEntity(i) && g_iPadType[i])
			ConvertPadToTeleporter(i);
			
		if (!GetEntProp(i, Prop_Send, "m_bHasSapper") && !GetEntProp(i, Prop_Send, "m_bPlasmaDisable") && TF2_GetMatchingTeleporter(i) == i)
			TF2_EnableObject(i);	//Re-enable disabled un-matched Teleporters
			
		TF2_SetMatchingTeleporter(i, -1); //If MatchingTeleporter is invalid, the game will auto-search for one (if it's active). Do this for all Teleporters just to be safe.
	}
}

int CreatePadParticle(int iPad)
{
	TFTeam iPadTeam = view_as<TFTeam>(GetEntProp(iPad, Prop_Send, "m_iTeamNum"));
	char szParticleName[128];
	switch (g_iPadType[iPad])
	{
		case PadType_Boost:	strcopy(szParticleName, sizeof(szParticleName), "powerup_icon_haste");
		case PadType_Jump:	strcopy(szParticleName, sizeof(szParticleName), "powerup_icon_agility");
	}
	switch (iPadTeam)
	{
		case TFTeam_Red:	StrCat(szParticleName, sizeof(szParticleName), "_red");
		case TFTeam_Blue:	StrCat(szParticleName, sizeof(szParticleName), "_blue");
	}
	int iParticle = SpawnParticle(szParticleName);
	
	float vPos[3];
	GetEntPropVector(iPad, Prop_Data, "m_vecAbsOrigin", vPos);
	vPos[2] += 40.0;
	TeleportEntity(iParticle, vPos, NULL_VECTOR, NULL_VECTOR);
	
	SetParent(iPad, iParticle);
	
	return iParticle;
}

/* Commands */
public Action TogglePadsMenuCmd(int iClient, int nArgs)
{
	if (!iClient)	//if client was the server console
	{
		ReplyToCommand(iClient, "This command can only be used in-game!");
		return Plugin_Handled;
	}
	
	ShowPadMenu(iClient);
	return Plugin_Handled;
}

public Action ShowPadsInfoCmd(int iClient, int nArgs)
{
	if (!iClient)
	{
		ReplyToCommand(iClient, "This command can only be used in-game!");
		return Plugin_Handled;
	}
	
	ShowPadInfo(iClient);
	
	return Plugin_Handled;
}

/* Menus/Panels */
void ShowPadMenu(int iClient)
{
	if (!CheckCommandAccess(iClient, "sm_engipads_override", 0))
	{
		CPrintToChat(iClient, "{orange}[EngiPads]{default} %t", "padphrase_noaccess");
		return;
	}
	
	Menu menu = new Menu(MenuHandlerPadMenu);
	
	char szTranslation[64];
	
	Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_menutitle", iClient);
	menu.SetTitle(szTranslation);
	
	Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_menuenable", iClient);
	menu.AddItem("on", szTranslation);
	
	Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_menudisable", iClient);
	menu.AddItem("off", szTranslation);
	
	if (g_bMenuExitEnabled == true)
		menu.ExitButton = true;

	if (g_bMenuExitEnabled == false)
		menu.ExitButton = false;
		
	menu.Display(iClient, MENU_TIME_FOREVER);
}

void ShowPadInfo(int iClient)
{
	Panel panel = new Panel();
	
	char szTranslation[256];
	Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infotitle", iClient);
	panel.SetTitle(szTranslation);
	
	Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infogeneral", iClient, cvarPads[PadHealth].IntValue);
	panel.DrawItem(szTranslation, ITEMDRAW_RAWLINE);
	
	if (cvarPads[PadsEnabled].IntValue != EngiPads_JumpOnly)
	{	
		Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infoboost", iClient, cvarPads[BoostDuration].FloatValue, cvarPads[BoostCooldown].FloatValue);
		panel.DrawItem(szTranslation, ITEMDRAW_RAWLINE);
	}
	
	if (cvarPads[PadsEnabled].IntValue != EngiPads_BoostOnly)
	{
		Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infojump", iClient, cvarPads[JumpCooldown].FloatValue);
		panel.DrawItem(szTranslation, ITEMDRAW_RAWLINE);
	}
	
	if (cvarPads[BlockEureka].BoolValue)
	{	
		Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infoeureka", iClient);
		panel.DrawItem(szTranslation, ITEMDRAW_RAWLINE);
	}
	
	if (cvarPads[JumpBlockSnipers].BoolValue)
	{
		Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infosniper", iClient);
		panel.DrawItem(szTranslation, ITEMDRAW_RAWLINE);
	}
	
	if (cvarPads[BoostBlockAiming].BoolValue)
	{
		Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infoaiming", iClient);
		panel.DrawItem(szTranslation, ITEMDRAW_RAWLINE);
	}
	
	Format(szTranslation, sizeof(szTranslation), "%T", "padphrase_infoexit", iClient);
	panel.DrawItem(szTranslation, ITEMDRAW_CONTROL);
	
	panel.Send(iClient, MenuHandlerPadInfo, MENU_TIME_FOREVER);
}

int MenuHandlerPadMenu(Menu menu, MenuAction iAction, int iClient, int iOption)
{
	if (iAction == MenuAction_Select)
	{
		if (!iOption) //Enabled EngiPads
		{
			CPrintToChat(iClient, "{orange}[EngiPads]{default} %t", "padphrase_enabled");
		}
		else	//Disabled EngiPads
		{
			CPrintToChat(iClient, "{orange}[EngiPads]{default} %t", "padphrase_disabled");
		}
		
		SetClientPadsEnabled(iClient, iOption ? false : true);
	}
	else if (iAction == MenuAction_End)
	{
		delete menu;
	}
}

int MenuHandlerPadInfo(Menu menu, MenuAction iAction, int iClient, int iOption)
{
	delete menu;
}

/* "Stocks" */
stock int TF2_GetMatchingTeleporter(int iTele)	//Get the matching teleporter entity of a given Teleporter
{
	int iMatch = -1;
	
	if (IsValidEntity(iTele) && HasEntProp(iTele, Prop_Send, g_szOffsetStartProp))
	{
		int iOffs = FindSendPropInfo("CObjectTeleporter", g_szOffsetStartProp) + g_iOffsetMatchingTeleporter;
		iMatch = GetEntDataEnt2(iTele, iOffs);
	}
	
	return iMatch;
}

stock void TF2_SetMatchingTeleporter(int iTele, int iMatch)	//Set the matching teleporter entity of a given Teleporter
{
	if (IsValidEntity(iTele) && HasEntProp(iTele, Prop_Send, g_szOffsetStartProp))
	{
		int iOffs = FindSendPropInfo("CObjectTeleporter", g_szOffsetStartProp) + g_iOffsetMatchingTeleporter;
		SetEntDataEnt2(iTele, iOffs, iMatch, true);
	}
}

stock void TF2_SayTeleportResponse(int iClient) //Plays the appropriate ThanksForTheTeleporter response line.
{
	if (IsValidClient(iClient) && IsPlayerAlive(iClient))
	{
		char szVO[512];
		
		TFClassType iClass = TF2_GetPlayerClass(iClient);
		if (iClass == TFClass_Spy && (TF2_IsPlayerInCondition(iClient, TFCond_Disguised) && GetEntProp(iClient, Prop_Send, "m_nDisguiseClass") != view_as<int>(iClass)))
			iClass = view_as<TFClassType>(GetEntProp(iClient, Prop_Send, "m_nDisguiseClass"));
		
		switch (iClass)
		{
			case TFClass_Scout:
			{
				Format(szVO, sizeof(szVO), "Scout.ThanksForTheTeleporter0%d", GetRandomInt(1, 3));
			}
			case TFClass_Soldier:
			{
				Format(szVO, sizeof(szVO), "Soldier.ThanksForTheTeleporter0%d", GetRandomInt(1, 3));
			}
			case TFClass_Pyro:
			{
				strcopy(szVO, sizeof(szVO), "Pyro.ThanksForTheTeleporter01");
			}
			case TFClass_DemoMan:
			{
				Format(szVO, sizeof(szVO), "Demoman.ThanksForTheTeleporter0%d", GetRandomInt(1, 2));
			}
			case TFClass_Heavy:
			{
				Format(szVO, sizeof(szVO), "Heavy.ThanksForTheTeleporter0%d", GetRandomInt(1, 3));
			}
			case TFClass_Engineer:
			{
				Format(szVO, sizeof(szVO), "Engineer.ThanksForTheTeleporter0%d", GetRandomInt(1, 2));
			}
			case TFClass_Medic:
			{
				Format(szVO, sizeof(szVO), "Medic.ThanksForTheTeleporter0%d", GetRandomInt(1, 3));
			}
			case TFClass_Sniper:
			{
				Format(szVO, sizeof(szVO), "Sniper.ThanksForTheTeleporter0%d", GetRandomInt(1, 3));
			}
			case TFClass_Spy:
			{
				Format(szVO, sizeof(szVO), "Spy.ThanksForTheTeleporter0%d", GetRandomInt(1, 3));
			}
		}
		EmitGameSoundToAll(szVO, iClient);
	}
}

/* Returns true if player has condition */
stock bool Pad_IsPlayerInCond(int iClient, PadCond fCond)
{
	if (IsValidClient(iClient))
	{
		if (Pad_GetConds(iClient) & fCond) //Check if player has specified custom condition flag
			return true;
	}
	return false;
}

/* Returns true if condition was added to player (as in, not already present) */
stock bool Pad_AddCond(int iClient, PadCond fCond)
{
	if (IsValidClient(iClient))
	{
		if (!Pad_IsPlayerInCond(iClient, fCond))
		{
			g_fPadCondFlags[iClient] |= fCond;
			return true;
		}
	}
	return false;
}

/* Returns true if condition was removed from player */
stock bool Pad_RemoveCond(int iClient, PadCond fCond)
{
	if (IsValidClient(iClient))
	{
		if (Pad_IsPlayerInCond(iClient, fCond))
		{
			g_fPadCondFlags[iClient] &= ~fCond;
			return true;
		}
	}
	return false;
}

/* Set PadCondFlags directly*/
stock void Pad_SetConds(int iClient, PadCond fConds)
{
	g_fPadCondFlags[iClient] = fConds;
}

/* Get PadCondFlags directly*/
stock PadCond Pad_GetConds(int iClient)
{
	return g_fPadCondFlags[iClient];
}

stock int GetPadType(int iPad) //Actually just a GetDesiredBuildRotations stock.
{
	int iType = PadType_None;
	
	if (IsValidEntity(iPad))
	{
		iType = (GetEntProp(iPad, Prop_Send, "m_iDesiredBuildRotations") % 2) + 1; //Rotation 0/2 (Horizontal) = PadType 1 | Rotation 1/3 (Vertical) = PadType 2.
		switch (cvarPads[PadsEnabled].IntValue)
		{
			case EngiPads_BoostOnly: iType = PadType_Boost;
			case EngiPads_JumpOnly: iType = PadType_Jump;
		}
	}
	
	return iType;
}

stock int TF2_GetBuildingState(int iBuilding)
{
	int iState = -1;
	
	if (IsValidEntity(iBuilding))
	{
		iState = GetEntProp(iBuilding, Prop_Send, "m_iState");
	}
	
	return iState;
}

stock void TF2_SetBuildingState(int iBuilding, int iState = 0)
{	
	if (IsValidEntity(iBuilding))
	{
		SetEntProp(iBuilding, Prop_Send, "m_iState", iState);
	}
}

stock void TF2_DisableObject(int iObj)
{
	if (IsValidEntity(iObj))
	{
		AcceptEntityInput(iObj, "Disable");
	}
}

stock void TF2_EnableObject(int iObj)
{
	if (IsValidEntity(iObj))
	{
		AcceptEntityInput(iObj, "Enable");
	}
}

stock void ResetSkin(int iEnt)
{
	if (IsValidEntity(iEnt) && HasEntProp(iEnt, Prop_Send, "m_nSkin"))
	{
		int iTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");
		SetEntProp(iEnt, Prop_Send, "m_nSkin", iTeam - 2);
	}
}

stock void PrintPadTypeNameToClient(int iObjType, int iClient)
{
	char szType[64];
	
	switch(iObjType)
	{
		case PadType_Boost: strcopy(szType, sizeof(szType), "padphrase_boost");
		case PadType_Jump: Format(szType, sizeof(szType), "padphrase_jump");
	}
	CPrintToChatEx(iClient, iClient, "{orange}[EngiPads]{default} %t", "padphrase_deploy", szType);
}

stock bool GetClientPadsEnabled(int iClient)
{
	if (!IsValidClient(iClient)) return false;
	if (IsFakeClient(iClient)) return cvarPads[BotsCanBuild].BoolValue;
	if (!AreClientCookiesCached(iClient)) return false;
	char szToggle[3];
	GetClientCookie(iClient, g_hPadCookie, szToggle, sizeof(szToggle));
	return view_as<bool>(StringToInt(szToggle));
}

stock void SetClientPadsEnabled(int iClient, bool bEnabled)
{
	if (!IsValidClient(iClient)) return;
	if (IsFakeClient(iClient)) return;
	if (!AreClientCookiesCached(iClient)) return;
	char szToggle[3];
	IntToString(view_as<int>(bEnabled), szToggle, sizeof(szToggle));
	SetClientCookie(iClient, g_hPadCookie, szToggle);
}

stock bool IsValidClient(int iClient)
{
	return (0 < iClient && iClient <= MaxClients && IsClientInGame(iClient));
}

stock int SpawnParticle(char[] szParticleType)
{
	int iParti = CreateEntityByName("info_particle_system");
	if (IsValidEntity(iParti))
	{
		DispatchKeyValue(iParti, "effect_name", szParticleType);
		DispatchSpawn(iParti);
		ActivateEntity(iParti);
	}
	return iParti;
}

stock void SetParent(int iParent, int iChild, char[] szAttachPoint = "")
{
	SetVariantString("!activator");
	AcceptEntityInput(iChild, "SetParent", iParent, iChild);
	
	if (szAttachPoint[0] != '\0')
	{
		if (IsValidClient(iParent) && IsPlayerAlive(iParent))
		{
			SetVariantString(szAttachPoint);
			AcceptEntityInput(iChild, "SetParentAttachmentMaintainOffset", iChild, iChild, 0);
		}
	}
}

stock void ClearTimer(Handle &hTimer)
{
	if (hTimer != INVALID_HANDLE)
	{
		KillTimer(hTimer);
		hTimer = INVALID_HANDLE;
		
		#if defined DEBUG
		PrintToChatAll("Timer cleared!");
		#endif
	}
}

stock int FindEntityByClassname2(int startEnt, char[] classname)
{
	/* If startEnt isn't valid shifting it back to the nearest valid one */
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
	return FindEntityByClassname(startEnt, classname);
}

#if !defined _smlib_included
/* SMLIB
 * Precaches the given particle system.
 * It's best to call this OnMapStart().
 * Code based on Rochellecrab's, thanks.
 *
 * @param particleSystem	Name of the particle system to precache.
 * @return					Returns the particle system index, INVALID_STRING_INDEX on error.
 */
stock int PrecacheParticleSystem(char[] particleSystem)
{
	int particleEffectNames = INVALID_STRING_TABLE;

	if (particleEffectNames == INVALID_STRING_TABLE) {
		if ((particleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) {
			return INVALID_STRING_INDEX;
		}
	}

	int index = FindStringIndex2(particleEffectNames, particleSystem);
	if (index == INVALID_STRING_INDEX) {
		int numStrings = GetStringTableNumStrings(particleEffectNames);
		if (numStrings >= GetStringTableMaxStrings(particleEffectNames)) {
			return INVALID_STRING_INDEX;
		}

		AddToStringTable(particleEffectNames, particleSystem);
		index = numStrings;
	}

	return index;
}

/* SMLIB
 * Rewrite of FindStringIndex, because in my tests
 * FindStringIndex failed to work correctly.
 * Searches for the index of a given string in a string table.
 *
 * @param tableidx		A string table index.
 * @param str			String to find.
 * @return				String index if found, INVALID_STRING_INDEX otherwise.
 */
stock int FindStringIndex2(int tableidx, char[] str)
{
	char buf[1024];

	int numStrings = GetStringTableNumStrings(tableidx);
	for (int i=0; i < numStrings; i++) {
		ReadStringTable(tableidx, i, buf, sizeof(buf));

		if (StrEqual(buf, str)) {
			return i;
		}
	}

	return INVALID_STRING_INDEX;
}

#endif

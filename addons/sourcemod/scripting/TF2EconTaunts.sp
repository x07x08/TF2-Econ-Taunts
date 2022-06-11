#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_AUTHOR "x07x08"
#define PLUGIN_VERSION "1.1.1"

#define DEFINDEX_UNDEFINED 65535

#define EF_BONEMERGE          (1 << 0)
#define EF_BRIGHTLIGHT        (1 << 1)
#define EF_DIMLIGHT           (1 << 2)
#define EF_NOINTERP           (1 << 3)
#define EF_NOSHADOW           (1 << 4)
#define EF_NODRAW             (1 << 5)
#define EF_NORECEIVESHADOW    (1 << 6)
#define EF_BONEMERGE_FASTCULL (1 << 7)
#define EF_ITEM_BLINK         (1 << 8)
#define EF_PARENT_ANIMATES    (1 << 9)

#include <sourcemod>
#include <sdktools>
#include <tf_econ_data>

Handle    g_hPlayTaunt;
StringMap g_hTokensMap;
int       g_iClientParticleIndex [MAXPLAYERS + 1];
int       g_iClientParticleEntity[MAXPLAYERS + 1] = {-1, ...};
bool      g_bClientShouldSee     [MAXPLAYERS + 1];
ArrayList g_hUnusualTauntsList;
ConVar    g_hCvarVariation;

enum ParticleAttachmentType
{
    PATTACH_ABSORIGIN = 0,    // Create at absorigin, but don't follow
    PATTACH_ABSORIGIN_FOLLOW, // Create at absorigin, and update to follow the entity
    PATTACH_CUSTOMORIGIN,     // Create at a custom origin, but don't follow
    PATTACH_POINT,            // Create on attachment point, but don't follow
    PATTACH_POINT_FOLLOW,     // Create on attachment point, and update to follow the entity
    PATTACH_WORLDORIGIN,      // Used for control points that don't attach to an entity
    PATTACH_ROOTBONE_FOLLOW   // Create at the root bone of the entity, and update to follow
};

enum struct UnusualTauntConfig
{
	int   ParticleIndex;
	float RefireInterval;
	bool  UseParticleSystem;
	bool  Disabled;
}

public Plugin myinfo = 
{
	name        = "[TF2] Econ Taunts",
	author      = PLUGIN_AUTHOR,
	description = "A simple taunt menu plugin",
	version     = PLUGIN_VERSION,
	url         = ""
};

public void OnPluginStart()
{
	Handle hConf = LoadGameConfigFile("tf2.tauntem");
	
	if (hConf == null)
	{
		SetFailState("Unable to load gamedata/tf2.tauntem.txt.");
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CTFPlayer::PlayTauntSceneFromItem");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_hPlayTaunt = EndPrepSDKCall();
	
	if (g_hPlayTaunt == null)
	{
		SetFailState("Unable to initialize call to CTFPlayer::PlayTauntSceneFromItem.");
		
		delete hConf;
	}
	
	delete hConf;
	
	RegConsoleCmd("sm_taunt", CmdTauntMenu);
	RegConsoleCmd("sm_unusualtaunt", CmdUnusualTauntsMenu);
	RegConsoleCmd("sm_utaunt", CmdUnusualTauntsMenu);
	
	RegConsoleCmd("sm_taunts", CmdTauntMenu);
	RegConsoleCmd("sm_unusualtaunts", CmdUnusualTauntsMenu);
	RegConsoleCmd("sm_utaunts", CmdUnusualTauntsMenu);
	
	RegAdminCmd("sm_refreshtaunts", CmdRefreshConfig, ADMFLAG_CONFIG, "Reloads the taunts configuration file");
	
	g_hCvarVariation = CreateConVar("sm_econtaunts_refire", "0.05", "Time variation between particle restarts.", _, true, 0.0);
	
	// OnClientPutInServer makes the particle spawn at [0, 0, 0], no idea why.
	HookEvent("player_team", OnPlayerTeam);
	
	g_hTokensMap = ParseLanguage("english");
}

public void OnClientDisconnect(int iClient)
{
	g_iClientParticleIndex[iClient]  = 0;
	g_iClientParticleEntity[iClient] = -1;
	g_bClientShouldSee[iClient]      = false;
}

public void OnClientConnected(int iClient)
{
	g_iClientParticleIndex[iClient]  = 0;
	g_iClientParticleEntity[iClient] = -1;
	g_bClientShouldSee[iClient]      = false;
}

public void OnMapStart()
{
	ParseTauntConfig();
}

public void OnPlayerTeam(Event hEvent, char[] strEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	
	char strEffectName[PLATFORM_MAX_PATH];
	int  iParticleIndex, iParticleEntity;
	
	if (hEvent.GetInt("oldteam") == 0 && !g_bClientShouldSee[iClient])
	{
		for (int iIndex = 1; iIndex <= MaxClients; iIndex++)
		{
			iParticleIndex  = g_iClientParticleIndex[iIndex];
			iParticleEntity = EntRefToEntIndex(g_iClientParticleEntity[iIndex]);
			
			UnusualTauntConfig Taunt;
			bool bParticleSystem = false;
			
			int iUnusualConfigIndex = g_hUnusualTauntsList == null ? -1 : g_hUnusualTauntsList.FindValue(iParticleIndex, 0);
			if (iUnusualConfigIndex != -1)
			{
				g_hUnusualTauntsList.GetArray(iUnusualConfigIndex, Taunt);
				bParticleSystem = Taunt.UseParticleSystem;
			}
			
			if (iParticleEntity == -1 || !iParticleIndex || bParticleSystem || (Taunt.RefireInterval > 0))
			{
				continue;
			}
			
			TF2Econ_GetParticleAttributeSystemName(iParticleIndex, strEffectName, sizeof(strEffectName));
			CreateTempParticle(strEffectName, _, _,  _, iParticleEntity, PATTACH_ABSORIGIN_FOLLOW, _, _);
			TE_SendToClient(iClient);
		}
		
		g_bClientShouldSee[iClient] = true;
	}
}

public Action CmdTauntMenu(int iClient, int iArgs)
{
	if (iClient == 0)
	{
		ReplyToCommand(iClient, "Command is in-game only.");
		return Plugin_Handled;
	}
	
	Menu hMenu = new Menu(TauntMenuHandler);
	hMenu.SetTitle("Taunts :");
	
	ArrayList hTauntList = TF2Econ_GetItemList(FilterTaunts, TF2_GetPlayerClass(iClient));
	int iTauntListSize = hTauntList.Length;
	
	char strTauntIndex[16];
	char strTauntName[64];
	
	for (int iEntry = 0; iEntry < iTauntListSize; iEntry++)
	{
		int iTauntIndex = hTauntList.Get(iEntry);
		IntToString(iTauntIndex, strTauntIndex, sizeof(strTauntIndex));
		
		TF2Econ_GetItemName(iTauntIndex, strTauntName, sizeof(strTauntName));
		hMenu.AddItem(strTauntIndex, strTauntName, ITEMDRAW_DEFAULT);
	}
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
	delete hTauntList;
	
	return Plugin_Handled;
}

public int TauntMenuHandler(Menu hMenu, MenuAction iMenuActions, int iParam1, int iParam2)
{
	switch(iMenuActions)
	{
		case MenuAction_Select :
		{
			char strTauntIndex[16];
			hMenu.GetItem(iParam2, strTauntIndex, sizeof(strTauntIndex));
			
			int iTauntIndex = StringToInt(strTauntIndex);
			PlayTaunt(iParam1, iTauntIndex);
		}
		
		case MenuAction_End :
		{
			delete hMenu;
		}
	}
	
	return 0;
}

public bool FilterTaunts(int iItemDefIndex, TFClassType iClass)
{
	int iTauntSlot = TF2Econ_TranslateLoadoutSlotNameToIndex("taunt");
	
	return TF2Econ_GetItemLoadoutSlot(iItemDefIndex, iClass) == iTauntSlot;
}

public Action CmdUnusualTauntsMenu(int iClient, int iArgs)
{
	if (iClient == 0)
	{
		ReplyToCommand(iClient, "Command is in-game only.");
		return Plugin_Handled;
	}
	
	Menu hMenu = new Menu(UnusualTauntsMenuHandler);
	
	hMenu.SetTitle("Unusual taunt particles :");
	hMenu.AddItem("0", "No effect", ITEMDRAW_DEFAULT);
	
	ArrayList hUnusualsList = TF2Econ_GetParticleAttributeList(ParticleSet_TauntUnusualEffects);
	int iUnusualsListSize = hUnusualsList.Length;
	
	char strUnusualIndex[16];
	char strUnusualName[64];
	char strLocalizedName[64];
	
	for (int iEntry = 0; iEntry < iUnusualsListSize; iEntry++)
	{
		UnusualTauntConfig UnusualTaunt;
		bool bUseUnusual = false;
		
		int iUnusualIndex = hUnusualsList.Get(iEntry);
		IntToString(iUnusualIndex, strUnusualIndex, sizeof(strUnusualIndex));
		
		FormatEx(strUnusualName, sizeof(strUnusualName), "Attrib_Particle%i", iUnusualIndex);
		
		if (LocalizeToken(strUnusualName, strLocalizedName, sizeof(strLocalizedName)))
		{
			Format(strLocalizedName, sizeof(strLocalizedName), "%s (%i)", strLocalizedName, iUnusualIndex);
		}
		
		int iUnusualConfigIndex = g_hUnusualTauntsList == null ? -1 : g_hUnusualTauntsList.FindValue(iUnusualIndex, 0);
		
		if (iUnusualConfigIndex != -1)
		{
			g_hUnusualTauntsList.GetArray(iUnusualConfigIndex, UnusualTaunt);
			bUseUnusual = UnusualTaunt.Disabled;
		}
		
		hMenu.AddItem(strUnusualIndex, strLocalizedName, bUseUnusual ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
	delete hUnusualsList;
	
	return Plugin_Handled;
}

public Action CmdRefreshConfig(int iClient, int iArgs)
{
	ParseTauntConfig();
	
	ReplyToCommand(iClient, "[SM] Successfully refreshed the taunts configuration file");
	
	return Plugin_Handled;
}

public int UnusualTauntsMenuHandler(Menu hMenu, MenuAction iMenuActions, int iParam1, int iParam2)
{
	switch(iMenuActions)
	{
		case MenuAction_Select :
		{
			char strUnusualIndex[16];
			char strLocalizedName[64];
			hMenu.GetItem(iParam2, strUnusualIndex, sizeof(strUnusualIndex), _, strLocalizedName, sizeof(strLocalizedName));
			
			int iUnusualIndex = StringToInt(strUnusualIndex);
			g_iClientParticleIndex[iParam1] = iUnusualIndex;
			
			if (iUnusualIndex != 0)
			{
				ReplyToCommand(iParam1, "[SM] Successfully applied \"%s\" on your taunts", strLocalizedName);
			}
			else
			{
				ReplyToCommand(iParam1, "[SM] Successfully removed the current effect from your taunts");
			}
		}
		
		case MenuAction_End :
		{
			delete hMenu;
		}
	}
	
	return 0;
}

bool PlayTaunt(int iClient, int iTauntIndex)
{
	int iEntity = MakeCEIVEnt(iClient, iTauntIndex);
	if (!IsValidEntity(iEntity))
	{
		ReplyToCommand(iClient, "[SM] Couldn't create entity for taunt");
		
		return false;
	}
	
	int iCEIVOffset = GetEntSendPropOffs(iEntity, "m_Item", true);
	if (iCEIVOffset <= 0)
	{
		ReplyToCommand(iClient, "[SM] Couldn't find m_Item for taunt item");
		
		if (iEntity && IsValidEntity(iEntity))
		{
			RemoveEntity(iEntity);
		}
		
		return false;
	}
	
	Address pEconItemView = GetEntityAddress(iEntity);
	if (!IsValidAddress(pEconItemView))
	{
		ReplyToCommand(iClient, "[SM] Couldn't find entity address for taunt item");
		
		if (iEntity && IsValidEntity(iEntity))
		{
			RemoveEntity(iEntity);
		}
		
		return false;
	}
	
	pEconItemView += view_as<Address>(iCEIVOffset);
	
	if (!SDKCall(g_hPlayTaunt, iClient, pEconItemView))
	{
		ReplyToCommand(iClient, "[SM] Couldn't play taunt");
		
		if (iEntity && IsValidEntity(iEntity))
		{
			RemoveEntity(iEntity);
		}
		
		return false;
	}
	
	RemoveEntity(iEntity); // The entity should be valid if the taunt succeeded
	
	return true;
}

/*
	https://github.com/nosoop/stocksoup/blob/master/tf/econ.inc
	https://git.csrd.science/nosoop/CSRD-BotTauntRandomizer
*/

stock int MakeCEIVEnt(int iClient, int iItemDef)
{
	int iWearable = CreateEntityByName("tf_wearable");
	
	if (IsValidEntity(iWearable))
	{
		SetEntProp(iWearable, Prop_Send, "m_iItemDefinitionIndex", iItemDef);
		
		if (iItemDef != DEFINDEX_UNDEFINED)
		{
			// using defindex of a valid item
			SetEntProp(iWearable, Prop_Send, "m_bInitialized", 1);
			SetEntProp(iWearable, Prop_Send, "m_iEntityLevel", 1);
			// Something about m_iEntityQuality doesn't play nice with SetEntProp.
			SetEntData(iWearable, FindSendPropInfo("CTFWearable", "m_iEntityQuality"), 6);
		}
		
		// Spawn.
		DispatchSpawn(iWearable);
	}
	
	return iWearable;
}

stock bool IsValidAddress(Address pAddress)
{
	return pAddress != Address_Null;
}

void ParseTauntConfig()
{
	delete g_hUnusualTauntsList;
	
	char strFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, strFilePath, sizeof(strFilePath), "configs/econtaunts/taunts.cfg");
	
	if (FileExists(strFilePath, true))
	{
		KeyValues kvTauntConfig = new KeyValues("EconTaunts");
		
		if (kvTauntConfig.ImportFromFile(strFilePath) && kvTauntConfig.GotoFirstSubKey())
		{
			g_hUnusualTauntsList = new ArrayList(sizeof(UnusualTauntConfig));
			
			do
			{
				ParseUnusualTaunt(kvTauntConfig);
			}
			while (kvTauntConfig.GotoNextKey());
		}
		
		delete kvTauntConfig;
	}
}

void ParseUnusualTaunt(KeyValues kvConfig)
{
	kvConfig.GotoFirstSubKey();
	
	char strUnusualTauntIndex[16];
	int  iTauntIndex;
	
	do
	{
		if (kvConfig.GetSectionName(strUnusualTauntIndex, sizeof(strUnusualTauntIndex)))
		{
			iTauntIndex = StringToInt(strUnusualTauntIndex);
			if (iTauntIndex > 0 && !IsUnusualTauntAdded(iTauntIndex))
			{
				UnusualTauntConfig UnusualTaunt;
				
				UnusualTaunt.ParticleIndex     = iTauntIndex;
				UnusualTaunt.RefireInterval    = kvConfig.GetFloat("refire interval", 0.0);
				UnusualTaunt.Disabled          = !!kvConfig.GetNum("disabled", 0);
				UnusualTaunt.UseParticleSystem = !!kvConfig.GetNum("use particle system", 0);
				
				g_hUnusualTauntsList.PushArray(UnusualTaunt);
			}
		}
	}
	while (kvConfig.GotoNextKey());
	kvConfig.GoBack();
}

bool IsUnusualTauntAdded(int iTauntIndex)
{
	UnusualTauntConfig UnusualTaunt;
	
	int iArrayIndex = g_hUnusualTauntsList.FindValue(iTauntIndex, 0);
	if (iArrayIndex != -1)
	{
		if (g_hUnusualTauntsList.GetArray(iArrayIndex, UnusualTaunt) > 0)
		{
			LogMessage("Taunt Index : %i found twice, skipping.", UnusualTaunt.ParticleIndex);
			return true;
		}
	}
	
	return false;
}

public void TF2_OnConditionAdded(int iClient, TFCond iCondition)
{
	if (iCondition == TFCond_Taunting)
	{
		int iParticleIndex = g_iClientParticleIndex[iClient];
		
		if (iParticleIndex != 0)
		{
			UnusualTauntConfig UnusualTaunt;
			bool bParticleSystem = false;
			
			int iUnusualConfigIndex = g_hUnusualTauntsList == null ? -1 : g_hUnusualTauntsList.FindValue(iParticleIndex, 0);
			if (iUnusualConfigIndex != -1)
			{
				g_hUnusualTauntsList.GetArray(iUnusualConfigIndex, UnusualTaunt);
				bParticleSystem = UnusualTaunt.UseParticleSystem;
			}
			
			int iParticleEntity = CreateAttachedParticle(iClient, iParticleIndex);
			if (bParticleSystem ? IsValidEdict(iParticleEntity) : IsValidEntity(iParticleEntity))
			{
				if (UnusualTaunt.RefireInterval > 0 && !bParticleSystem)
				{
					DataPack hTauntDataPack = new DataPack();
					hTauntDataPack.WriteCell(GetClientUserId(iClient));
					hTauntDataPack.WriteCell(iParticleIndex);
					hTauntDataPack.WriteCell(EntIndexToEntRef(iParticleEntity));
					
					CreateTimer(UnusualTaunt.RefireInterval, RefireTauntParticle, hTauntDataPack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
				}
				
				g_iClientParticleEntity[iClient] = EntIndexToEntRef(iParticleEntity);
			}
		}
	}
}

public Action RefireTauntParticle(Handle hTimer, DataPack hTauntDataPack)
{
	hTauntDataPack.Reset();
	
	int iClient         = GetClientOfUserId(hTauntDataPack.ReadCell());
	int iParticleIndex  = hTauntDataPack.ReadCell();
	int iParticleEntity = EntRefToEntIndex(hTauntDataPack.ReadCell());
	
	if (!iParticleIndex || iParticleEntity == -1 || !iClient || !IsClientInGame(iClient))
	{
		return Plugin_Stop;
	}
	
	char strEffectName[PLATFORM_MAX_PATH];
	
	// https://forums.alliedmods.net/showthread.php?t=235329
	SetVariantString("ParticleEffectStop");
	AcceptEntityInput(iParticleEntity, "DispatchEffect");
	
	TF2Econ_GetParticleAttributeSystemName(iParticleIndex, strEffectName, sizeof(strEffectName));
	CreateTempParticle(strEffectName, _, _,  _, iParticleEntity, PATTACH_ABSORIGIN_FOLLOW, _, _);
	TE_SendToAll();
	
	return Plugin_Continue;
}

public void TF2_OnConditionRemoved(int iClient, TFCond iCondition)
{
	if (iCondition == TFCond_Taunting)
	{
		int iParticleEntity = EntRefToEntIndex(g_iClientParticleEntity[iClient]);
		if (iParticleEntity != -1)
		{
			char strEntityClassname[64]; GetEntityClassname(iParticleEntity, strEntityClassname, sizeof(strEntityClassname));
			
			if (StrEqual(strEntityClassname, "info_particle_system"))
			{
				if (IsValidEdict(iParticleEntity))
				{
					RemoveEdict(iParticleEntity);
					g_iClientParticleEntity[iClient] = -1;
				}
			}
			else
			{
				if (IsValidEntity(iParticleEntity))
				{
					RemoveEntity(iParticleEntity);
					g_iClientParticleEntity[iClient] = -1;
				}
			}
		}
	}
}

/*
	I couldn't get unusual taunts working with attributes so I did this.
	If anyone knows how to get them working with attributes, please tell how.
*/

stock int CreateAttachedParticle(int iClient, int iParticleIndex)
{
	UnusualTauntConfig UnusualTaunt;
	bool bParticleSystem = false;
	
	int iUnusualConfigIndex = g_hUnusualTauntsList == null ? -1 : g_hUnusualTauntsList.FindValue(iParticleIndex, 0);
	if (iUnusualConfigIndex != -1)
	{
		g_hUnusualTauntsList.GetArray(iUnusualConfigIndex, UnusualTaunt);
		bParticleSystem = UnusualTaunt.UseParticleSystem;
	}
	
	// I just guessed it, nothing else
	int iEntity = CreateEntityByName(bParticleSystem ? "info_particle_system" : "tf_wearable");
	
	if (bParticleSystem ? IsValidEdict(iEntity) : IsValidEntity(iEntity))
	{
		float fPosition[3];
		GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", fPosition);
		TeleportEntity(iEntity, fPosition, NULL_VECTOR, NULL_VECTOR);
		
		char strEffectName[PLATFORM_MAX_PATH];
		
		if (!TF2Econ_GetParticleAttributeSystemName(iParticleIndex, strEffectName, sizeof(strEffectName)))
		{
			LogError("Failed to get the system name of the particle attribute index. Removing entity.");
			
			bParticleSystem ? RemoveEdict(iEntity) : RemoveEntity(iEntity);
			return -1;
		}
		
		if (!bParticleSystem)
		{
			DispatchSpawn(iEntity);
			
			// EF_BONEMERGE_FASTCULL moves the entity in an undesired position (in the middle of the client)
			// Also setting all these netprops before dispatching spawn resets them for some reason
			SetEntProp(iEntity, Prop_Send, "m_fEffects", EF_BONEMERGE | EF_NOSHADOW | EF_PARENT_ANIMATES | EF_NODRAW | EF_NORECEIVESHADOW);
			SetEntProp(iEntity, Prop_Send, "m_CollisionGroup", 0);    // COLLISION_GROUP_NONE
			SetEntProp(iEntity, Prop_Send, "m_usSolidFlags", 0x0004); // FSOLID_NOT_SOLID
			SetEntProp(iEntity, Prop_Send, "m_nSolidType", 0);        // SOLID_NONE
			SetEntProp(iEntity, Prop_Send, "m_bValidatedAttachedEntity", 1); // Visibility
			
			char strModelName[PLATFORM_MAX_PATH];
			GetEntPropString(iClient, Prop_Data, "m_ModelName", strModelName, sizeof(strModelName));
			SetEntityModel(iEntity, strModelName);
			
			SetVariantString("!activator");
			AcceptEntityInput(iEntity, "SetParent", iClient, iEntity);
			
			CreateTempParticle(strEffectName, fPosition, _,  _, iEntity, PATTACH_ABSORIGIN_FOLLOW, _, _);
			
			TE_SendToAll();
		}
		else
		{
			DispatchKeyValue(iEntity, "effect_name", strEffectName);
			DispatchSpawn(iEntity);
			ActivateEntity(iEntity);
			
			SetVariantString("!activator");
			AcceptEntityInput(iEntity, "SetParent", iClient, iEntity);
			
			AcceptEntityInput(iEntity, "Start");
			
			if (UnusualTaunt.RefireInterval > 0)
			{
				char strBuffer[64];
				FormatEx(strBuffer, sizeof(strBuffer), "OnUser1 !self:Stop::%f:-1", UnusualTaunt.RefireInterval);
				SetVariantString(strBuffer);
				AcceptEntityInput(iEntity, "AddOutput");
				FormatEx(strBuffer, sizeof(strBuffer), "OnUser1 !self:Start::%f:-1", UnusualTaunt.RefireInterval + GetConVarFloat(g_hCvarVariation));
				SetVariantString(strBuffer);
				AcceptEntityInput(iEntity, "AddOutput");
				FormatEx(strBuffer, sizeof(strBuffer), "OnUser1 !self:FireUser1::%f:-1", UnusualTaunt.RefireInterval);
				SetVariantString(strBuffer);
				AcceptEntityInput(iEntity, "AddOutput");
				AcceptEntityInput(iEntity, "FireUser1");
			}
		}
	}
	
	return iEntity;
}

stock void CreateTempParticle(const char[] strParticle,
                              const float vecOrigin[3] = NULL_VECTOR,
                              const float vecStart[3] = NULL_VECTOR,
                              const float vecAngles[3] = NULL_VECTOR,
                              int iEntity = -1,
                              ParticleAttachmentType AttachmentType = PATTACH_ABSORIGIN,
                              int iAttachmentPoint = -1,
                              bool bResetParticles = false)
{
	int iParticleTable, iParticleIndex;
	
	iParticleTable = FindStringTable("ParticleEffectNames");
	if (iParticleTable == INVALID_STRING_TABLE)
	{
		ThrowError("Could not find string table: ParticleEffectNames");
	}
	
	iParticleIndex = FindStringIndex(iParticleTable, strParticle);
	if (iParticleIndex == INVALID_STRING_INDEX)
	{
		LogError("Could not find particle index: %s. Trying to precache it now.", strParticle);
		iParticleIndex = PrecacheParticleSystem(strParticle);
		if (iParticleIndex == INVALID_STRING_INDEX)
		{
			ThrowError("Could not find particle index: %s", strParticle);
		}
	}
	
	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", vecOrigin[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecOrigin[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecOrigin[2]);
	TE_WriteFloat("m_vecStart[0]", vecStart[0]);
	TE_WriteFloat("m_vecStart[1]", vecStart[1]);
	TE_WriteFloat("m_vecStart[2]", vecStart[2]);
	TE_WriteVector("m_vecAngles", vecAngles);
	TE_WriteNum("m_iParticleSystemIndex", iParticleIndex);
	
	if (iEntity != -1)
	{
		TE_WriteNum("entindex", iEntity);
	}
	
	if (AttachmentType != PATTACH_ABSORIGIN)
	{
		TE_WriteNum("m_iAttachType", view_as<int>(AttachmentType));
	}
	
	if (iAttachmentPoint != -1)
	{
		TE_WriteNum("m_iAttachmentPointIndex", iAttachmentPoint);
	}
	
	TE_WriteNum("m_bResetParticles", bResetParticles ? 1 : 0);
}

stock int PrecacheParticleSystem(const char[] strParticleSystem)
{
	static int iParticleEffectNames = INVALID_STRING_TABLE;
	
	if (iParticleEffectNames == INVALID_STRING_TABLE)
	{
		if ((iParticleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE)
		{
			return INVALID_STRING_INDEX;
		}
	}
	
	int iIndex = FindStringIndex2(iParticleEffectNames, strParticleSystem);
	if (iIndex == INVALID_STRING_INDEX)
	{
		int iNumStrings = GetStringTableNumStrings(iParticleEffectNames);
		if (iNumStrings >= GetStringTableMaxStrings(iParticleEffectNames))
		{
			return INVALID_STRING_INDEX;
		}
		
		AddToStringTable(iParticleEffectNames, strParticleSystem);
		iIndex = iNumStrings;
	}
	
	return iIndex;
}

stock int FindStringIndex2(int iTableIndex, const char[] strString)
{
	char strBuffer[1024];
	
	int iNumStrings = GetStringTableNumStrings(iTableIndex);
	for (int iIndex = 0; iIndex < iNumStrings; iIndex++)
	{
		ReadStringTable(iTableIndex, iIndex, strBuffer, sizeof(strBuffer));
		
		if (StrEqual(strBuffer, strString))
		{
			return iIndex;
		}
	}
	
	return INVALID_STRING_INDEX;
}

/* 
	The following localization functions are taken from
	https://github.com/DoctorMcKay/sourcemod-plugins/blob/master/scripting/enhanced_items.sp
*/

bool LocalizeToken(const char[] strToken, char[] strOutput, int strMaxLen)
{
	if(g_hTokensMap == null)
	{
		LogError("Unable to localize token for server language!");
		return false;
	}
	else
	{
		return g_hTokensMap.GetString(strToken, strOutput, strMaxLen);
	}
}

StringMap ParseLanguage(const char[] strLanguage)
{
	char strFilename[64];
	Format(strFilename, sizeof(strFilename), "resource/tf_%s.txt", strLanguage);
	File hFile = OpenFile(strFilename, "r");
	
	if(hFile == null)
	{
		return null;
	}
	
	// The localization files are encoded in UCS-2, breaking all of our available parsing options
	// We have to go byte-by-byte then line-by-line :(
	
	// This parser isn't perfect since some values span multiple lines, but since we're only interested in single-line values, this is sufficient
	
	StringMap hLang = new StringMap();
	hLang.SetString("__name__", strLanguage);
	
	int iData, i = 0;
	char strLine[2048];
	
	while(ReadFileCell(hFile, iData, 2) == 1)
	{
		if(iData < 0x80)
		{
			// It's a single-byte character
			strLine[i++] = iData;
			
			if(iData == '\n')
			{
				strLine[i] = '\0';
				HandleLangLine(strLine, hLang);
				i = 0;
			}
		}
		else if(iData < 0x800)
		{
			// It's a two-byte character
			strLine[i++] = (iData >> 6) | 0xC0;
			strLine[i++] = (iData & 0x3F) | 0x80;
		}
		else if(iData < 0xFFFF && iData >= 0xD800 && iData <= 0xDFFF)
		{
			strLine[i++] = (iData >> 12) | 0xE0;
			strLine[i++] = ((iData >> 6) & 0x3F) | 0x80;
			strLine[i++] = (iData & 0x3F) | 0x80;
		}
		else if(iData >= 0x10000 && iData < 0x10FFFF)
		{
			strLine[i++] = (iData >> 18) | 0xF0;
			strLine[i++] = ((iData >> 12) & 0x3F) | 0x80;
			strLine[i++] = ((iData >> 6) & 0x3F) | 0x80;
			strLine[i++] = (iData & 0x3F) | 0x80;
		}
	}
	
	delete hFile;
	
	return hLang;
}

void HandleLangLine(char[] strLine, StringMap hLang)
{
	TrimString(strLine);
	
	if(strLine[0] != '"')
	{
		// Not a line containing at least one quoted string
		return;
	}
	
	char strToken[128], strValue[1024];
	int iPos = BreakString(strLine, strToken, sizeof(strToken));
	
	if(iPos == -1)
	{
		// This line doesn't have two quoted strings
		return;
	}
	
	BreakString(strLine[iPos], strValue, sizeof(strValue));
	
	if (StrContains(strToken, "Attrib_Particle") != -1) // Only particles should be added
	{
		hLang.SetString(strToken, strValue);
	}
}
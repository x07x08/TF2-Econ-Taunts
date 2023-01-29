#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf_econ_data>

#define PLUGIN_NAME        "[TF2] Econ Taunts"
#define PLUGIN_AUTHOR      "x07x08"
#define PLUGIN_DESCRIPTION "A simple taunts menu plugin"
#define PLUGIN_VERSION     "1.3.1"
#define PLUGIN_URL         "https://github.com/x07x08/TF2-Econ-Taunts"

#define DEFINDEX_UNDEFINED 65535

public Plugin myinfo =
{
	name        = PLUGIN_NAME,
	author      = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version     = PLUGIN_VERSION,
	url         = PLUGIN_URL
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_taunt", CmdTaunt);
	RegConsoleCmd("sm_taunts", CmdTaunt);
}

public Action CmdTaunt(int iClient, int iArgs)
{
	if (iClient == 0)
	{
		ReplyToCommand(iClient, "Command is in-game only.");
		
		return Plugin_Handled;
	}
	
	char strTauntIndex[16];
	
	if (iArgs >= 1)
	{
		GetCmdArg(1, strTauntIndex, sizeof(strTauntIndex));
		
		int iTauntIndex = StringToInt(strTauntIndex);
		
		if (FilterTaunts(iTauntIndex, TF2_GetPlayerClass(iClient)))
		{
			PlayTaunt(iClient, iTauntIndex);
		}
		else
		{
			ReplyToCommand(iClient, "[SM] Invalid taunt index");
		}
		
		return Plugin_Handled;
	}
	
	Menu hMenu = new Menu(TauntMenuHandler);
	hMenu.SetTitle("Taunts :");
	
	ArrayList hTauntsList = TF2Econ_GetItemList(FilterTaunts, TF2_GetPlayerClass(iClient));
	
	int iTauntListSize = hTauntsList.Length;
	
	char strTauntName[64];
	
	for (int iEntry = 0; iEntry < iTauntListSize; iEntry++)
	{
		int iTauntIndex = hTauntsList.Get(iEntry);
		IntToString(iTauntIndex, strTauntIndex, sizeof(strTauntIndex));
		
		TF2Econ_GetItemName(iTauntIndex, strTauntName, sizeof(strTauntName));
		
		Format(strTauntName, sizeof(strTauntName), "%s (%i)", strTauntName, iTauntIndex);
		
		hMenu.AddItem(strTauntIndex, strTauntName, ITEMDRAW_DEFAULT);
	}
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
	delete hTauntsList;
	
	return Plugin_Handled;
}

public int TauntMenuHandler(Menu hMenu, MenuAction iMenuActions, int iParam1, int iParam2)
{
	switch (iMenuActions)
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
	return TF2Econ_GetItemLoadoutSlot(iItemDefIndex, iClass) == TF2Econ_TranslateLoadoutSlotNameToIndex("taunt");
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
		
		RemoveEntity(iEntity);
		
		return false;
	}
	
	Address pEconItemView = GetEntityAddress(iEntity);
	
	if (!IsValidAddress(pEconItemView))
	{
		ReplyToCommand(iClient, "[SM] Couldn't find entity address for taunt item");
		
		RemoveEntity(iEntity);
		
		return false;
	}
	
	pEconItemView += view_as<Address>(iCEIVOffset);
	
	static Handle hPlayTaunt = null;
	
	if (hPlayTaunt == null)
	{
		GameData hConf = new GameData("tf2.tauntem");
		
		if (hConf == null) SetFailState("Unable to load gamedata/tf2.tauntem.txt.");
		
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "CTFPlayer::PlayTauntSceneFromItem");
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
		hPlayTaunt = EndPrepSDKCall();
		
		if (hPlayTaunt == null) SetFailState("Unable to initialize call to CTFPlayer::PlayTauntSceneFromItem.");
		
		delete hConf;
	}
	
	if (!SDKCall(hPlayTaunt, iClient, pEconItemView))
	{
		ReplyToCommand(iClient, "[SM] Couldn't play taunt");
		
		RemoveEntity(iEntity);
		
		return false;
	}
	
	RemoveEntity(iEntity);
	
	return true;
}

/*
	https://github.com/nosoop/stocksoup/blob/master/tf/econ.inc
	https://git.csrd.science/nosoop/CSRD-BotTauntRandomizer
*/

stock int MakeCEIVEnt(int iClient, int iItemDef)
{
	int iWearable = CreateEntityByName("tf_wearable");
	
	if (!IsValidEntity(iWearable)) return iWearable;
	
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
	
	return iWearable;
}

stock bool IsValidAddress(Address pAddress)
{
	return pAddress != Address_Null;
}

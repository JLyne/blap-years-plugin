#include <tf2>
#include <tf2items>
#include <tf2attributes>
#include <sdktools>
#include <sdkhooks>
#include <sourcemod>
#include <tf2_stocks>
#include <buildings>

#pragma semicolon 1;
#pragma newdecls required;

Handle hCreateDroppedWeapon;
Handle hInitDroppedWeapon;
Handle hPickupWeaponFromOther;

ConVar year;

ArrayList gBlockedQualities;
ArrayList gBlockedAttributes;
ArrayList gCreatedWeapons;

public Plugin myinfo =
{
	name = "Years",
	description = "Year specific logic",
	author = "Jim",
	version = "1.0",
	url = ""
};

enum NamedItem {
	NIClient,
	String:NIClassname[32],
	NIDefIndex,
	NILevel,
	NIQuality,
	NIEntity,
};

public void OnPluginStart() {
	Handle hConf = LoadGameConfigFile("weapons.games");

	StartPrepSDKCall(SDKCall_Static);

	if(!PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "Create")) {
		LogMessage("[DW] Failed to set CDW from conf!");
	}

	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	hCreateDroppedWeapon = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);

	if(!PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "InitDroppedWeapon")) {
		LogMessage("[DW] Failed to set IDW from conf!");
	}

	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	hInitDroppedWeapon = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Player);

	if(!PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "PickupWeaponFromOther")) {
		PrintToServer("[DW] Failed to set PWFO from conf!");
	}

	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	hPickupWeaponFromOther = EndPrepSDKCall();
	
	delete hConf;

	gBlockedQualities = new ArrayList();
	gBlockedAttributes = new ArrayList();
	gCreatedWeapons = new ArrayList();
	
	HookEvent("player_spawn", Hook_PlayerSpawn, EventHookMode_Post);
	HookEvent("post_inventory_application", Hook_PostInventoryApplication, EventHookMode_Post);

	year = CreateConVar("sm_year", "2019", "Current year", 0, true, 2007.0, true, 2019.0);
	year.AddChangeHook(YearChanged);

	YearChanged(year, "", "");
}

public void Hook_PlayerSpawn(Handle event, char[] name, bool dontBroadcast) {
}

public void Hook_PostInventoryApplication(Event event, char[] name, bool dontBroadcast) {
	PrintToChatAll("Dashoom");
	int client = GetClientOfUserId(event.GetInt("userid"));

	for(int slot = 0; slot < 8; slot++) {
        int weapon = GetPlayerWeaponSlot(client, slot);
        
        if(IsValidEntity(weapon)) {
			NamedItem item[NamedItem];

			item[NIClient] = client;
			GetEntityClassname(weapon, item[NIClassname], sizeof(item[NIClassname]));
			item[NIDefIndex] = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			item[NILevel] = GetEntProp(weapon, Prop_Send, "m_iEntityLevel");
			item[NIQuality] = GetEntProp(weapon, Prop_Send, "m_iEntityQuality");
			item[NIEntity] = weapon;

			UpdateItem(item);
        }
    }
}

// public void TF2Items_OnGiveNamedItem_Post(int client, char[] classname, int itemDefinitionIndex, int itemLevel, int quality, int entity) {
// 	if(gCreatedWeapons.FindValue(entity) > -1) {
// 		PrintToServer("Ignoring plugin created weapon");
// 		return;
// 	}

// 	DataPack pack = new DataPack();
// 	pack.WriteCell(GetClientUserId(client));
// 	pack.WriteString(classname);
// 	pack.WriteCell(itemDefinitionIndex);
// 	pack.WriteCell(itemLevel);
// 	pack.WriteCell(quality);
// 	pack.WriteCell(entity);

// 	RequestFrame(Frame_UpdateItem, pack);
// }

public void UpdateItem(NamedItem item[NamedItem]) {
	//NamedItem item[NamedItem];
		// pack.Reset();

	// item[NIClient] = GetClientOfUserId(pack.ReadCell());
	// pack.ReadString(item[NIClassname], sizeof(item[NIClassname]));
	// item[NIDefIndex] = pack.ReadCell();
	// item[NILevel] = pack.ReadCell();
	// item[NIQuality] = pack.ReadCell();
	// item[NIEntity] = pack.ReadCell();


	//Skip items that aren't equipped
	int slot = GetWeaponSlot(item[NIClient], item[NIEntity]);

	if(slot == -1) {
		PrintToServer("Ignoring item that is no longer equipped");
		return;
	}

	//Create replacement item if needed
	Handle replacement = CreateReplacementItem(item);

	if(replacement == INVALID_HANDLE) {
		PrintToServer("No replacement item created");
		return;
	}

	int created = TF2Items_GiveNamedItem(item[NIClient], replacement);

	if(!IsValidEntity(created)) {
		PrintToServer("TF2Items_GiveNamedItem failed");
		return;
	}

	gCreatedWeapons.Push(created);

	//Remove old item
	TF2_RemoveWeaponSlot(item[NIClient], slot);
	PrintToServer("Original item unequipped");
	
	//Equip replaced item (will be invisible)
	EquipPlayerWeapon(item[NIClient], created);
	PrintToServer("Replacement item equipped");

	//Create dropped version of replaced weapon
	float position[3];
	float angles[3];

	GetClientEyePosition(item[NIClient], position);
	GetClientEyeAngles(item[NIClient], angles);
	int dropped = CreateDroppedWeapon(created, item[NIClient], position, angles);

	if(dropped == INVALID_ENT_REFERENCE) {
		PrintToServer("CreateDroppedWeapon failed");
		return;
	}

	PrintToServer("Dropped weapon created");

	gCreatedWeapons.Push(dropped);

	//Unequip invisible replaced item
	// TF2_RemoveWeaponSlot(item[NIClient], slot);

	PrintToServer("Initial replacement item unequipped");

	//"Pick up" dropped weapon, which will be visible
	SDKCall(hPickupWeaponFromOther, item[NIClient], dropped);

	PrintToServer("Dropped weapon picked up");

	PrintToServer("Done");
	delete replacement;
}

stock Handle CreateReplacementItem(NamedItem item[NamedItem]) {
	bool replace = false;

	PrintToServer("Frame_UpdateItem");

	if(gBlockedQualities.FindValue(item[NIQuality]) > -1) {
		PrintToServer("Blocked quality %d found", item[NIQuality]);
		item[NIQuality] = 6;
		replace = true;
	}

	// PrintToServer("Trying TF2Attrib_GetSOCAttribs");

	int attributes[16];
	float attributeValues[16];
	int attributeCount = TF2Attrib_GetSOCAttribs(item[NIEntity], attributes, attributeValues);
	int allowedAttributeCount = 0;
	
	// PrintToServer("Checking attributes, count %d", attributeCount);

	if(attributeCount != -1) {
		for(int i = 0; i < attributeCount; i++) {
			// PrintToServer("Checking attribute %d found, value %f", attributes[i], attributeValues[i]);
			if(gBlockedAttributes.FindValue(attributes[i]) > -1) {
				PrintToServer("Blocked attribute %d found, value %f", attributes[i], attributeValues[i]);
				replace = true;
			} else {
				allowedAttributeCount++;
			}
		}
	} else {
		PrintToServer("Failed to get attributes");
		replace = true;
	}

	if(!replace) {
		return INVALID_HANDLE;
	}

	PrintToServer("Replacing weapon");
	
	//FIXME: try to fix GiveNamedItem failing or crashing server (FORCE_GENERATION?)

	Handle replacement = TF2Items_CreateItem(PRESERVE_ATTRIBUTES | OVERRIDE_ALL | FORCE_GENERATION);
	TF2Items_SetQuality(replacement, item[NIQuality] ? item[NIQuality] : 6);
	TF2Items_SetItemIndex(replacement, item[NIDefIndex]);
	TF2Items_SetLevel(replacement, item[NILevel]);
	TF2Items_SetClassname(replacement, item[NIClassname]);
	TF2Items_SetNumAttributes(replacement, allowedAttributeCount);

	int index = 0;

	for(int i = 0; i < attributeCount; i++) {
		if(gBlockedAttributes.FindValue(attributes[i]) == -1) {
			PrintToServer("Adding attribute %d, value %f", attributes[i], attributeValues[i]);
			TF2Items_SetAttribute(replacement, index, attributes[i], attributeValues[i]);
			index++;
		}
	}

	return replacement;
}

public void AustraliumFix(int entity) {
	SetVariantInt(1);
	AcceptEntityInput(entity, "skin", entity, entity);
}

public void YearChanged(ConVar convar, char[] oldValue, char[] newValue) {
	PrintToServer("%i", year.IntValue);

	gBlockedQualities.Clear();
	gBlockedAttributes.Clear();

	if(year.IntValue < 2008) {
		gBlockedQualities.Push(6); //Unique
		gBlockedAttributes.Push(142); //Paint
	}

	if(year.IntValue < 2010) {
		gBlockedQualities.Push(5); //Unusual
		gBlockedQualities.Push(3); //Vintage
	}

	if(year.IntValue < 2011) {
		gBlockedQualities.Push(11); //Strange
		gBlockedQualities.Push(13); //Haunted
		gBlockedQualities.Push(1); //Genuine
		gBlockedAttributes.Push(214); //Strange counter
		gBlockedAttributes.Push(294); //Strange counter 2
		gBlockedAttributes.Push(134); //Unusual effect
		gBlockedAttributes.Push(747); //Unusual effect
	}
	
	if(year.IntValue < 2012) {
		gBlockedAttributes.Push(379); //Strange parts
		gBlockedAttributes.Push(380); //Strange parts
		gBlockedAttributes.Push(381); //Strange parts
		gBlockedAttributes.Push(382); //Strange parts
		gBlockedAttributes.Push(383); //Strange parts
		gBlockedAttributes.Push(384); //Strange parts
		gBlockedAttributes.Push(385); //Strange parts
	}

	if(year.IntValue < 2013) {
		gBlockedAttributes.Push(2013); //Killstreak 
		gBlockedAttributes.Push(2014); //Killstreak Sheen
		gBlockedAttributes.Push(2025); //Killstreak Tier
		gBlockedAttributes.Push(2027); //Australium
	}

	if(year.IntValue < 2014) {
		gBlockedQualities.Push(14); //Collector's
		gBlockedQualities.Push(750); //Unusual taunt
	}

	if(year.IntValue < 2015) {
		gBlockedQualities.Push(15); //Decorated
		gBlockedAttributes.Push(725); //Skin wear
		gBlockedAttributes.Push(2053); //Festivized
		gBlockedAttributes.Push(731); //Inspecting
	}

	//War paints
	if(year.IntValue < 2015) {
		gBlockedAttributes.Push(834);
		gBlockedAttributes.Push(866);
		gBlockedAttributes.Push(867);
	}

	gBlockedAttributes.Push(143);
	gBlockedAttributes.Push(185);
	gBlockedAttributes.Push(211);
	gBlockedAttributes.Push(302);
	gBlockedAttributes.Push(374);
	gBlockedAttributes.Push(751);
	gBlockedAttributes.Push(2010);
	gBlockedAttributes.Push(2011);
}

public Action Buildings_CanPlayerPickup(int client, int building, bool &result) {
	if(year.IntValue < 2010) {
		result = false;

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

stock int GetWeaponSlot(int client, int weapon) {
	if (client == 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || weapon == 0 || weapon < MaxClients || !IsValidEntity(weapon))
		return -1;

	for (int i = 0; i < 5; i++)
	{
		if (GetPlayerWeaponSlot(client, i) != weapon)
			continue;

		return i;
	}

	return -1;
}

// public int SpawnWeapon(int entity, const char[] name, ConfigWeapon configWeapon[ConfigWeapon], int client) {
// 	float origin[3];
// 	float angles[3];
// 	char model[128];

// 	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
// 	GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);  
// 	GetEntPropString(entity, Prop_Data, "m_ModelName", model, 128);
	
// 	int weapon = CreateWeapon(client, configWeapon);
// 	int dropped = CreateDroppedWeapon(weapon, client, origin, angles);

// 	SetEntityMoveType(dropped, MOVETYPE_NONE);

// 	return dropped;
// }

int CreateDroppedWeapon(int fromWeapon, int client, const float origin[3], const float angles[3]) {
	// Offset of the CEconItemView class inlined on the weapon.
	// Manually using FindSendPropInfo as 1) it's a sendtable, not a value,
	// and 2) we just want a pointer to it, not the value at that address.
	int itemOffset = FindSendPropInfo("CTFWeaponBase", "m_Item");

	if(itemOffset == -1) {
		ThrowError("Failed to find m_Item on CTFWeaponBase");
	}
	
	// Can't get model directly. Instead get index and look it up in string table.
	char model[PLATFORM_MAX_PATH];
	int modelidx = GetEntProp(fromWeapon, Prop_Send, "m_iWorldModelIndex");
	ModelIndexToString(modelidx, model, sizeof(model));
	
	int droppedWeapon = SDKCall(hCreateDroppedWeapon, client, origin, angles, model, GetEntityAddress(fromWeapon) + view_as<Address>(itemOffset));
	
	if(droppedWeapon != INVALID_ENT_REFERENCE) {
		SDKCall(hInitDroppedWeapon, droppedWeapon, client, fromWeapon, false, false);
	}

	return droppedWeapon;
}

void ModelIndexToString(int index, char[] model, int size) {
	int table = FindStringTable("modelprecache");
	ReadStringTable(table, index, model, size);
}

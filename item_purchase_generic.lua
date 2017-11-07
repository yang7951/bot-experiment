local items = require(GetScriptDirectory() .. "/ItemUtility" )
--local roles = require(GetScriptDirectory() .. "/RoleUtilityAlt" )
local role = require(GetScriptDirectory() .. "/RoleUtility" )

local bot = GetBot();

if  ( bot:GetUnitName() == 'npc_dota_hero_monkey_king' and DotaTime() < -60 and bot:GetLocation() ~= Vector(0.000000, 0.000000, 0.000000) )
    or bot:IsInvulnerable() or bot:IsHero() == false or bot:IsIllusion()
then
	return;
end

local purchase = "NOT IMPLEMENTED";

if bot:IsHero() then
	purchase = require(GetScriptDirectory() .. "/builds/item_build_" .. string.gsub(GetBot():GetUnitName(), "npc_dota_hero_", ""));
end

--Prevent meepo clone to perform item purchase
if  bot:GetUnitName() == 'npc_dota_hero_meepo' and DotaTime() > -60 then
	bot.clone = true;
	local item_count = 0;
	for i=0,5 do
		local item = bot:GetItemInSlot(i);
		if item ~= nil then
			item_count = item_count + 1;
		end
	end
	if item_count > 1  then
		bot.clone = false;	
	end
end

--Still failed to prevent arc warden tempest double to buy items so I checked it in Think() function
if bot:GetUnitName() == 'npc_dota_hero_arc_warden' and DotaTime() > -60 then
	bot.clone = false;
	if bot:HasModifier('modifier_arc_warden_tempest_double') then
		print("I'm arc warden clone")
		bot.clone = true;	
	end
end

if bot.clone == true then purchase = "NOT IMPLEMENTED"; end

if purchase == "NOT IMPLEMENTED" then return; end

--clone skill build to bot.abilities in reverse order 
--plus overcome the usage of the same memory address problem for bot.abilities in same heroes game which result in bot failed to level up correctly 
bot.itemToBuy = {};
bot.currentItemToBuy = nil;
bot.currentComponentToBuy = nil;
bot.currListItemToBuy = {};
bot.SecretShop = false;
bot.SideShop = false;
local unitName = bot:GetUnitName();

--Swap items order
for i=1, math.ceil(#purchase['items']/2) do
	bot.itemToBuy[i] = purchase['items'][#purchase['items']-i+1]; 
	bot.itemToBuy[#purchase['items']-i+1] = purchase['items'][i];
end

--[[bot.itemToBuy = {
	"item_tranquil_boots",
	"item_magic_wand",
};]]--

---add tango and healing salve as starting consumables item
---add stout shield + queling blade for melee carry and stout shield for melee non carry
if DotaTime() < -60 then
	if bot:GetAttackRange() < 320 and unitName ~= 'npc_dota_hero_templar_assassin' and unitName ~= 'npc_dota_hero_tidehunter' then
		if role.IsCarry(unitName) then
			bot.itemToBuy[#bot.itemToBuy+1] = 'item_quelling_blade';
			bot.itemToBuy[#bot.itemToBuy+1] = 'item_stout_shield';
		else
			bot.itemToBuy[#bot.itemToBuy+1] = 'item_stout_shield';
		end
	end
	bot.itemToBuy[#bot.itemToBuy+1] = 'item_flask';
	bot.itemToBuy[#bot.itemToBuy+1] = 'item_tango';
end
--------------------------------

---Update the status to prevent bots selling stout shield and queling blade
local buildBFury = false;
local buildVanguard = false;
local buildBloodStone = false;
for i=1, math.ceil(#bot.itemToBuy/2) do
	if bot.itemToBuy[i] == "item_bfury" or bot.itemToBuy[#bot.itemToBuy-i+1] == "item_bfury" then
		buildBFury = true;
	end
	if bot.itemToBuy[i] == "item_vanguard" or bot.itemToBuy[#bot.itemToBuy-i+1] == "item_vanguard" 
	or bot.itemToBuy[i] == "item_crimson_guard" or bot.itemToBuy[#bot.itemToBuy-i+1] == "item_crimson_guard"
	or bot.itemToBuy[i] == "item_abyssal_blade" or bot.itemToBuy[#bot.itemToBuy-i+1] == "item_abyssal_blade"
	then
		buildVanguard = true;
	end
	if bot.itemToBuy[i] == "item_bloodstone" or bot.itemToBuy[#bot.itemToBuy-i+1] == "item_bloodstone" then
		buildBloodStone = true;
	end
end
--------------------------------------------------------------------------

--[[print(bot:GetUnitName())
for i=1, #bot.itemToBuy do
	print(bot.itemToBuy[i])
end]]--

local courier = nil;
local buytime = -90;
local check_time = -90;

--bot.currRole = roles.GetRole(unitName);

local lastItemToBuy = nil;
local CanPurchaseFromSecret = false;
local CanPurchaseFromSide = false;
local itemCost = 0;
local courier = nil;
local t3AlreadyDamaged = false;
local t3Check = -90;

--General item purchase logis
local function GeneralPurchase()

	--Cache all needed item properties when the last item to buy not equal to current item component to buy
	if lastItemToBuy ~= bot.currentComponentToBuy then
		lastItemToBuy = bot.currentComponentToBuy;
		bot:SetNextItemPurchaseValue( GetItemCost( bot.currentComponentToBuy ) );
		CanPurchaseFromSecret = IsItemPurchasedFromSecretShop(bot.currentComponentToBuy);
		CanPurchaseFromSide   = IsItemPurchasedFromSideShop(bot.currentComponentToBuy);
		itemCost = GetItemCost( bot.currentComponentToBuy );
		lastItemToBuy = bot.currentComponentToBuy ;
	end
	
	local cost = itemCost;
	
	--Save the gold for buyback whenever a tier 3 tower damaged or destroyed
	if t3AlreadyDamaged == false and DotaTime() > t3Check + 1.0 then
		for i=2, 8, 3 do
			local tower = GetTower(GetTeam(), i);
			if tower == nil or tower:GetHealth()/tower:GetMaxHealth() < 0.5 then
				t3AlreadyDamaged = true;
				break;
			end
		end
		t3Check = DotaTime();
	elseif t3AlreadyDamaged == true and bot:GetBuybackCooldown() <= 10 then
		cost = itemCost + bot:GetBuybackCost() + ( 100 + bot:GetNetWorth()/40 );
	end
	
	--buy the item if we have the gold
	if ( bot:GetGold() >= cost ) then
		
		if courier == nil then
			courier = GetCourier(0);
		end
		
		--purchase done by courier for secret shop item
		if bot.SecretShop and courier ~= nil and GetCourierState(courier) == COURIER_STATE_IDLE and courier:DistanceFromSecretShop() == 0 then
			if courier:ActionImmediate_PurchaseItem( bot.currentComponentToBuy ) == PURCHASE_ITEM_SUCCESS then
				bot.currentComponentToBuy = nil;
				bot.currListItemToBuy[#bot.currListItemToBuy] = nil; 
				courier.latestUser = bot;
				bot.SecretShop = false;
			    bot.SideShop = false;
				return
			end
		end
		
		--Get bot distance from side shop and secret shop
		local dSecretShop = bot:DistanceFromSecretShop();
		local dSideShop   = bot:DistanceFromSideShop();
		
		--Logic to decide in which shop bot have to purchase the item
		if CanPurchaseFromSecret and CanPurchaseFromSide == false and bot:DistanceFromSecretShop() > 0 then
			bot.SecretShop = true;
		elseif CanPurchaseFromSecret and CanPurchaseFromSide and dSideShop < dSecretShop and dSideShop > 0 and dSideShop <= 2500 then
			bot.SideShop = true;
		elseif CanPurchaseFromSecret and CanPurchaseFromSide and dSideShop > dSecretShop and dSecretShop > 0 then
			bot.SecretShop = true;
		elseif CanPurchaseFromSecret and CanPurchaseFromSide and dSideShop > 2500 and dSecretShop > 0 then
			bot.SecretShop = true;
		elseif CanPurchaseFromSide and CanPurchaseFromSecret == false and bot:DistanceFromSideShop() > 0 and bot:DistanceFromSideShop() <= 2500 then
			bot.SideShop = true;
		else
			if bot:ActionImmediate_PurchaseItem( bot.currentComponentToBuy ) == PURCHASE_ITEM_SUCCESS then
				bot.currentComponentToBuy = nil;
				bot.currListItemToBuy[#bot.currListItemToBuy] = nil; 
				bot.SecretShop = false;
				bot.SideShop = false;	
				return
			else
				print("[item_purchase_generic] "..bot:GetUnitName().." failed to purchase "..bot.currentComponentToBuy.." : "..tostring(bot:ActionImmediate_PurchaseItem( bot.currentComponentToBuy )))	
			end
		end	
	else
		bot.SecretShop = false;
		bot.SideShop = false;
	end
end

--Turbo Mode General item purchase logis
local function TurboModeGeneralPurchase()
	--Cache all needed item properties when the last item to buy not equal to current item component to buy
	if lastItemToBuy ~= bot.currentComponentToBuy then
		lastItemToBuy = bot.currentComponentToBuy;
		bot:SetNextItemPurchaseValue( GetItemCost( bot.currentComponentToBuy ) );
		itemCost = GetItemCost( bot.currentComponentToBuy );
		lastItemToBuy = bot.currentComponentToBuy ;
	end
	
	local cost = itemCost;
	
	--Save the gold for buyback whenever a tier 3 tower damaged or destroyed
	if t3AlreadyDamaged == false and DotaTime() > t3Check + 1.0 then
		for i=2, 8, 3 do
			local tower = GetTower(GetTeam(), i);
			if tower == nil or tower:GetHealth()/tower:GetMaxHealth() < 0.5 then
				t3AlreadyDamaged = true;
				break;
			end
		end
		t3Check = DotaTime();
	elseif t3AlreadyDamaged == true and bot:GetBuybackCooldown() <= 10 then
		cost = itemCost + bot:GetBuybackCost() + ( 100 + bot:GetNetWorth()/40 );
	end
	
	--buy the item if we have the gold
	if ( bot:GetGold() >= cost ) then
		if bot:ActionImmediate_PurchaseItem( bot.currentComponentToBuy ) == PURCHASE_ITEM_SUCCESS then
			bot.currentComponentToBuy = nil;
			bot.currListItemToBuy[#bot.currListItemToBuy] = nil; 
			bot.SecretShop = false;
			bot.SideShop = false;	
			return
		else
			print("[item_purchase_generic] "..bot:GetUnitName().." failed to purchase "..bot.currentComponentToBuy.." : "..tostring(bot:ActionImmediate_PurchaseItem( bot.currentComponentToBuy )))	
		end
	end
end

local lastInvCheck = -90;
local fullInvCheck = -90;
local lastBootsCheck = -90;
local buyBootsStatus = false;
local addVeryLateGameItem = false
local buyRD = false;
local buyTP = false;
local buyBottle = false;

function ItemPurchaseThink()  
	
	if ( GetGameState() ~= GAME_STATE_PRE_GAME and GetGameState() ~= GAME_STATE_GAME_IN_PROGRESS )
	then
		return;
	end
	
	if bot:HasModifier('modifier_arc_warden_tempest_double') then
		bot.itemToBuy = {};
		return
	end
	
	--replace tango with faerie fire for midlaner
	if DotaTime() < 0 and bot:DistanceFromFountain() == 0 and bot.theRole == "midlaner" and bot.currentItemToBuy == nil and GetGameMode() ~= GAMEMODE_1V1MID
	then
		local tango = bot:FindItemSlot("item_tango");
		if tango >= 0 then
			bot:ActionImmediate_SellItem(bot:GetItemInSlot(tango));
			bot.itemToBuy[#bot.itemToBuy+1] = "item_faerie_fire";
		end	
	end
	
	--add bottle to item to purchase for midlaner 
	if DotaTime() > 0 and DotaTime() < 15 and #bot.currListItemToBuy > 0 and GetGameMode() ~= GAMEMODE_1V1MID
	   and bot:GetAssignedLane() == LANE_MID and role["bottle"][unitName] == 1 and buyBottle == false
	then
		bot.currListItemToBuy[#bot.currListItemToBuy+1]  =  "item_bottle";
		buyBottle = true;
	end
	
	--Update support availability status
	if role['supportExist'] == nil then role.UpdateSupportStatus(bot); end
	
	--Update invisible hero or item availability status
	if role['invisEnemyExist'] == false then role.UpdateInvisEnemyStatus(bot); end
	
	--Update boots availability status to make the bot start buy support item and rain drop
	if buyBootsStatus == false and DotaTime() > lastBootsCheck + 2.0 then buyBootsStatus = items.UpdateBuyBootStatus(bot); lastBootsCheck = DotaTime() end
	
	--purchase flying courier and support item
	if bot.theRole == 'support' then
		if DotaTime() < 0 and GetItemStockCount( "item_courier" ) > 0 
		then
			bot:ActionImmediate_PurchaseItem( 'item_courier' );
		elseif DotaTime() < 0 and bot:GetGold() >= GetItemCost( "item_smoke_of_deceit" ) 
			and GetItemStockCount( "item_smoke_of_deceit" ) > 1 and items.GetEmptyInventoryAmount(bot) >= 4 
		then
			bot:ActionImmediate_PurchaseItem("item_smoke_of_deceit"); 	
		elseif DotaTime() < 0 and bot:GetGold() >= GetItemCost( "item_clarity" ) and items.HasItem(bot, "item_clarity") == false 
		then
			bot:ActionImmediate_PurchaseItem("item_clarity");	
		elseif role['invisEnemyExist'] == true and buyBootsStatus == true and bot:GetGold() >= GetItemCost( "item_dust" ) 
			and items.GetEmptyInventoryAmount(bot) >= 4 and items.GetItemCharges(bot, "item_dust") < 1 and bot:GetCourierValue() == 0 
		then
			bot:ActionImmediate_PurchaseItem("item_dust"); 
		elseif GetItemStockCount( "item_ward_observer" ) > 0 and ( DotaTime() < 0 or( DotaTime() > 0 and buyBootsStatus == true ) ) and bot:GetGold() >= GetItemCost( "item_ward_observer" ) 
			and items.GetEmptyInventoryAmount(bot) >= 2 and items.GetItemCharges(bot, "item_ward_observer") < 2  and bot:GetCourierValue() == 0
		then
			bot:ActionImmediate_PurchaseItem("item_ward_observer"); 
		end
	end
	
	--purchase courier when no support in team
	if DotaTime() < 0 and role['supportExist'] == false and GetItemStockCount( "item_courier" ) > 0 then 
		bot:ActionImmediate_PurchaseItem( 'item_courier' );
	end
	
	--purchase raindrop
	if buyRD == false and buyBootsStatus == true and GetItemStockCount( "item_infused_raindrop" ) > 0 and bot:GetGold() >= GetItemCost( "item_infused_raindrop" ) and items.HasItem(bot, 'item_boots')
	then
		bot:ActionImmediate_PurchaseItem("item_infused_raindrop"); 
		buyRD = true;
	end
	
	---buy tom of knowledge
	if GetItemStockCount( "item_tome_of_knowledge" ) > 0 and bot:GetGold() >= GetItemCost( "item_tome_of_knowledge" ) and 
	   items.GetEmptyInventoryAmount(bot) >= 4 and role.IsTheLowestLevel(bot)
	then
		bot:ActionImmediate_PurchaseItem("item_tome_of_knowledge"); 
	end	
	  
	--sell early game item   
	if DotaTime() > 20*60 and DotaTime() > fullInvCheck + 2.0 and ( bot:DistanceFromFountain() == 0 or bot:DistanceFromSecretShop() == 0 ) then
		local emptySlot = items.GetEmptyInventoryAmount(bot);
		local slotToSell = nil;
		if emptySlot < 2 then
			for i=1,#items['earlyGameItem'] do
				local item = items['earlyGameItem'][i];
				local itemSlot = bot:FindItemSlot(item);
				if itemSlot > 0 then
					if ( item == "item_dust" or item == "item_ward_observer" ) then
						if  emptySlot <= 1 then
							slotToSell = itemSlot;
							break;
						end
					elseif item == "item_stout_shield" then
						if buildVanguard == false  then
							slotToSell = itemSlot;
							break;
						end
					elseif item == "item_tpscroll" then
						if bot:FindItemSlot("item_travel_boots") > 0  then
							slotToSell = itemSlot;
							break;
						end
					elseif item == "item_soul_ring" then
						if buildBloodStone == false then
							slotToSell = itemSlot;
							break;
						end
					elseif item == "item_quelling_blade" then
						if buildBFury == false then
							slotToSell = itemSlot;
							break;
						end
					else
						slotToSell = itemSlot;
						break;
					end
				end
			end
		end	
		if slotToSell ~= nil then
			bot:ActionImmediate_SellItem(bot:GetItemInSlot(slotToSell));
		end
		fullInvCheck = DotaTime();
	end
	
	--Sell non BoT boots when have BoT
	if DotaTime() > 40*60 and ( items.HasItem( bot, "item_travel_boots") or items.HasItem( bot, "item_travel_boots_2")) and
	   ( bot:DistanceFromFountain() == 0 or bot:DistanceFromSecretShop() == 0 )
	then	
		for i=1,#items['earlyBoots']
		do
			local bootsSlot = bot:FindItemSlot(items['earlyBoots'][i]);
			if bootsSlot >= 0 then
				bot:ActionImmediate_SellItem(bot:GetItemInSlot(bootsSlot));
			end
		end
	end
	
	--Insert tp scroll to list item to buy and then change the buyTP flag so the bots don't reapeatedly add the tp scroll to list item to buy 
	if buyTP == false and items.HasItem(bot, 'item_travel_boots') == false and items.HasItem(bot, 'item_travel_boots_2') == false and DotaTime() > 0 and bot:GetCourierValue() == 0 and bot:FindItemSlot('item_tpscroll') == -1 then
		bot.currentComponentToBuy = nil;	
		bot.currListItemToBuy[#bot.currListItemToBuy+1] = 'item_tpscroll';
		buyTP = true;
		return
	end
	--Change the flag to buy tp scroll to false when it already has it in inventory so the bot can insert tp scroll to list item to buy whenever they don't have any tp scroll
	if buyTP == true and bot:FindItemSlot('item_tpscroll') > -1 then
		buyTP = false;
	end
	
	--Fill purchase table with super late game item
	if #bot.itemToBuy == 0 and addVeryLateGameItem == false then
		bot.itemToBuy = {
			'item_travel_boots_2',
			'item_moon_shard',	
		}
		if items.HasItem(bot, 'item_travel_boots') == false then
			bot.itemToBuy[#bot.itemToBuy+1] = 'item_travel_boots';
		end
		addVeryLateGameItem = true;
	end
	
	--No need to purchase item when not item to purchase in the list
	if #bot.itemToBuy == 0 then bot:SetNextItemPurchaseValue( 0 ); return; end
	
	--Get the next item to buy and break it to item components then add it to currListItemToBuy. 
	--It'll only done if the bot already has the item that formed from its component in their hero's inventory (not stash) to prevent unintended item combining
	if  bot.currentItemToBuy == nil and #bot.currListItemToBuy == 0 then
		bot.currentItemToBuy = bot.itemToBuy[#bot.itemToBuy];
		local tempTable = items.GetBasicItems({bot.currentItemToBuy})
		if bot.currentItemToBuy == "item_bfury" then 
			tempTable = items.RemoveItem(tempTable, "item_quelling_blade");
		elseif 	bot.currentItemToBuy == "item_crimson_guard" then
			tempTable = items.RemoveItem(tempTable, "item_stout_shield");
		elseif 	bot.currentItemToBuy == "item_vanguard" then
			tempTable = items.RemoveItem(tempTable, "item_stout_shield");
		end
		for i=1,math.ceil(#tempTable/2) 
		do	
			bot.currListItemToBuy[i] = tempTable[#tempTable-i+1];
			bot.currListItemToBuy[#tempTable-i+1] = tempTable[i];
		end
		
	end
	
	--Check if the bot already has the item formed from its components in their inventory (not stash)
	if  #bot.currListItemToBuy == 0 and DotaTime() > lastInvCheck + 3.0 then
	    if items.IsItemInHero(bot.currentItemToBuy) then
			bot.currentItemToBuy = nil; 
			bot.itemToBuy[#bot.itemToBuy] = nil;
		else
			lastInvCheck = DotaTime();
		end
	--Added item component to current item component to buy and do the purchase	
	elseif #bot.currListItemToBuy > 0 then
		if bot.currentComponentToBuy == nil then
			bot.currentComponentToBuy = bot.currListItemToBuy[#bot.currListItemToBuy]; 
		else
			if GetGameMode() == 23 then
				TurboModeGeneralPurchase();
			else
				GeneralPurchase();
			end	
		end
	end

end



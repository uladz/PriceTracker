-- ------------- --
-- Price Tracker --
-- ------------- --

PriceTracker = {
	isSearching = false,
	settingsVersion = 0.3,
	colors = {
		default = "|c" .. ZO_TOOLTIP_DEFAULT_COLOR:ToHex(),
		instructional = "|c" .. ZO_TOOLTIP_INSTRUCTIONAL_COLOR:ToHex(),
		title = "|c00B5FF",
	},
	selectedItem = {},
}
local PriceTracker = PriceTracker

-- Addon initialization
function PriceTracker:OnLoad(eventCode, addOnName)
	if(addOnName ~= "PriceTracker") then return end

	EVENT_MANAGER:RegisterForEvent("OnSearchResultsReceived", EVENT_TRADING_HOUSE_SEARCH_RESULTS_RECEIVED, function(...) self:OnSearchResultsReceived(...) end)
	EVENT_MANAGER:RegisterForEvent("OnSearchResultsError", EVENT_TRADING_HOUSE_ERROR, function(...) self:OnSearchResultsError(...) end)
	EVENT_MANAGER:RegisterForEvent("OnTradingHouseOpened", EVENT_OPEN_TRADING_HOUSE, function(...) self:OnTradingHouseOpened(...) end)
	EVENT_MANAGER:RegisterForEvent("OnTradingHouseClosed", EVENT_CLOSE_TRADING_HOUSE, function(...) self:OnTradingHouseClosed(...) end)
	EVENT_MANAGER:RegisterForEvent("OnTradingHouseCooldown", EVENT_TRADING_HOUSE_SEARCH_COOLDOWN_UPDATE, function(...) self:OnTradingHouseCooldown(...) end)

	LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_CLICKED_EVENT, self.OnLinkClicked, self)
	LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_MOUSE_UP_EVENT, self.OnLinkClicked, self)

	ZO_PreHookHandler(ItemTooltip, "OnUpdate", function() self:OnUpdateTooltip(moc(), ItemTooltip) end)
	ZO_PreHookHandler(ItemTooltip, "OnHide", function() self:OnHideTooltip(ItemTooltip) end)

	ZO_PreHookHandler(PopupTooltip, "OnUpdate", function() self:OnUpdateTooltip(self.clickedItem, PopupTooltip) end)
	ZO_PreHookHandler(PopupTooltip, "OnHide", function() self:OnHideTooltip(PopupTooltip) end)

	ZO_PreHook("ExecuteTradingHouseSearch", function() self.scanButton:SetEnabled(false) end)

	PriceTracker.enchantingTable:OnLoad(eventCode, addOnName)

	SLASH_COMMANDS["/pt"] = function(...) self:CommandHandler(...) end
	SLASH_COMMANDS["/pricetracker"] = function(...) self:CommandHandler(...) end

	local defaults = {
		itemList = {},
		algorithm = self.menu.algorithmTable[4],
		showMinMax = true,
		showSeen = true,
		historyDays = 30,
		ignoreFewItems = false,
		keyPress = self.menu.keyTable[1],
		isPlaySound = true,
		playSound = self.menu.soundTable[1],
	}

	-- Load saved settings
	self.settings = ZO_SavedVars:NewAccountWide("PriceTrackerSettings", self.settingsVersion, nil, defaults)

	-- Do some housekeeping and remove inparsable items 
	self:Housekeeping()

	-- Create a button in the trading house window
	self.scanButton = PriceTrackerControlButton
	self.scanButton:SetParent(ZO_TradingHouseLeftPaneBrowseItemsCommon)
	self.scanButton:SetWidth(ZO_TradingHouseLeftPaneBrowseItemsCommonQuality:GetWidth())
	self.stopButton = PriceTrackerStopButton
	self.stopButton:SetParent(ZO_TradingHouseLeftPaneBrowseItemsCommon)
	self.stopButton:SetWidth(ZO_TradingHouseLeftPaneBrowseItemsCommonQuality:GetWidth())

	self.menu:InitAddonMenu()
end

-- Handle slash commands
function PriceTracker:CommandHandler(text)
	text = text:lower()

	if #text == 0 or text == "help" then
		self:ShowHelp()
		return
	end

	if text == "reset" then
		self.settings.itemList = {}
		return
	end

	if text:find("^clean") then
		local days = select(3, text:find("^clean (%d+)"))
		days = tonumber(days) or 30
		self:CleanItemList(days)
		return
	end

	-- Hidden option
	if text == "housekeeping" then
		self:Housekeeping()
		return
	end

end

function PriceTracker:ShowHelp()
	d("To scan all item prices in all guild stores, click the 'Scan Prices' button in the guild store window.")
	d(" ")
	d("/pt help - Show this help")
	d("/pt clean <days> - Remove prices older then <days> (30 days if not specified)")
	d("/pt reset - Remove all stored price values")
	d("/ptsetup - Open the addon settings menu")
end

-- This method makes sure the item list is intact and parsable, in order to avoid exceptions later on
function PriceTracker:Housekeeping()
	if not self.settings.itemList then
		self.settings.itemList = {}
	end

	-- Preserve prices from previous UI versions
	if PriceTrackerSettings["Default"][""] ~= nil then
		PriceTrackerSettings["Default"][GetDisplayName()] = PriceTrackerSettings["Default"][""]
		PriceTrackerSettings["Default"][""] = nil
		ReloadUI("ingame")
	end

	--expiry is time listed + 30 days. So if I want to keep items for 60 days, I have to use historyDays - 30
	local timestamp = GetTimeStamp() - 86400 * (self.settings.historyDays - 30)
	for k, v in pairs(self.settings.itemList) do
		if type(k) ~= "string" or #k > 5 then
			self.settings.itemList[k] = nil
		else
			for level, item in pairs(v) do
				for itemK, itemV in pairs(item) do
					-- Remove invalid and expired items
					if itemV.purchasePrice == nil or itemV.stackCount == nil or type(itemV.name) ~= "string" or type(itemV.expiry) ~= "number" or itemV.expiry < timestamp then
						item[itemK] = nil
					else -- Remove redundant keys from older data
						itemV.normalizedName = nil
						itemV.icon = nil
						itemV.sellerName = nil
						itemV.eachPrice = nil
					end
				end
				if next(item) == nil then v[level] = nil end
			end
		end
		if next(v) == nil then self.settings.itemList[k] = nil end
	end
end

function PriceTracker:OnUpdateTooltip(item, tooltip)
	if not tooltip then tooltip = ItemTooltip end
	if not item or not item.dataEntry or not item.dataEntry.data or not self.menu:IsKeyPressed() or self.selectedItem[tooltip] == item then return end
	self.selectedItem[tooltip] = item
	local stackCount = item.dataEntry.data.stackCount or item.dataEntry.data.stack or item.dataEntry.data.count
	if not stackCount then return end

	local itemLink = self:GetItemLink(item)
	local _, _, _, itemId = ZO_LinkHandler_ParseLink(itemLink)
	local level = self:GetItemLevel(itemLink)
	local quality = GetItemLinkQuality(itemLink)

	if not itemLink then
		if item.dataEntry and item.dataEntry.data and item.dataEntry.data.itemId then
			itemId = item.dataEntry.data.itemId
			level = tonumber(item.dataEntry.data.level)
			quality = item.dataEntry.data.quality
		else
			return
		end
	end

	local matches = self:GetMatches(itemId, level, quality)
	if not matches then return end

	local item = self:SuggestPrice(matches)
	if not item then return end

	local r, g, b = ZO_TOOLTIP_DEFAULT_COLOR:UnpackRGB()
	local function AddValuePair(leftText, rightText)
		tooltip:AddLine(leftText, "ZoFontGame", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, true)
		tooltip:AddVerticalPadding(-32)
		tooltip:AddLine(rightText, "ZoFontGame", r, g, b, RIGHT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_RIGHT, true)
	end

	tooltip:AddVerticalPadding(15)
	ZO_Tooltip_AddDivider(tooltip)
	tooltip:AddLine("Price Tracker", "ZoFontHeader2")
	AddValuePair("Suggested price:", ("|cFFFFFF%d|r |t16:16:EsoUI/Art/currency/currency_gold.dds|t"):format(zo_round(item.purchasePrice / item.stackCount)))
	if stackCount > 1 then
		tooltip:AddVerticalPadding(-6)
		AddValuePair("Stack price:", ("|cFFFFFF%d|r |t16:16:EsoUI/Art/currency/currency_gold.dds|t"):format(zo_round(item.purchasePrice / item.stackCount * stackCount)))
	end
	if self.settings.showMinMax then
		local minItem = self.mathUtils:Min(matches)
		local maxItem = self.mathUtils:Max(matches)
		local minPrice = zo_round(minItem.purchasePrice / minItem.stackCount)
		local maxPrice = zo_round(maxItem.purchasePrice / maxItem.stackCount)
		local minGuild = minItem.guildName and zo_strjoin(nil, "   (", zo_strtrim(("%-12.12s"):format(minItem.guildName)), ")") or ""
		local maxGuild = maxItem.guildName and zo_strjoin(nil, "  (", zo_strtrim(("%-12.12s"):format(maxItem.guildName)), ")") or ""
		tooltip:AddVerticalPadding(-6)
		AddValuePair("Min (each / stack):" .. minGuild, ("|cFFFFFF%d|r / |cFFFFFF%d|r |t16:16:EsoUI/Art/currency/currency_gold.dds|t"):format(minPrice, minPrice * stackCount))
		tooltip:AddVerticalPadding(-6)
		AddValuePair("Max (each / stack):" .. maxGuild, ("|cFFFFFF%d|r / |cFFFFFF%d|r |t16:16:EsoUI/Art/currency/currency_gold.dds|t"):format(maxPrice, maxPrice * stackCount))
	end
	if self.settings.showSeen then
		tooltip:AddLine("Seen " .. #matches .. " times", "ZoFontGame", r, g, b, CENTER, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_CENTER, false)
	end
end

function PriceTracker:OnHideTooltip(tooltip)
	self.selectedItem[tooltip] = nil
	self.clickedItem = nil
end

function PriceTracker:OnScanPrices()
	if self.isSearching then return end

	self.scanButton:SetEnabled(false)
	self.scanButton:SetHidden(true)
	self.stopButton:SetHidden(false)
	self.isSearching = true
	self.currentPage = 0
	self.currentGuildId = GetSelectedTradingHouseGuildId()
	self.currentGuildIndex = 1

	if self.currentGuildId and self.currentGuildId > 0 then --if using guild trader, self.currentGuildId is nil 
		self.numOfGuilds = GetNumTradingHouseGuilds()
		self.currentGuildId = GetGuildId(self.currentGuildIndex)
		while not CanSellOnTradingHouse(self.currentGuildId) and self.currentGuildIndex < self.numOfGuilds do
			self.currentGuildIndex = self.currentGuildIndex + 1
			self.currentGuildId = GetGuildId(self.currentGuildIndex)
		end
		SelectTradingHouseGuildId(self.currentGuildId)
	end

	zo_callLater(function()
			if self.isSearching then
				ExecuteTradingHouseSearch(0, TRADING_HOUSE_SORT_SALE_PRICE, true)
			end
		end, GetTradingHouseCooldownRemaining() + 1000)
end

function PriceTracker:OnStopScan()
	self.isSearching = false
	self.stopButton:SetHidden(true)
	self.scanButton:SetHidden(false)
end

function PriceTracker:OnTradingHouseOpened(eventCode)
	self.isSearching = false
	self.scanButton:SetEnabled(true)
	self.stopButton:SetHidden(true)
	self.scanButton:SetHidden(false)
end

function PriceTracker:OnSearchResultsReceived(eventId, guildId, numItemsOnPage, currentPage, hasMorePages)
	self.currentGuildId = guildId
	self.currentGuildName = select(2, GetCurrentTradingHouseGuildDetails())
	for i = 1, numItemsOnPage do
		self:AddItem(i)
	end

	if not self.isSearching then return end

	self.currentPage = currentPage

	if hasMorePages then
		zo_callLater(function()
				if self.isSearching then
					ExecuteTradingHouseSearch(currentPage + 1, TRADING_HOUSE_SORT_SALE_PRICE, true)
				end
			end, GetTradingHouseCooldownRemaining() + 1000)
	else
		if self.currentGuildId and self.currentGuildId > 0 and self.currentGuildIndex and self.currentGuildIndex < self.numOfGuilds then
			self.currentGuildIndex = self.currentGuildIndex + 1
			self.currentGuildId = GetGuildId(self.currentGuildIndex)
			while not CanSellOnTradingHouse(self.currentGuildId) and self.currentGuildIndex < self.numOfGuilds do
				self.currentGuildIndex = self.currentGuildIndex + 1
				self.currentGuildId = GetGuildId(self.currentGuildIndex)
			end

			zo_callLater(function()
					if self.isSearching then
						SelectTradingHouseGuildId(self.currentGuildId)
						zo_callLater(function()
								if self.isSearching then
									ExecuteTradingHouseSearch(0, TRADING_HOUSE_SORT_SALE_PRICE, true)
								end
							end, GetTradingHouseCooldownRemaining() + 1000)
					end
				end, GetTradingHouseCooldownRemaining() + 1000)

		else
			if self.settings.isPlaySound then
				PlaySound(self.settings.playSound)
			end
			self:OnTradingHouseClosed()
		end
	end
end

function PriceTracker:OnTradingHouseCooldown(eventCode, cooldownMilliseconds)
	self.scanButton:SetEnabled(not self.isSearching)
end

function PriceTracker:OnSearchResultsError(eventCode, errorCode)
	if self.isSearching then
		d("Error scanning prices. Please try again.")
	end

	self:OnTradingHouseClosed()
end

function PriceTracker:OnTradingHouseClosed(eventCode)
	self.isSearching = false
	self.stopButton:SetHidden(true)
	self.scanButton:SetHidden(false)
end

function PriceTracker:OnLinkClicked(rawLink, mouseButton, linkText, linkStyle, linkType, itemId, ...)
	if linkType ~= ITEM_LINK_TYPE then return end

	local item = {
		dataEntry = {
			data = {
				stackCount = 1,
				itemId = itemId,
				level = self:GetItemLevel(rawLink),
				quality = GetItemLinkQuality(rawLink),
			}
		}
	}
	self.clickedItem = item
end

function PriceTracker:AddItem(index)
	local icon, itemName, quality, stackCount, sellerName, timeRemaining, purchasePrice = GetTradingHouseSearchResultItemInfo(index)
	local itemLink = GetTradingHouseSearchResultItemLink(index)
	local _, _, _, itemId = ZO_LinkHandler_ParseLink(itemLink)
	if not itemId then return end
	local level = self:GetItemLevel(itemLink)
	local expiry = timeRemaining + GetTimeStamp()

	if not purchasePrice or not stackCount then return end

	self.settings.itemList[itemId] = self.settings.itemList[itemId] or {}
	self.settings.itemList[itemId][level] = self.settings.itemList[itemId][level] or {}

	-- Do not add items that are already in the database
	if not self.settings.itemList[itemId][level][expiry] then
		local item = {
			expiry = expiry,
			name = itemName,
			quality = quality,
			stackCount = stackCount,
			purchasePrice = purchasePrice,
			guildId = self.currentGuildId or 0, --0 = kiosk
			guildName = self.currentGuildName
		}
		self.settings.itemList[itemId][level][expiry] = item
	end
end

function PriceTracker:CleanItemList(days)
	days = tonumber(days) or 30
	local timestamp = GetTimeStamp() - 86400 * (days - 30)
	for k, v in pairs(self.settings.itemList) do
		for level, item in pairs(v) do
			for itemK, itemV in pairs(item) do
				if itemV.expiry < timestamp then
					item[itemK] = nil
				end
			end
			if next(item) == nil then v[level] = nil end
		end
		if next(v) == nil then self.settings.itemList[k] = nil end
	end
end

function PriceTracker:GetMatches(itemId, itemLevel, quality)
	if not self.settings.itemList or not self.settings.itemList[itemId] then
		return nil
	end

	local limitToGuild = self.settings.limitToGuild or 1

	local matches = {}
	for level, items in pairs(self.settings.itemList[itemId]) do
		level = tonumber(level)
		if not itemLevel or itemLevel == level or (itemLevel < 2 and level < 2) then
			local index = next(items)
			while index do
				if items[index].quality == quality and (limitToGuild == 1 or items[index].guildId == GetGuildId(limitToGuild - 1)) then
					table.insert(matches, items[index])
				end
				index = next(items, index)
			end
		end
	end
	local minSeen = 0
	if self.settings.ignoreFewItems then minSeen = 2 end
	if #matches <= minSeen then return nil end
	return matches
end

function PriceTracker:SuggestPrice(matches)
	if self.settings.algorithm == self.menu.algorithmTable[1] then
		return self.mathUtils:Average(matches)
	end

	if self.settings.algorithm == self.menu.algorithmTable[2] then
		return self.mathUtils:Median(matches)
	end

	if self.settings.algorithm == self.menu.algorithmTable[3] then
		return self.mathUtils:Mode(matches)
	end
 
	if self.settings.algorithm == self.menu.algorithmTable[4] then
		return self.mathUtils:WeightedAverage(matches)
	end

	d("Error deciding how to calculate suggested price")
	return nil
end

function PriceTracker:GetItemLink(item)
	if not item or not item.GetParent then return nil end

	local parent = item:GetParent()
	if not parent then return nil end
	local parentName = parent:GetName()

	if parentName == "ZO_PlayerInventoryQuestContents" then
		return nil
	end
	if parentName == "ZO_StoreWindowListContents" then
		return GetStoreItemLink(item.dataEntry.data.slotIndex, LINK_STYLE_DEFAULT)
	end
	if parentName == "ZO_TradingHouseItemPaneSearchResultsContents" then
		if item.dataEntry.data.timeRemaining > 0 then
			return GetTradingHouseSearchResultItemLink(item.dataEntry.data.slotIndex, LINK_STYLE_DEFAULT)
		end
		return nil
	end
	if parentName == "ZO_TradingHousePostedItemsListContents" then
		return GetTradingHouseListingItemLink(item.dataEntry.data.slotIndex, LINK_STYLE_DEFAULT)
	end
	if parentName == "ZO_BuyBackListContents" then
		return GetBuybackItemLink(item.dataEntry.data.slotIndex, LINK_STYLE_DEFAULT)
	end
	if parentName:find("ZO_ListDialog%d+ListContents") then
		if item.dataEntry and item.dataEntry.data then 
			return GetItemLink(item.dataEntry.data.bag, item.dataEntry.data.index, LINK_STYLE_DEFAULT)
		end
		return nil
	end
	if parentName == "ZO_LootAlphaContainerListContents" then
		return GetLootItemLink(item.dataEntry.data.lootId, LINK_STYLE_DEFAULT)
	end

	if item.bagId and item.slotIndex then
		return GetItemLink(item.bagId, item.slotIndex, LINK_STYLE_DEFAULT)
	end
	if item.dataEntry and item.dataEntry.data and item.dataEntry.data.bagId and item.dataEntry.data.slotIndex then  
		return GetItemLink(item.dataEntry.data.bagId, item.dataEntry.data.slotIndex, LINK_STYLE_DEFAULT)
	end

	d("Could not get item link for " .. parentName)
	return nil
end

function PriceTracker:GetItemLevel(itemLink)
	local level = GetItemLinkRequiredLevel(itemLink)
	if level == 50 then
		level = level + GetItemLinkRequiredVeteranRank(itemLink)
	end
	return level
end

EVENT_MANAGER:RegisterForEvent("PriceTrackerLoaded", EVENT_ADD_ON_LOADED, function(...) PriceTracker:OnLoad(...) end)

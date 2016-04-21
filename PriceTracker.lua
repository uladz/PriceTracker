-- ------------- --
-- Price Tracker --
-- ------------- --

PriceTracker = {
  name = "PriceTracker",
  title = "Price Tracker",
  author = "Barvazon (updated by Garkin & @uladz)",
  version = "2.6.3",
	dbVersion = 0.3,

	colors = {
		default = "|c" .. ZO_TOOLTIP_DEFAULT_COLOR:ToHex(),
		instructional = "|c" .. ZO_TOOLTIP_INSTRUCTIONAL_COLOR:ToHex(),
		title = "|c00B5FF",
	},

  isSearching = false,
	selectedItem = {},
}
local PriceTracker = PriceTracker

-- List of support suggested price calculation algorithms.
PriceTracker.algorithmTable = {
	"Average",
	"Median",
	"Most Frequently Used",
	"Weighted Average",
}

-- Addon initialization.
function PriceTracker:OnLoad(eventCode, addOnName)
  if(addOnName ~= self.name) then
    return
  end

  -- Register for relevant trading house events.
  EVENT_MANAGER:RegisterForEvent("OnSearchResultsReceived",
      EVENT_TRADING_HOUSE_SEARCH_RESULTS_RECEIVED,
      function(...) self:OnSearchResultsReceived(...) end)
  EVENT_MANAGER:RegisterForEvent("OnSearchResultsError",
      EVENT_TRADING_HOUSE_ERROR,
      function(...) self:OnSearchResultsError(...) end)
	EVENT_MANAGER:RegisterForEvent("OnTradingHouseOpened",
      EVENT_OPEN_TRADING_HOUSE,
      function(...) self:OnTradingHouseOpened(...) end)
  EVENT_MANAGER:RegisterForEvent("OnTradingHouseClosed",
      EVENT_CLOSE_TRADING_HOUSE,
      function(...) self:OnTradingHouseClosed(...) end)
	EVENT_MANAGER:RegisterForEvent("OnTradingHouseCooldown",
      EVENT_TRADING_HOUSE_SEARCH_COOLDOWN_UPDATE,
      function(...) self:OnTradingHouseCooldown(...) end)

  -- ???
	LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_CLICKED_EVENT,
      self.OnLinkClicked, self)
	LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_MOUSE_UP_EVENT,
      self.OnLinkClicked, self)

  -- Register for item tooltip events.
	ZO_PreHookHandler(ItemTooltip, "OnUpdate",
      function() self:OnUpdateTooltip(moc(), ItemTooltip) end)
	ZO_PreHookHandler(ItemTooltip, "OnHide",
      function() self:OnHideTooltip(ItemTooltip) end)
	ZO_PreHookHandler(PopupTooltip, "OnUpdate",
      function() self:OnUpdateTooltip(self.clickedItem, PopupTooltip) end)
	ZO_PreHookHandler(PopupTooltip, "OnHide",
      function() self:OnHideTooltip(PopupTooltip) end)

  -- ???
	ZO_PreHook("ExecuteTradingHouseSearch",
      function() self.scanButton:SetEnabled(false) end)

  -- Forward OnLoad event to enchanting table handler.
	PriceTracker.enchantingTable:OnLoad(eventCode, addOnName)

  -- Register chat commands.
	SLASH_COMMANDS["/pt"] = function(...) self:CommandHandler(...) end
	SLASH_COMMANDS["/pricetracker"] = function(...) self:CommandHandler(...) end

  -- Load saved settings.
	local defaults = {
		itemList = {},
		algorithm = self.algorithmTable[4],
		showMinMax = true,
		showSeen = true,
		historyDays = 30,
		ignoreFewItems = false,
		keyPress = self.menu.keyTable[1],
		isPlaySound = true,
		playSound = self.menu.soundTable[1],
	}
	self.db = ZO_SavedVars:NewAccountWide(
      self.name.."Settings",
      self.dbVersion,
      nil,
      defaults)

	-- Do some housekeeping and remove inparsable items.
	self:Housekeeping()

	-- Create the addon setting menu.
	self.menu:InitAddonMenu()

	-- Create Price Tracker buttons in the trading house window. Note that second
	-- button [Stop Scan] is initially hidden.
	self.scanButton = PriceTrackerControlButton
	self.scanButton:SetParent(ZO_TradingHouseLeftPaneBrowseItemsCommon)
	self.scanButton:SetWidth(ZO_TradingHouseLeftPaneBrowseItemsCommonQuality:GetWidth())
	self.stopButton = PriceTrackerStopButton
	self.stopButton:SetParent(ZO_TradingHouseLeftPaneBrowseItemsCommon)
	self.stopButton:SetWidth(ZO_TradingHouseLeftPaneBrowseItemsCommonQuality:GetWidth())

	-- Publish addon API.
	local libAA = LibStub:GetLibrary("LibAddonAPI")
	libAA:RegisterAddon(self.name, 1)
end

-- Handle slash commands
function PriceTracker:CommandHandler(text)
	text = text:lower()

	if #text == 0 or text == "help" then
		self:ShowHelp()
		return
	end

	if text == "reset" then
		self.db.itemList = {}
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

-- This method makes sure the item list is intact and parsable, in order to
-- avoid exceptions later on. It runs only once on loading the addon.
function PriceTracker:Housekeeping()
	-- First time ever addon loaded.
	if not self.db.itemList then
		self.db.itemList = {}
		return
	end

	-- Expiry is time listed + 30 days. So if I want to keep items for 60 days,
	-- we have to use historyDays - 30.
	local timestamp = GetTimeStamp() - 86400 * (self.db.historyDays - 30)
	for k, v in pairs(self.db.itemList) do
		if type(k) ~= "string" or #k > 5 then
			self.db.itemList[k] = nil
		else
			for level, item in pairs(v) do
				for itemK, itemV in pairs(item) do
					-- Remove invalid and expired items.
					if itemV.purchasePrice == nil
							or itemV.stackCount == nil
							or type(itemV.name) ~= "string"
							or type(itemV.expiry) ~= "number"
							or itemV.expiry < timestamp then
						item[itemK] = nil
					-- Remove redundant keys from older data.
					else
						itemV.normalizedName = nil
						itemV.icon = nil
						itemV.sellerName = nil
						itemV.eachPrice = nil
					end
				end
				if next(item) == nil then
					v[level] = nil
				end
			end
		end
		if next(v) == nil then
			self.db.itemList[k] = nil
		end
	end
end

-- Helper function that adds a line to a tooltip with left text alligned to
-- the left and right text alligned to the right.
local function AddValuePair(tooltip, leftText, rightText)
	local r, g, b = ZO_TOOLTIP_DEFAULT_COLOR:UnpackRGB()
	tooltip:AddLine(leftText, "ZoFontGame", r, g, b,
			LEFT,
			MODIFY_TEXT_TYPE_NONE,
			TEXT_ALIGN_LEFT,
			true)
	tooltip:AddVerticalPadding(-32)
	tooltip:AddLine(rightText, "ZoFontGame", r, g, b,
			RIGHT,
			MODIFY_TEXT_TYPE_NONE,
			TEXT_ALIGN_RIGHT,
			true)
end

function PriceTracker:OnUpdateTooltip(item, tooltip)
	if not tooltip then
    tooltip = ItemTooltip
	end
	if not item
			or not item.dataEntry
			or not item.dataEntry.data
			or not self.menu:IsKeyPressed() then
		-- Tooltip has moved to another item but there is no Price Tracker info to
		-- show. Treat as hiding tooltip to avoid bug that no PT info is shown when
		-- returning back to the last item.
		if self.selectedItem[tooltip] ~= item then
			self:OnHideTooltip(tooltip)
		end
		return
	end
	if self.selectedItem[tooltip] == item then
		-- Tooltip is still showing the same item Price Tracker info, do nothing
		-- otherwise PT information will be duplicated.
		return
	end

	-- New item was selected, add Price Tracke info to this tooltip.
	self.selectedItem[tooltip] = item

	-- Get number of items or stacks.
	local stackCount = item.dataEntry.data.stackCount
			or item.dataEntry.data.stack
			or item.dataEntry.data.count
	if not stackCount then
		return
	end

	-- Get item metadata.
	local itemId, level, quality
	local itemLink = self:GetItemLink(item)
	if itemLink then
		_, _, _, itemId = ZO_LinkHandler_ParseLink(itemLink)
		level = self:GetItemLevel(itemLink)
		quality = GetItemLinkQuality(itemLink)
	else
		if item.dataEntry
				and item.dataEntry.data
				and item.dataEntry.data.itemId then
			itemId = item.dataEntry.data.itemId
			level = tonumber(item.dataEntry.data.level)
			quality = item.dataEntry.data.quality
		else
			return
		end
	end

	-- Search internal prices database.
	local matches = self:GetMatches(itemId, level, quality)
	if not matches then
		return
	end
	local item = self:SuggestPrice(matches)
	if not item then
		return
	end

	-- Add title.
	tooltip:AddVerticalPadding(15)
	ZO_Tooltip_AddDivider(tooltip)
	tooltip:AddLine("Market Prices", "ZoFontHeader2")

	local goldDDS = "EsoUI/Art/currency/currency_gold.dds"
	local suggestedFmt = "|cFFFFFF%d|r |t16:16:"..goldDDS.."|t"
	local stackPriceFmt = "|cFFFFFF%d|r / |cFFFFFF%d|r |t16:16:"..goldDDS.."|t"
	local singlePriceFmt = "|cFFFFFF%d|r |t16:16:"..goldDDS.."|t"

	-- Add suggested price info.
	local suggestedPrice = item.purchasePrice / item.stackCount
	AddValuePair(tooltip, "Suggested price:",
		suggestedFmt:format(
			zo_round(suggestedPrice)))
	if stackCount > 1 then
		tooltip:AddVerticalPadding(-6)
		AddValuePair(tooltip, "Stack price ("..stackCount.."):",
			suggestedFmt:format(
				zo_round(suggestedPrice*stackCount)))
	end

	-- Show min/max values.
	if self.db.showMinMax then
		local minItem = self.mathUtils:Min(matches)
		local maxItem = self.mathUtils:Max(matches)
		local minPrice = zo_round(minItem.purchasePrice / minItem.stackCount)
		local maxPrice = zo_round(maxItem.purchasePrice / maxItem.stackCount)
		local minGuild = minItem.guildName
				and zo_strjoin(nil,
					"   (", -- yes 3 spaces to align
					zo_strtrim(("%-12.12s"):format(minItem.guildName)),
					")")
				or ""
		local maxGuild = maxItem.guildName
				and zo_strjoin(nil,
					"  (", -- yes 3 spaces to align
					zo_strtrim(("%-12.12s"):format(maxItem.guildName)),
					")")
				or ""
		tooltip:AddVerticalPadding(-6)
		if stackCount > 1 then
			AddValuePair(tooltip, "Min each/stack:" .. minGuild,
				stackPriceFmt:format(
					minPrice,
					minPrice*stackCount))
			tooltip:AddVerticalPadding(-6)
			AddValuePair(tooltip, "Max each/stack:" .. maxGuild,
				stackPriceFmt:format(
					maxPrice,
					maxPrice*stackCount))
		else
			AddValuePair(tooltip, "Min:" .. minGuild,
				singlePriceFmt:format(
					minPrice))
			tooltip:AddVerticalPadding(-6)
			AddValuePair(tooltip, "Max:" .. maxGuild,
				singlePriceFmt:format(
					maxPrice))
		end
	end

	-- Show number of times seen.
	if self.db.showSeen then
		tooltip:AddLine(
				"Seen "..#matches.." times",
				"ZoFontGame",
				r, g, b,
				CENTER,
				MODIFY_TEXT_TYPE_NONE,
				TEXT_ALIGN_CENTER,
				false)
	end
end

function PriceTracker:OnHideTooltip(tooltip)
	self.selectedItem[tooltip] = nil
	self.clickedItem = nil
end

function PriceTracker:OnScanPrices()
	-- Scan already in progress.
	if self.isSearching then
		return
	end

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
			if self.db.isPlaySound then
				PlaySound(self.db.playSound)
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

	self.db.itemList[itemId] = self.db.itemList[itemId] or {}
	self.db.itemList[itemId][level] = self.db.itemList[itemId][level] or {}

	-- Do not add items that are already in the database
	if not self.db.itemList[itemId][level][expiry] then
		local item = {
			expiry = expiry,
			name = itemName,
			quality = quality,
			stackCount = stackCount,
			purchasePrice = purchasePrice,
			guildId = self.currentGuildId or 0, --0 = kiosk
			guildName = self.currentGuildName
		}
		self.db.itemList[itemId][level][expiry] = item
	end
end

function PriceTracker:CleanItemList(days)
	days = tonumber(days) or 30
	local timestamp = GetTimeStamp() - 86400 * (days - 30)
	for k, v in pairs(self.db.itemList) do
		for level, item in pairs(v) do
			for itemK, itemV in pairs(item) do
				if itemV.expiry < timestamp then
					item[itemK] = nil
				end
			end
			if next(item) == nil then v[level] = nil end
		end
		if next(v) == nil then self.db.itemList[k] = nil end
	end
end

function PriceTracker:GetMatches(itemId, itemLevel, quality)
	if not self.db.itemList or not self.db.itemList[itemId] then
		return nil
	end

	local limitToGuild = self.db.limitToGuild or 1

	local matches = {}
	for level, items in pairs(self.db.itemList[itemId]) do
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
	if self.db.ignoreFewItems then minSeen = 2 end
	if #matches <= minSeen then return nil end
	return matches
end

function PriceTracker:SuggestPrice(matches)
	if self.db.algorithm == self.algorithmTable[1] then
		return self.mathUtils:Average(matches)
	elseif self.db.algorithm == self.algorithmTable[2] then
		return self.mathUtils:Median(matches)
	elseif self.db.algorithm == self.algorithmTable[3] then
		return self.mathUtils:Mode(matches)
	elseif self.db.algorithm == self.algorithmTable[4] then
		return self.mathUtils:WeightedAverage(matches)
	else
		d("Error deciding how to calculate suggested price")
		return nil
	end
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

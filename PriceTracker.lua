-- ------------- --
-- Price Tracker --
-- ------------- --

PriceTracker = {
  name = "PriceTracker",
  title = "Price Tracker",
  author = "@uladz & @rvca18, Garkin, Barvazon",
  version = "2.7.1",
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
    EVENT_TRADING_HOUSE_RESPONSE_RECEIVED,
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

  -- Automatically disable [Scan Prices] button when user performs search.
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
		showSeen = false,
		showWasntSeen = false,
		showMath = false,
		ignoreFilters = false,
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

	-- Do some housekeeping and remove inparsable/invalid items from database.
	self:Housekeeping()

	-- Create Pricing Scan Notification Area
	self.scanLabel = PriceTrackerNotifier
	self.scanLabel:SetParent(ZO_TradingHouseBrowseItemsLeftPane)
	self.scanLabel:SetWidth(ZO_TradingHouseBrowseItemsLeftPane:GetWidth())

	-- Create Price Tracker buttons in the trading house window. Note that second
	-- button [Stop Scan] is initially hidden.
	self.scanButton = PriceTrackerControlButton
	self.scanButton:SetParent(ZO_TradingHouseBrowseItemsLeftPane)
	self.scanButton:SetWidth(ZO_TradingHouseBrowseItemsLeftPane:GetWidth())
	self.stopButton = PriceTrackerStopButton
	self.stopButton:SetParent(ZO_TradingHouseBrowseItemsLeftPane)
	self.stopButton:SetWidth(ZO_TradingHouseBrowseItemsLeftPane:GetWidth())

	-- Create the addon setting menu.
	self.menu:InitAddonMenu()  
end

-- Handle /slash commands.
function PriceTracker:CommandHandler(text)
	text = text:lower()

	-- User options.
	if #text == 0 or text == "help" then
		self:ShowHelp()
		return
	end
	if text == "setup" then
		self.menu:OpenSettings()
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
	if text == "stats" then
		self:ShowStats()
		return
	end

	-- Hidden options.
	if text == "housekeeping" then
		self:Housekeeping()
		return
	end
end

-- Print help info.
function PriceTracker:ShowHelp()
	d("To scan all item prices in all guild stores, click the [Scan Prices] button in the guild store window. You can also scan prices of other guild store while at a vendor. Press [Stop Scan] if you want to abort scan.")
	d(" ")
	d("Other commands: ")
	d("/pt help - Show this help.")
	d("/pt clean <days> - Remove prices older then <days> (30 days if not specified).")
	d("/pt reset - Remove all stored price values.")
	d("/pt setup - Open the addon settings menu.")
end

-- Prints out database statistics.
function PriceTracker:ShowStats()
	local itemsCnt = 0
	local uniqueCnt = 0
	local recordsCnt = 0
	local oldestTime = 2147483647
	local newestTime = 0
	for k, v in pairs(self.db.itemList) do
		itemsCnt = itemsCnt + 1
		for level, item in pairs(v) do
			uniqueCnt = uniqueCnt + 1
			for itemK, itemV in pairs(item) do
				recordsCnt = recordsCnt + 1
				oldestTime = zo_min(oldestTime, itemV.expiry)
				newestTime = zo_max(newestTime, itemV.expiry)
			end
		end
	end
	oldestTime = zo_round((GetTimeStamp() + 30*86400 - oldestTime)/86400)
	newestTime = zo_round((GetTimeStamp() + 30*86400 - newestTime)/86400)
	d("Price Tracker statistics:")
	d("- Number of known items = "..itemsCnt)
	d("- Number of unique items = "..uniqueCnt)
	d("- Number of price records = "..recordsCnt)
	d("- Oldest time stamp = "..oldestTime.." day(s) ago")
	d("- Newest time stamp = "..newestTime.." day(s) ago")
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

local function Collect(tooltip, object)
	if not tooltip.pt_objects then
		tooltip.pt_objects = {}
	end
	table.insert(tooltip.pt_objects, object)
end

local function AddDivider(tooltip)
	if not tooltip.pt_dividerPool then
		tooltip.pt_dividerPool = ZO_ControlPool:New(
			"ZO_BaseTooltipDivider",
			tooltip,
			"PT_Divider")
	end
	local div = tooltip.pt_dividerPool:AcquireObject()
	tooltip:AddControl(div)
	div:SetAnchor(CENTER)
	div:SetHidden(false)
	Collect(tooltip, div)
	tooltip:AddVerticalPadding(-10)
end

local function AddLine(tooltip, text, font, align)
	if not tooltip.pt_labelPool then
		tooltip.pt_labelPool = ZO_ControlPool:New(
			"ZO_TooltipLabel",
			tooltip,
			"PT_Label")
	end
	if not font then
		font = "ZoFontGame"
	end
	if not align then
		align = TEXT_ALIGN_CENTER
	end
	local label = tooltip.pt_labelPool:AcquireObject()
	tooltip:AddControl(label)
	label:SetAnchor(CENTER)
	label:SetWidth(tooltip:GetWidth())
	label:SetHorizontalAlignment(align)
	label:SetFont(font)
	label:SetText(text)
	label:SetHidden(false)
	Collect(tooltip, label)
	if text == "" then
		label:SetHeight(0)
	elseif align ~= TEXT_ALIGN_LEFT then
		tooltip:AddVerticalPadding(-10)
	end
end

local function AddPadding(tooltip, height)
	if not tooltip.pt_labelPool then
		tooltip.pt_labelPool = ZO_ControlPool:New(
			"ZO_TooltipLabel",
			tooltip,
			"PT_Label")
	end
	local pad = tooltip.pt_labelPool:AcquireObject()
	tooltip:AddControl(pad)
	pad:SetAnchor(CENTER)
	pad:SetWidth(tooltip:GetWidth())
	pad:SetHeight(height+10)
	pad:SetText("")
	pad:SetHidden(false)
	Collect(tooltip, pad)
	tooltip:AddVerticalPadding(-10)
end

local function AddLine2(tooltip, leftText, rightText)
	AddLine(tooltip, leftText, "ZoFontGame", TEXT_ALIGN_LEFT)
	tooltip:AddVerticalPadding(-32)
	AddLine(tooltip, rightText, "ZoFontGame", TEXT_ALIGN_RIGHT)
end

local function ReleaseAllObjects(tooltip)
	if tooltip.pt_dividerPool then
		tooltip.pt_dividerPool:ReleaseAllObjects()
	end
	if tooltip.pt_labelPool then
		tooltip.pt_labelPool:ReleaseAllObjects()
	end
	tooltip.pt_objects = nil
	tooltip.pt_init = nil
end

local function HideAllObjects(tooltip)
	if not tooltip.pt_objects then
		return
	end
	for k, v in pairs(tooltip.pt_objects) do
		v:SetHidden(true)
	end
end

local function ShowAllObjects(tooltip)
	if not tooltip.pt_objects then
		return
	end
	for _, object in pairs(tooltip.pt_objects) do
		object:SetHidden(false)
	end
end

-- Called when a tooltip is created or when any condition has changed, like
-- key was pressed or mouse moved. Anything that can change what's displayed
-- in the tooltip.
function PriceTracker:OnUpdateTooltip(item, tooltip)
	if not tooltip then
    tooltip = ItemTooltip
	end
	if not item
			or not item.dataEntry
			or not item.dataEntry.data then
		-- Tooltip has moved to another item but there is no Price Tracker info to
		-- show. Treat as hiding tooltip to avoid bug that no PT info is shown when
		-- returning back to the last item.
		self:OnHideTooltip(tooltip)
		return
	end
	if self.selectedItem[tooltip] == item then
		-- Tooltip already showing this item's Price Tracker info, do not rebuilt
		-- labels otherwise PT information will be duplicated. Only trace key modifiers
		-- to show or hide existing PT info in the tooltip.
		if self.menu:IsKeyPressed() then
			ShowAllObjects(tooltip)
		else
			HideAllObjects(tooltip)
		end
		return
	else
		-- New item selected, which means that the tooltip was reset and we need
		-- to clean up PT labels also and rebuilt PT info labels from scratch.
		self:OnHideTooltip(tooltip)
		if not self.menu:IsKeyPressed() then
			-- If the key modifier is not pressed, treat no PT info available, PT info
			-- will be added later when the key is pressed and this update function
			-- is called again.
			return
		end
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

	-- Add title.
	if matches or self.db.showWasntSeen then
		AddPadding(tooltip, 5)
		AddDivider(tooltip)
		AddPadding(tooltip, 3)
		AddLine(tooltip, "Market Prices", "ZoFontHeader2")
		AddPadding(tooltip, 3)
	end

	-- Exit if no price data available.
	if not matches then
		if self.db.showWasntSeen then
			AddLine(tooltip, "Wasn't seen is trade houses yet")
		end
		return
	end

	local goldDDS = "EsoUI/Art/currency/currency_gold.dds"
	local suggestedFmt = "|cFFFFFF%d|r |t16:16:"..goldDDS.."|t"
	local stackPriceFmt = "|cFFFFFF%d|r / |cFFFFFF%d|r |t16:16:"..goldDDS.."|t"
	local singlePriceFmt = "|cFFFFFF%d|r |t16:16:"..goldDDS.."|t"

	-- Add suggested price info.
	local suggestedPrice, priceName = self:SuggestPrice(matches)
	AddLine2(tooltip, "Suggested price ("..priceName.."):",
		suggestedFmt:format(
			zo_round(suggestedPrice)))
	if stackCount > 1 then
		AddLine2(tooltip, "Stack price ("..stackCount.."):",
			suggestedFmt:format(
				zo_round(suggestedPrice*stackCount)))
	end

	-- Show min/max values.
	if self.db.showMinMax then
		local minItem = self.mathUtils:MinItem(matches)
		local maxItem = self.mathUtils:MaxItem(matches)
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
		if stackCount > 1 then
			AddLine2(tooltip, "Min each/stack:" .. minGuild,
				stackPriceFmt:format(
					minPrice,
					minPrice*stackCount))
			AddLine2(tooltip, "Max each/stack:" .. maxGuild,
				stackPriceFmt:format(
					maxPrice,
					maxPrice*stackCount))
		else
			AddLine2(tooltip, "Min:" .. minGuild,
				singlePriceFmt:format(
					minPrice))
			AddLine2(tooltip, "Max:" .. maxGuild,
				singlePriceFmt:format(
					maxPrice))
		end
	end

	AddLine2(tooltip, "", "")
	if 	self.db.showSeen or self.db.showMath then
		AddPadding(tooltip, 15)
	end

	-- Show some advance info.
	if self.db.showSeen then
		AddLine(tooltip, "Seen "..#matches.." times")
	end
	if self.db.showMath then
		local min = self.mathUtils:Min(matches)
		local max = self.mathUtils:Max(matches)
		local range = max - min
		AddLine(tooltip, ("Price range = %.2f: [%d - %d]"):format(
			range, zo_round(min), zo_round(max)))
		local mean = self.mathUtils:Average(matches)
		local median = self.mathUtils:Median(matches)
		local mode = self.mathUtils:Mode(matches)
		AddLine(tooltip, ("Mean = %.2f, Median = %.2f, Mode = %.2f"):format(mean, median, mode))
		local stddev = self.mathUtils:StdDev(matches)
		local stddev_lower = math.max(mean - stddev, min)
		local stddev_upper = math.min(mean + stddev, max)
		local stddev_pct = (stddev_upper - stddev_lower) / range * 100
		AddLine(tooltip, ("Std. Dev. = %.2f (%.2f%%): [%d - %d]"):format(
			stddev, stddev_pct, zo_round(stddev_lower), zo_round(stddev_upper)))
		local conf95 = stddev * 1.96
		local conf95_lower = math.max(mean - conf95, min)
		local conf95_upper = math.min(mean + conf95, max)
		local conf95_pct = (conf95_upper - conf95_lower) / range * 100
		AddLine(tooltip, ("95%% Conf. = %.2f (%.2f%%): [%d - %d]"):format(
			conf95, conf95_pct, zo_round(conf95_lower), zo_round(conf95_upper)))
	end
end

-- Called when tooltip is hidden, i.e. removed. Basically this is the place
-- where you want to clean up your PT stuff.
function PriceTracker:OnHideTooltip(tooltip)
	if not self.selectedItem[tooltip] then
		-- no PT info was shown, nothing to do
		return
	end
	self.selectedItem[tooltip] = nil
	self.clickedItem = nil
	ReleaseAllObjects(tooltip)
end

-- Called when [Scan Prices] button is clicked.
function PriceTracker:OnScanPrices()
	if self.isSearching then
		-- scan is already in progress, what else?
		return
	end

	-- Reset guild store filter before scan to scan all items instead of only ones
	-- that are selected by the filters. Behavior controlled by user options.
	if self.db.ignoreFilters then
		TRADING_HOUSE:ResetAllSearchData()
	end

	-- Replace [Scan Prices] with [Stop Scan] button.
	self.scanButton:SetEnabled(false)
	self.scanButton:SetHidden(true)
	self.stopButton:SetHidden(false)

	-- Initialize scan engine.
	self.isSearching = true
	self.currentPage = 0
  self.numOfGuilds = 0

	-- Select a single guild to search based on selected settings
	if self.db.limitToGuild > 1 then
		self.currentGuildId = GetGuildId(self.db.limitToGuild - 1)
	else
		self.currentGuildId = GetSelectedTradingHouseGuildId()
	end

	self.currentGuildIndex = 1

	-- Select first guild trading house to scan.
	-- If using guild trader, self.currentGuildId is nil.
	if self.currentGuildId and self.currentGuildId > 0 and self.db.limitToGuild == 1 then
		self.numOfGuilds = GetNumTradingHouseGuilds()
		self.currentGuildId = GetGuildId(self.currentGuildIndex)
		while not CanSellOnTradingHouse(self.currentGuildId)
				and self.currentGuildIndex < self.numOfGuilds do
			self.currentGuildIndex = self.currentGuildIndex + 1
			self.currentGuildId = GetGuildId(self.currentGuildIndex)
		end
	end

  SelectTradingHouseGuildId(self.currentGuildId)

	-- Execute background price scan.
	zo_callLater(
		function()
			if self.isSearching then
        self.scanLabel:SetText("|cf79f07Scanning|r: Page 1")
				ExecuteTradingHouseSearch(0, TRADING_HOUSE_SORT_SALE_PRICE, true)
			end
		end,
		GetTradingHouseCooldownRemaining()
	)
end

-- Called when [Stop Scan] button is clicked.
function PriceTracker:OnStopScan()
	self.isSearching = false
	self.stopButton:SetHidden(true)
	self.scanButton:SetHidden(false)
end

-- Called when PC open a trading house window (bank or merchant).
function PriceTracker:OnTradingHouseOpened(eventCode)
	self.isSearching = false
  self.scanLabel:SetText(" ")
	self.scanButton:SetEnabled(true)
	self.stopButton:SetHidden(true)
	self.scanButton:SetHidden(false)
end

-- Called when PC closes a trading house window (bank or merchant).
function PriceTracker:OnTradingHouseClosed(eventCode)
	self.isSearching = false
	self.stopButton:SetHidden(true)
	self.scanButton:SetHidden(false)
end

function PriceTracker:OnSearchResultsReceived(eventId, tradeResponse, result)
	if tradeResponse ~= 14 then return end
	if not self.isSearching then return end

	self.currentGuildId = select(1, GetCurrentTradingHouseGuildDetails())
	self.currentGuildName = select(2, GetCurrentTradingHouseGuildDetails())
	
	local numItemsOnPage = select(1, GetTradingHouseSearchResultsInfo())
	local currentPage = select(2, GetTradingHouseSearchResultsInfo())
	local hasMorePages = select(3, GetTradingHouseSearchResultsInfo())

	self.currentPage = currentPage
  PlaySound(SOUNDS.BOOK_PAGE_TURN)
  self.scanLabel:SetText("|cf79f07Scanning|r: Page " .. currentPage + 1)

	for i = 1, numItemsOnPage do
		self:AddItem(i)
	end

	if hasMorePages then
		zo_callLater(function()
				if self.isSearching then
					ExecuteTradingHouseSearch(currentPage + 1, TRADING_HOUSE_SORT_SALE_PRICE, true)
				end
			end, GetTradingHouseCooldownRemaining())
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
							end, GetTradingHouseCooldownRemaining())
					end
				end, GetTradingHouseCooldownRemaining())

		else
			self:OnTradingHouseClosed()
			
			-- Execute a bogus search to clear the gui's search results visual bug
			zo_callLater(function()
				self.scanLabel:SetText("|c24ed45Finished Scanning!|r")
				if self.db.isPlaySound then
					PlaySound(self.db.playSound)
				end
				ExecuteTradingHouseSearch(99999999, TRADING_HOUSE_SORT_SALE_PRICE, true)
			end, GetTradingHouseCooldownRemaining())      
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

-- Calculates suggested market price.
function PriceTracker:SuggestPrice(matches)
	if self.db.algorithm == self.algorithmTable[1] then
		return self.mathUtils:Average(matches), "mean"
	elseif self.db.algorithm == self.algorithmTable[2] then
		return self.mathUtils:Median(matches), "median"
	elseif self.db.algorithm == self.algorithmTable[3] then
		return self.mathUtils:Mode(matches), "mode"
	elseif self.db.algorithm == self.algorithmTable[4] then
		return self.mathUtils:WeightedAverage(matches), "weight"
	end
	assert(false, "bug")
	return nil
end

function PriceTracker:GetItemLink(item)
	if not item or not item.GetParent then return nil end

	local parent = item:GetParent()
	if not parent then return nil end
	local parentName = parent:GetName()

	if parentName == "ZO_QuestItemsListContents" then
		return nil
	end
	if parentName == "ZO_StoreWindowListContents" then
		return GetStoreItemLink(item.dataEntry.data.slotIndex, LINK_STYLE_DEFAULT)
	end
	if parentName == "ZO_TradingHouseBrowseItemsRightPaneSearchResultsContents" then
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

-- Returns item level. After level
function PriceTracker:GetItemLevel(itemLink)
	local level = GetItemLinkRequiredLevel(itemLink)
	if level == 50 then
		level = level + GetItemLinkRequiredVeteranRank(itemLink)
	end
	return level
end

EVENT_MANAGER:RegisterForEvent("PriceTrackerLoaded",
	EVENT_ADD_ON_LOADED,
	function(...) PriceTracker:OnLoad(...) end
)

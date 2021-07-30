if not PriceTracker then return end

local PT = PriceTracker
local PriceTrackerMenu = {}
PT.menu = PriceTrackerMenu

PriceTrackerMenu.keyTable = {
	"None",
	"Shift",
	"Control",
	"Alt",
	"Command",
}

PriceTrackerMenu.soundTable = {
	"Display_Announcement",
	"LevelUp",
	"Justice_NoLongerKOS",
	"BG_CA_AreaCaptured_OtherTeam",
}

function PriceTrackerMenu:IsKeyPressed()
	return PT.db.keyPress == self.keyTable[1] or
			(PT.db.keyPress == self.keyTable[2] and IsShiftKeyDown()) or
			(PT.db.keyPress == self.keyTable[3] and IsControlKeyDown()) or
			(PT.db.keyPress == self.keyTable[4] and IsAltKeyDown()) or
			(PT.db.keyPress == self.keyTable[5] and IsCommandKeyDown())
end

function PriceTrackerMenu:GetGuildList()
	local guildList = {}
	guildList[1] = "All Guilds"
	for i = 1, GetNumGuilds() do
		guildList[i + 1] = GetGuildName(GetGuildId(i))
	end
	return guildList
end

function PriceTrackerMenu:SetLimitToGuild(guildName)
	local guildList = self:GetGuildList()
	for i, name in pairs(guildList) do
		if name == guildName then
			PT.db.limitToGuild = i
			return
		end
	end
	-- Guild not found.  Default to 'All Guilds'
	PT.db.limitToGuild = 1
end

function PriceTrackerMenu:setCompletionSound(soundName)
  for k, v in pairs(SOUNDS) do
    if SOUNDS[k] == soundName then
      PlaySound(SOUNDS[k])
      PriceTracker.db.playSound = SOUNDS[k]
      return
    end
  end
end

-- Opens addon options menu.
function PriceTrackerMenu:OpenSettings()
	local LAM2 = LibAddonMenu2
	LAM2:OpenToPanel(self.panel)
end

function PriceTrackerMenu:InitAddonMenu()
	-- Addon LAM2 config panel
	local panelData = {
		type = "panel",
		name = PT.title,
		displayName = PT.colors.title .. "Price Tacker|r",
		author = PT.author,
		version = PT.version,
		registerForRefresh = true
	}

	-- Addon LAM2 options.
	local optionsData = {
		{
			type = "dropdown",
			name = "Suggested Price Algorithm",
			choices = PT.algorithmTable,
			getFunc = function() return PT.db.algorithm or PT.algorithmTable[1] end,
			setFunc = function(value) PT.db.algorithm = value end,
		},
		{
			type = "description",
			title = PT.colors.instructional .. "Average" .. PT.colors.default,
			text = "The average (mean) price of all items seen in guild trading houses. This is the most commonly used statistical estimation of the market price, but may be affected by extreme outliers."
		},
		{
			type = "description",
			title = PT.colors.instructional .. "Median" .. PT.colors.default,
			text = "The price value for which half of the items cost more and half cost less. This statistics may provide a more robust suggested price estimate in volatile market conditions."
		},
		{
			type = "description",
			title = PT.colors.instructional .. "Most Frequently Used (also known as Mode)" .. PT.colors.default,
			text = "The most common item price value observed. This estimate is the least affected by outlining price values but less effective for items with low number of sales."
		},
		{
			type = "description",
			title = PT.colors.instructional .. "Weighted Average" .. PT.colors.default,
			text = "The average price of all items, with date taken into account. The latest data gets a wighting of X, where X is the number of days the data covers, thus making the newest data worth more. This statistics takes into account trends in prices."
		},
		{
			type = "header",
			name = "Price Suggestion Options",
			width = "full",
		},
		{
			type = "checkbox",
			name = "Show Min / Max Prices",
			tooltip = "Show minimum and maximum sell values.",
			getFunc = function() return PT.db.showMinMax end,
			setFunc = function(value) PT.db.showMinMax = value end,
		},
		{
			type = "checkbox",
			name = "Show 'Wasn't seen'",
			tooltip = "Show tooltip info even if the item was not seen yet in guild stores and no price data is available.",
			getFunc = function() return PT.db.showWasntSeen end,
			setFunc = function(value) PT.db.showWasntSeen = value end,
		},
		{
			type = "checkbox",
			name = "Show 'Seen'",
			tooltip = "Show how many times an item was seen in the guild stores so far.",
			getFunc = function() return PT.db.showSeen end,
			setFunc = function(value) PT.db.showSeen = value end,
		},
		{
			type = "checkbox",
			name = "Show Advanced Math",
			tooltip = "Show various additional advanced statistics like stdder, confidence, etc.",
			getFunc = function() return PT.db.showMath end,
			setFunc = function(value) PT.db.showMath = value end,
		},
		{
			type = "dropdown",
			name = "Show only if key is pressed",
			tooltip = "Show pricing on tooltip only if one of the following keys is pressed. This is useful if you have too many addons modifying your tooltips.",
			choices = self.keyTable,
			getFunc = function() return PT.db.keyPress or self.keyTable[1] end,
			setFunc = function(value) PT.db.keyPress = value end,
			default = self.keyTable[1]
		},
		{
			type = "dropdown",
			name = "Limit results to a specific guild",
			tooltip = "Check pricing data from all guilds, or a specific one.",
			choices = self:GetGuildList(),
			getFunc = function() return self:GetGuildList() [PT.db.limitToGuild or 1] end,
			setFunc = function(value) self:SetLimitToGuild(value) end,
			default = self:GetGuildList()[1]
		},
		{
			type = "checkbox",
			name = "Ignore infrequent items",
			tooltip = "Ignore items that were seen only once or twice, as their price statistics may be inaccurate.",
			getFunc = function() return PT.db.ignoreFewItems end,
			setFunc = function(value) PT.db.ignoreFewItems = value end,
			default = false
		},
		{
			type = "header",
			name = "Price Scan Options",
			width = "full",
		},
		{
			type = "slider",
			name = "Keep item prices for (days):",
			tooltip = "Keep item prices for a selected number of days. Older data will be automatically removed.",
			min = 7,
			max = 120,
			getFunc = function() return PT.db.historyDays end,
			setFunc = function(value) PT.db.historyDays = value end,
			default = 90
		},
		{
			type = "checkbox",
			name = "Ignore guild store filters",
			tooltip = "Ignore currently set filters in a guild store and perform a complete scan of all items. Otherwise will scan only a subset of items selected by store filters.",
			getFunc = function() return PT.db.ignoreFilters end,
			setFunc = function(value) PT.db.ignoreFilters = value end,
			default = false
		},
		{
			type = "checkbox",
			name = "Scan complete notification",
			tooltip = "Play an audio notification when item scan is complete.",
			getFunc = function() return PT.db.isPlaySound end,
			setFunc = function(value) PT.db.isPlaySound = value end,
			default = false
		},
		{
			type = "dropdown",
			name = "Sound type",
			tooltip = "Select which sound to play upon scan completion.",
			choices = self.soundTable,
			getFunc = function() return PT.db.playSound or self.soundTable[1] end,
			setFunc = function(...) self:setCompletionSound(...) end,
			disabled = function() return not PT.db.isPlaySound end,
			default = self.soundTable[1]
		},
	}

	local LAM2 = LibAddonMenu2
	self.panel = LAM2:RegisterAddonPanel("PriceTrackerOptions", panelData)
	LAM2:RegisterOptionControls("PriceTrackerOptions", optionsData)
end

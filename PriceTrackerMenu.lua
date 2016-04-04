if not PriceTracker then return end

local PriceTracker = PriceTracker
local PriceTrackerMenu = {}
PriceTracker.menu = PriceTrackerMenu

PriceTrackerMenu.algorithmTable = {
	"Average",
	"Median",
	"Most Frequently Used",
	"Weighted Average",
}

PriceTrackerMenu.keyTable = {
	"None",
	"Shift",
	"Control",
	"Alt",
	"Command",
}

PriceTrackerMenu.soundTable = {
	SOUNDS.BOOK_ACQUIRED,
	SOUNDS.ACHIEVEMENT_AWARDED,
	SOUNDS.FRIEND_REQUEST_ACCEPTED,
	SOUNDS.GUILD_SELF_JOINED,
}

function PriceTrackerMenu:InitAddonMenu()
	local panelData = {
		type = "panel",
		name = "Price Tracker",
		displayName = PriceTracker.colors.title .. "Price Tacker|r",
		author = "Barvazon (updated by Garkin & @uladz)",
		version = "2.6.3",
		slashCommand = "/ptsetup",
		registerForRefresh = true
	}

	local optionsData = {
		{
			type = "dropdown",
			name = "Select price algorithm",
			choices = self.algorithmTable,
			getFunc = function() return PriceTracker.settings.algorithm or self.algorithmTable[1] end,
			setFunc = function(algorithm) PriceTracker.settings.algorithm = algorithm end,
			default = self.algorithmTable[1]
		},
		{
			type = "description",
			title = PriceTracker.colors.instructional .. "Average" .. PriceTracker.colors.default,
			text = "The average price of all items."
		},
		{
			type = "description",
			title = PriceTracker.colors.instructional .. "Median" .. PriceTracker.colors.default,
			text = "The price value for which half of the items cost more and half cost less."
		},
		{
			type = "description",
			title = PriceTracker.colors.instructional .. "Most Frequently Used (also known as Mode)" .. PriceTracker.colors.default,
			text = "The most common price value."
		},
		{
			type = "description",
			title = PriceTracker.colors.instructional .. "Weighted Average" .. PriceTracker.colors.default,
			text = "The average price of all items, with date taken into account. The latest data gets a wighting of X, where X is the number of days the data covers, thus making newest data worth more."
		},
		{
			type = "checkbox",
			name = "Show Min / Max Prices",
			tooltip = "Show minimum and maximum sell values",
			getFunc = function() return PriceTracker.settings.showMinMax end,
			setFunc = function(check) PriceTracker.settings.showMinMax = check end,
			default = true
		},
		{
			type = "checkbox",
			name = "Show 'Seen'",
			tooltip = "Show how many times an item was seen in the guild stores",
			getFunc = function() return PriceTracker.settings.showSeen end,
			setFunc = function(check) PriceTracker.settings.showSeen = check end,
			default = true
		},
		{
			type = "dropdown",
			name = "Show only if key is pressed",
			tooltip = "Show pricing on tooltip only if one of the following keys is pressed.  This is useful if you have too many addons modifying your tooltips.",
			choices = self.keyTable,
			getFunc = function() return PriceTracker.settings.keyPress or self.keyTable[1] end,
			setFunc = function(key) PriceTracker.settings.keyPress = key end,
			default = self.keyTable[1]
		},
		{
			type = "dropdown",
			name = "Limit results to a specific guild",
			tooltip = "Check pricing data from all guild, or a specific one",
			choices = self:GetGuildList(),
			getFunc = function() return self:GetGuildList()[PriceTracker.settings.limitToGuild or 1] end,
			setFunc = function(...) self:setLimitToGuild(...) end,
			default = self:GetGuildList()[1]
		},
		{
			type = "checkbox",
			name = "Ignore infrequent items",
			tooltip = "Ignore items that were seen only once or twice, as their price statistics may be inaccurate",
			getFunc = function() return PriceTracker.settings.ignoreFewItems end,
			setFunc = function(check) PriceTracker.settings.ignoreFewItems = check end,
			default = false
		},
		{
			type = "slider",
			name = "Keep item prices for (days):",
			tooltip = "Keep item prices for selected number of days. Older data will be automatically removed.",
			min = 7,
			max = 120,
			getFunc = function() return PriceTracker.settings.historyDays end,
			setFunc = function(days) PriceTracker.settings.historyDays = days end,
			default = 90
		},
		{
			type = "checkbox",
			name = "Audible notification",
			tooltip = "Play an audio notification when item scan is complete",
			getFunc = function() return PriceTracker.settings.isPlaySound end,
			setFunc = function(check) PriceTracker.settings.isPlaySound = check end,
			default = false
		},
		{
			type = "dropdown",
			name = "Sound type",
			tooltip = "Select which sound to play upon scan completion",
			choices = self.soundTable,
			getFunc = function() return PriceTracker.settings.playSound or self.soundTable[1] end,
			setFunc = function(value) PriceTracker.settings.playSound = value end,
			disabled = function() return not PriceTracker.settings.isPlaySound end,
			default = self.soundTable[1]
		},
	}

	local LAM2 = LibStub:GetLibrary("LibAddonMenu-2.0")
	LAM2:RegisterAddonPanel("PriceTrackerOptions", panelData)
	LAM2:RegisterOptionControls("PriceTrackerOptions", optionsData)
end

function PriceTrackerMenu:IsKeyPressed()
	return PriceTracker.settings.keyPress == self.keyTable[1] or
		(PriceTracker.settings.keyPress == self.keyTable[2] and IsShiftKeyDown()) or
		(PriceTracker.settings.keyPress == self.keyTable[3] and IsControlKeyDown()) or
		(PriceTracker.settings.keyPress == self.keyTable[4] and IsAltKeyDown()) or
		(PriceTracker.settings.keyPress == self.keyTable[5] and IsCommandKeyDown())
end

function PriceTrackerMenu:GetGuildList()
	local guildList = {}
	guildList[1] = "All Guilds"
	for i = 1, GetNumGuilds() do
		guildList[i + 1] = GetGuildName(GetGuildId(i))
	end
	return guildList
end

function PriceTrackerMenu:setLimitToGuild(guildName)
	local guildList = self:GetGuildList()
	for i, name in pairs(guildList) do
		if name == guildName then
			PriceTracker.settings.limitToGuild = i
			return
		end
	end
	-- Guild not found.  Default to 'All Guilds'
	PriceTracker.settings.limitToGuild = 1
end


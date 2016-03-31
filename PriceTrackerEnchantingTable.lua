if not PriceTracker then
	return
end

local PriceTracker = PriceTracker
local PriceTrackerEnchantingTable = {}
PriceTracker.enchantingTable = PriceTrackerEnchantingTable

PriceTrackerEnchantingTable.enchanting = ENCHANTING
PriceTrackerEnchantingTable.enchantingRunes = {
	potency = {
		bagId = nil,
		itemIndex = nil
	},
	essence = {
		bagId = nil,
		itemIndex = nil
	},
	aspect = {
		bagId = nil,
		itemIndex = nil
	}
}

function PriceTrackerEnchantingTable:OnLoad(eventCode, addOnName)
	if(addOnName ~= "PriceTracker") then return end

	ZO_PreHookHandler(self.enchanting.runeSlots[1].control, "OnUpdate", function() self:OnUpdateEnchantingRune(self.enchanting.runeSlots[1], "aspect") end)
	ZO_PreHookHandler(self.enchanting.runeSlots[2].control, "OnUpdate", function() self:OnUpdateEnchantingRune(self.enchanting.runeSlots[2], "essence") end)
	ZO_PreHookHandler(self.enchanting.runeSlots[3].control, "OnUpdate", function() self:OnUpdateEnchantingRune(self.enchanting.runeSlots[3], "potency") end)
	ZO_PreHookHandler(self.enchanting.resultTooltip, "OnHide", function() PriceTracker:OnHideTooltip(self.enchanting.resultTooltip) end)
end

function PriceTrackerEnchantingTable:OnUpdateEnchantingRune(rune, runeType)
	if rune.bagId == self.enchantingRunes[runeType].bagId and rune.slotIndex == self.enchantingRunes[runeType].itemIndex then return end

	self.enchantingRunes[runeType].bagId = rune.bagId
	self.enchantingRunes[runeType].itemIndex = rune.slotIndex
	self:UpdateEnchantingTooltip()
end

function PriceTrackerEnchantingTable:UpdateEnchantingTooltip()
	if not self.enchantingRunes.potency.bagId or not self.enchantingRunes.potency.itemIndex or 
		not self.enchantingRunes.essence.bagId or not self.enchantingRunes.essence.itemIndex or 
		not self.enchantingRunes.aspect.bagId or not self.enchantingRunes.aspect.itemIndex then return end
	local name, icon, stack, sellPrice, meetsUsageRequirement, quality = 
		GetEnchantingResultingItemInfo(self.enchantingRunes.potency.bagId, self.enchantingRunes.potency.itemIndex, 
			self.enchantingRunes.essence.bagId, self.enchantingRunes.essence.itemIndex, 
			self.enchantingRunes.aspect.bagId, self.enchantingRunes.aspect.itemIndex)
	local _, _, _, itemId, level =
		ZO_LinkHandler_ParseLink(GetEnchantingResultingItemLink(self.enchantingRunes.potency.bagId, self.enchantingRunes.potency.itemIndex, 
			self.enchantingRunes.essence.bagId, self.enchantingRunes.essence.itemIndex, 
			self.enchantingRunes.aspect.bagId, self.enchantingRunes.aspect.itemIndex))
	local item = {
		dataEntry = {
			data = {
				name = name,
				stackCount = 1,
				purchasePrice = sellPrice,
				itemId = itemId,
				level = level,
				quality = quality,
			}
		}
	}
	if(meetsUsageRequirement) then
		PriceTracker:OnUpdateTooltip(item, self.enchanting.resultTooltip)
	end
end


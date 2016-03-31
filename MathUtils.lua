if not PriceTracker then
	return
end

local MathUtils = {}
PriceTracker.mathUtils = MathUtils

function MathUtils:GetSortedPriceTable(itemTable)
	table.sort(itemTable, function(a, b) return a.purchasePrice / a.stackCount < b.purchasePrice / b.stackCount end)
	return itemTable
end

function MathUtils:Average(itemTable)
	local sum = 0
	for i = 1, #itemTable do
		sum = sum + itemTable[i].purchasePrice / itemTable[i].stackCount
	end
	local item = {
		purchasePrice = zo_round(sum / #itemTable),
		stackCount = 1
	}
	return item
end

--implementation of Khaibit's weighted average used in Shopkeeper
function MathUtils:WeightedAverage(itemTable)
	local oldestTime = 2147483647
	local newestTime = 0
	for _, item in pairs(itemTable) do
		oldestTime = zo_min(oldestTime, item.expiry)
		newestTime = zo_max(newestTime, item.expiry)
	end

	local timeInterval = newestTime - oldestTime
	local avgPrice = 0
	--If all data covers less than a day, we'll just do a plain average, nothing to weight
	if timeInterval < 86400 then
		for _, item in pairs(itemTable) do
			avgPrice = avgPrice + item.purchasePrice / item.stackCount
		end
		avgPrice = avgPrice / #itemTable
	-- For a weighted average, the latest data gets a weighting of X, where X is the number of
	-- days the data covers, thus making newest data worth more.
	else
		--item.expiry is always time listed + 30 days, thus my timestamp will be now + 30 days
		local timestamp = GetTimeStamp() + 30 * 86400
		local dayInterval = zo_floor( (timestamp - oldestTime) / 86400 ) + 1
		local weightedDiv = 0
		for _, item in pairs(itemTable) do
			local weightValue = dayInterval - zo_floor( (timestamp - item.expiry) / 86400 )
			weightedDiv = weightedDiv + weightValue
			avgPrice = avgPrice + item.purchasePrice / item.stackCount * weightValue
		end
		avgPrice = avgPrice / weightedDiv 
	end

	local item = {
		purchasePrice = zo_round(avgPrice),
		stackCount = 1,
	}
	return item
end

function MathUtils:Median(itemTable)
	local itemTable = self:GetSortedPriceTable(itemTable)
	local index = zo_round(#itemTable / 2)
	if (index * 2 == #itemTable) then
		local item = {
			purchasePrice = zo_round(itemTable[index].purchasePrice / itemTable[index].stackCount + itemTable[index + 1].purchasePrice / itemTable[index + 1].stackCount),
			stackCount = 2
		}
		return item
	else
		return itemTable[index]
	end
end

function MathUtils:Mode(itemTable)
	local itemTable = self:GetSortedPriceTable(itemTable)
	local number = itemTable[1]
	local mode = number
	local count = 1
	local countMode = 1

	for i = 2, #itemTable do
		if zo_floatsAreEqual(itemTable[i].purchasePrice / itemTable[i].stackCount, number.purchasePrice / number.stackCount, 0.1) then
			count = count + 1
		else
			if count > countMode then
				countMode = count
				mode = number
			end
			count = 1
			number = itemTable[i]
		end
	end
	return mode
end

function MathUtils:Max(itemTable)
	local price = itemTable[1].purchasePrice / itemTable[1].stackCount
	local item = itemTable[1]
	for i = 2, #itemTable do
		local newPrice = itemTable[i].purchasePrice / itemTable[i].stackCount
		if newPrice > price then
			price = newPrice
			item = itemTable[i]
		end
	end
	return item
end

function MathUtils:Min(itemTable)
	local price = itemTable[1].purchasePrice / itemTable[1].stackCount
	local item = itemTable[1]
	for i = 2, #itemTable do
		local newPrice = itemTable[i].purchasePrice / itemTable[i].stackCount
		if newPrice < price then
			price = newPrice
			item = itemTable[i]
		end
	end
	return item
end

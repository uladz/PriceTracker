if not PriceTracker then
	return
end

local MathUtils = {}
PriceTracker.mathUtils = MathUtils

function MathUtils:GetSortedPriceTable(itemTable)
	table.sort(itemTable,
		function(a, b)
			return a.purchasePrice/a.stackCount < b.purchasePrice/b.stackCount
		end)
	return itemTable
end

function MathUtils:Average(itemTable)
	local sum = 0
	for i = 1, #itemTable do
		local item = itemTable[i]
		sum = sum + item.purchasePrice/item.stackCount
	end
	return sum / #itemTable
end

function MathUtils:Mean(itemTable)
	local sum = 0
	local cnt = 0
	for i = 1, #itemTable do
		local item = itemTable[i]
		sum = sum + item.purchasePrice
		cnt = cnt + item.stackCount
	end
	return sum / cnt
end

-- implementation of Khaibit's weighted average used in Shopkeeper
function MathUtils:WeightedAverage(itemTable)
	-- Calculate history time range.
	local oldestTime = 2147483647
	local newestTime = 0
	for _, item in pairs(itemTable) do
		oldestTime = zo_min(oldestTime, item.expiry)
		newestTime = zo_max(newestTime, item.expiry)
	end

	local timeInterval = newestTime - oldestTime
	local day = 86400 -- in seconds
	local avgPrice = 0

	if timeInterval < day then
		-- If all data covers less than a day, we'll just do a plain average,
		-- nothing to weight really.
		avgPrice = self:Mean(itemTable)
	else
		-- For a weighted average, the latest data gets a weighting of X, where X is
		-- the number of days the data covers, thus making newest data worth more.
		local timestamp = GetTimeStamp() + 30*day
		local dayInterval = zo_floor((timestamp - oldestTime)/day) + 1
		local weightedDiv = 0
		for _, item in pairs(itemTable) do
			local weightValue = dayInterval - zo_floor((timestamp - item.expiry)/day)
			weightedDiv = weightedDiv + weightValue
			avgPrice = avgPrice + item.purchasePrice/item.stackCount * weightValue
		end
		avgPrice = avgPrice/weightedDiv
	end
	return avgPrice
end

function MathUtils:Median(itemTable)
	local itemTable = self:GetSortedPriceTable(itemTable)
	local index = zo_round(#itemTable / 2)
	if (index * 2 == #itemTable) then
		-- median is between two items
		local a = itemTable[index]
		local b = itemTable[index+1]
		return (a.purchasePrice / a.stackCount
				+ b.purchasePrice / b.stackCount) / 2
	else
		-- exact median found
		return itemTable[index].purchasePrice
	end
end

function MathUtils:Mode(itemTable)
	local itemTable = self:GetSortedPriceTable(itemTable)
	local number = itemTable[1]
	local mode = number.purchasePrice / number.stackCount
	local countMode = 1

	local count = 1
	for i = 2, #itemTable do
		local item = itemTable[i]
		local itemPrice = item.purchasePrice / item.stackCount
		if zo_floatsAreEqual(itemPrice, mode, 0.1) then
			count = count + 1
		else
			if count > countMode then
				countMode = count
				mode = itemPrice
			end
			count = 1
			number = item
		end
	end
	return mode
end

function MathUtils:MaxItem(itemTable)
	local item = itemTable[1]
	local price = item.purchasePrice / item.stackCount
	for i = 2, #itemTable do
		local newItem = itemTable[i]
		local newPrice = newItem.purchasePrice / newItem.stackCount
		if newPrice > price then
			price = newPrice
			item = newItem
		end
	end
	return item
end

function MathUtils:MinItem(itemTable)
	local item = itemTable[1]
	local price = item.purchasePrice / item.stackCount
	for i = 2, #itemTable do
		local newItem = itemTable[i]
		local newPrice = newItem.purchasePrice / newItem.stackCount
		if newPrice < price then
			price = newPrice
			item = newItem
		end
	end
	return item
end

function MathUtils:Max(itemTable)
	local item = self:MaxItem(itemTable)
	return item.purchasePrice / item.stackCount
end

function MathUtils:Min(itemTable)
	local item = self:MinItem(itemTable)
	return item.purchasePrice / item.stackCount
end

function MathUtils:Variance(itemTable)
	local mean = self:Mean(itemTable)
	local var = 0
	local cnt = 0
	for _, item in ipairs(itemTable) do
		cnt = cnt + item.stackCount
		var = var + (((item.purchasePrice/item.stackCount - mean) ^ 2) * item.stackCount)
	end
	var = var / cnt
	return var
end

function MathUtils:StdDev(itemTable)
	local var = self:Variance(itemTable)
	local dev = math.sqrt(var)
	return dev
end

function MathUtils:StdErr(itemTable)
	local dev = self:StdDev(itemTable)
	local cnt = 0
	for _, item in ipairs(itemTable) do
		cnt = cnt + item.stackCount
	end
	local err = dev / math.sqrt(cnr)
	return err
end

function MathUtils:round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

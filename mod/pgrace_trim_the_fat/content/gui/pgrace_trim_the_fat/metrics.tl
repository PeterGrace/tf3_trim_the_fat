local metrics : PgraceTrimTheFatMetrics = {}

metrics.TARGET_DEFAULT = 0.70
metrics.TARGET_SINGLE_CARGO = 0.50
metrics.BUSY_LOAD = 0.95
metrics.MIN_DATA_FRACTION = 1 / 12

function metrics.targetFor(cargoTypeCount : integer) : number
	if cargoTypeCount == 1 then
		return metrics.TARGET_SINGLE_CARGO
	end
	return metrics.TARGET_DEFAULT
end

function metrics.percent(fraction : number) : integer
	if fraction == nil then
		return nil
	end
	return math.floor(fraction * 100 + 0.5)
end

-- Integer plural rules from CLDR, for the languages TF3 ships (same as Commuter Compass rank.pluralCategory).
local function slavicCategory(count : integer, oneNeedsTensCheck : boolean) : string
	local lastDigit, lastTwo = count % 10, count % 100
	if count == 1 or (oneNeedsTensCheck and lastDigit == 1 and lastTwo ~= 11) then
		return "one"
	end
	if lastDigit >= 2 and lastDigit <= 4 and not (lastTwo >= 12 and lastTwo <= 14) then
		return "few"
	end
	return "many"
end

function metrics.pluralCategory(language : string, count : integer) : string
	local lang = (language or "en"):sub(1, 2)
	if lang == "ja" or lang == "ko" or lang == "zh" then
		return "other"
	end
	if lang == "ru" then
		return slavicCategory(count, true)
	end
	if lang == "pl" then
		return slavicCategory(count, false)
	end
	if lang == "fr" or lang == "pt" then
		return (count == 0 or count == 1) and "one" or "other"
	end
	return count == 1 and "one" or "other"
end

function metrics.averageLoad(input : PgraceTrimTheFatMetrics.LineInput) : number
	if input.vehicleCount == nil or input.vehicleCount <= 0
		or input.totalCapacity == nil or input.totalCapacity <= 0
		or input.intervalMs == nil or input.intervalMs <= 0
		or input.dataMs == nil or input.dataMs <= 0 then
		return nil
	end
	local departures = input.dataMs / input.intervalMs
	local offered = departures * (input.totalCapacity / input.vehicleCount)
	return (input.itemsTransported or 0) / offered
end

function metrics.annualise(amount : number, spanMs : number, yearMs : number) : number, boolean
	if spanMs == nil or spanMs <= 0 or spanMs >= yearMs then
		return amount, false
	end
	return amount * yearMs / spanMs, true
end

return metrics

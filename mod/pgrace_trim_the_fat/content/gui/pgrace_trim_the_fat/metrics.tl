local metrics : PgraceTrimTheFatMetrics = {}

metrics.TARGET_DEFAULT = 0.70
metrics.TARGET_SINGLE_CARGO = 0.50
metrics.BUSY_LOAD = 0.95
metrics.MIN_DATA_FRACTION = 1 / 12
metrics.STUCK_LOAD_NOW = 0.75
metrics.STUCK_AVERAGE_LOAD = 0.25

function metrics.targetFor(cargoTypeCount : integer, carriesPassengers : boolean) : number
	if cargoTypeCount == 1 and not carriesPassengers then
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
		or input.stopCount == nil or input.stopCount < 1
		or input.dataMs == nil or input.dataMs <= 0 then
		return nil
	end
	-- A round trip takes intervalMs × vehicles (the interval is the time between departures at one stop). Each
	-- vehicle completes vehicleDataMs / roundTripMs round trips in total, each running one leg per stop, and every
	-- leg offers the vehicle's capacity. Counting each vehicle's own time keeps vehicles bought recently from
	-- inflating the capacity offered over the year.
	local count = input.vehicleCount
	local vehicleDataMs = input.vehicleDataMs or input.dataMs * count
	if vehicleDataMs <= 0 then
		return nil
	end
	local roundTrips = vehicleDataMs / (input.intervalMs * count)
	local offered = roundTrips * (input.totalCapacity / count) * input.stopCount
	return (input.itemsTransported or 0) / offered
end

function metrics.annualise(amount : number, spanMs : number, yearMs : number) : number, boolean
	if spanMs == nil or spanMs <= 0 or spanMs >= yearMs then
		return amount, false
	end
	return amount * yearMs / spanMs, true
end

local HISTORY_SLICES = 12

function metrics.dataSpan(balanceBetween : function(integer, integer) : number, bought : integer, now : integer,
		yearMs : integer) : integer
	local from = math.max(now - yearMs, 0)
	if bought <= from then
		return now - from
	end
	local sliceMs = yearMs // HISTORY_SLICES
	if sliceMs <= 0 or balanceBetween(from, bought) == 0 then
		return now - bought
	end
	-- Start of the first slice (a month by default) with any money in it.
	local start = from
	while start + sliceMs < bought and balanceBetween(start, start + sliceMs) == 0 do
		start = start + sliceMs
	end
	return now - start
end

-- Guards ceil() against float noise: 8 × 0.25 ÷ 0.5 may come out as 4.000000001.
local EPSILON = 1e-9

function metrics.assess(input : PgraceTrimTheFatMetrics.LineInput) : PgraceTrimTheFatMetrics.Assessment
	local a : PgraceTrimTheFatMetrics.Assessment = {
		verdict = "Ok",
		target = metrics.targetFor(input.cargoTypeCount, input.carriesPassengers),
		trim = 0,
		notDelivering = false,
	}
	a.balancePerYear, a.annualised = metrics.annualise(input.balance or 0, input.dataMs, input.yearMs)
	local count = input.vehicleCount or 0
	if count <= 0 then
		a.verdict = "NoVehicles"
		return a
	end
	a.profitPerVehicle = a.balancePerYear / count
	a.load = metrics.averageLoad(input)
	if input.dataMs == nil or input.dataMs < input.yearMs * metrics.MIN_DATA_FRACTION then
		a.verdict = "TooNew"
		return a
	end
	-- Full right now but little carried over the window: the cargo isn't being unloaded, so fewer vehicles won't help.
	a.notDelivering = input.loadNow ~= nil and input.loadNow >= metrics.STUCK_LOAD_NOW
		and a.load ~= nil and a.load < metrics.STUCK_AVERAGE_LOAD
	if a.load ~= nil and a.load < a.target and count > 1 and not a.notDelivering then
		local keep = math.max(1, math.ceil(count * a.load / a.target - EPSILON))
		if keep < count then
			a.keep = keep
			a.trim = count - keep
		end
	end
	if a.balancePerYear < 0 then
		a.verdict = "Losing"
	elseif a.trim > 0 then
		a.verdict = "TooMany"
	elseif a.load ~= nil and a.load >= metrics.BUSY_LOAD then
		a.verdict = "Busy"
	end
	return a
end

function metrics.verdictKind(a : PgraceTrimTheFatMetrics.Assessment) : PgraceTrimTheFatMetrics.VerdictKind
	if a.verdict == "Losing" then
		if a.notDelivering then
			return "LosingStuck"
		elseif a.trim > 0 then
			return "LosingTrim"
		end
		return "Losing"
	end
	return a.verdict as PgraceTrimTheFatMetrics.VerdictKind
end

local SEVERITY : {PgraceTrimTheFatMetrics.VerdictKind : integer} = {
	Losing = 1, LosingTrim = 1, LosingStuck = 1,
	TooMany = 2, Busy = 3, TooNew = 4, NoVehicles = 5, Ok = 6,
}

function metrics.severity(kind : PgraceTrimTheFatMetrics.VerdictKind) : integer
	return SEVERITY[kind] or 6
end

function metrics.summarise(assessments : {PgraceTrimTheFatMetrics.Assessment}) : PgraceTrimTheFatMetrics.Summary
	local s : PgraceTrimTheFatMetrics.Summary = { losingCount = 0, losingPerYear = 0, tooManyCount = 0, trimTotal = 0 }
	for __, a in ipairs(assessments) do
		if a.verdict == "Losing" then
			s.losingCount = s.losingCount + 1
			s.losingPerYear = s.losingPerYear + (a.balancePerYear or 0)
		end
		if a.trim > 0 then
			s.tooManyCount = s.tooManyCount + 1
			s.trimTotal = s.trimTotal + a.trim
		end
	end
	return s
end

return metrics

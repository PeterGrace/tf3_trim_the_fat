local t = ...
local metrics = t.requireTl("gui/pgrace_trim_the_fat/metrics.tl")

t.test("constants: starting targets", function()
	t.eq(metrics.TARGET_DEFAULT, 0.70)
	t.eq(metrics.TARGET_SINGLE_CARGO, 0.50)
	t.eq(metrics.BUSY_LOAD, 0.95)
end)

t.test("targetFor: single-cargo freight vs everything else", function()
	t.eq(metrics.targetFor(1, false), 0.50, "one cargo type")
	t.eq(metrics.targetFor(1, nil), 0.50, "one cargo type, passengers unknown")
	t.eq(metrics.targetFor(1, true), 0.70, "passengers only")
	t.eq(metrics.targetFor(2, false), 0.70, "two cargo types")
	t.eq(metrics.targetFor(0, false), 0.70, "unknown")
end)

t.test("percent: rounds half up, nil stays nil", function()
	t.eq(metrics.percent(0.344), 34)
	t.eq(metrics.percent(0.346), 35)
	t.eq(metrics.percent(0), 0)
	t.eq(metrics.percent(1.2), 120)
	t.eq(metrics.percent(nil), nil)
end)

t.test("pluralCategory: CLDR integer rules", function()
	t.eq(metrics.pluralCategory("en", 1), "one")
	t.eq(metrics.pluralCategory("en", 2), "other")
	t.eq(metrics.pluralCategory("en", 0), "other")
	t.eq(metrics.pluralCategory("fr", 0), "one")
	t.eq(metrics.pluralCategory("pt_BR", 1), "one")
	t.eq(metrics.pluralCategory("pl", 1), "one")
	t.eq(metrics.pluralCategory("pl", 2), "few")
	t.eq(metrics.pluralCategory("pl", 5), "many")
	t.eq(metrics.pluralCategory("pl", 12), "many")
	t.eq(metrics.pluralCategory("pl", 22), "few")
	t.eq(metrics.pluralCategory("pl", 21), "many")
	t.eq(metrics.pluralCategory("ru", 21), "one")
	t.eq(metrics.pluralCategory("ru", 11), "many")
	t.eq(metrics.pluralCategory("ja", 1), "other")
	t.eq(metrics.pluralCategory("zh_TW", 3), "other")
	t.eq(metrics.pluralCategory(nil, 1), "one")
end)

-- A line of 8 vehicles × 100 capacity on 2 stops, a departure every 200 ms, a full year of 1200 ms of data:
-- 6 round trips × 100 per vehicle × 2 legs = 1200 capacity offered.
-- pairs() skips nil values, so an override of NIL clears the field.
local NIL = {}

local function line(overrides)
	local input = {
		vehicleCount = 8,
		balance = 400,
		itemsTransported = 408,
		totalCapacity = 800,
		intervalMs = 200,
		stopCount = 2,
		dataMs = 1200,
		yearMs = 1200,
		cargoTypeCount = 1,
	}
	for k, v in pairs(overrides or {}) do
		if v == NIL then
			v = nil
		end
		input[k] = v
	end
	return input
end

local function near(actual, expected, label)
	if actual == nil or math.abs(actual - expected) > 1e-9 then
		error(("%s: expected %s, got %s"):format(label or "near", tostring(expected), tostring(actual)), 2)
	end
end

t.test("averageLoad: carried ÷ offered", function()
	near(metrics.averageLoad(line({ itemsTransported = 600 })), 0.5)
	near(metrics.averageLoad(line()), 0.34)
end)

t.test("averageLoad: a young line is measured over its own data window", function()
	near(metrics.averageLoad(line({ dataMs = 600, itemsTransported = 300 })), 0.5)
end)

t.test("averageLoad: nil when it can't be known", function()
	t.eq(metrics.averageLoad(line({ intervalMs = 0 })), nil, "interval 0")
	t.eq(metrics.averageLoad(line({ intervalMs = NIL })), nil, "interval nil")
	t.eq(metrics.averageLoad(line({ totalCapacity = 0 })), nil, "no capacity")
	t.eq(metrics.averageLoad(line({ vehicleCount = 0 })), nil, "no vehicles")
	t.eq(metrics.averageLoad(line({ dataMs = 0 })), nil, "no data")
	t.eq(metrics.averageLoad(line({ stopCount = NIL })), nil, "stops nil")
	t.eq(metrics.averageLoad(line({ stopCount = 0 })), nil, "no stops")
end)

t.test("averageLoad: every stop is a leg that offers the vehicle's capacity", function()
	-- 6 round trips × 100 × 3 legs = 1800 offered.
	near(metrics.averageLoad(line({ stopCount = 3, itemsTransported = 900 })), 0.5)
end)

t.test("annualise: scales partial years up and flags it", function()
	local amount, scaled = metrics.annualise(100, 300, 1200)
	t.eq(amount, 400)
	t.eq(scaled, true)
	amount, scaled = metrics.annualise(100, 1200, 1200)
	t.eq(amount, 100)
	t.eq(scaled, false)
	amount, scaled = metrics.annualise(100, 5000, 1200)
	t.eq(amount, 100, "older than a year")
	t.eq(scaled, false)
	amount, scaled = metrics.annualise(-50, 0, 1200)
	t.eq(amount, -50, "no span")
	t.eq(scaled, false)
end)

t.test("assess: too many, with the trim suggestion", function()
	-- 8 × 34% ÷ 50% = 5.44 → keep 6, trim 2.
	local a = metrics.assess(line())
	t.eq(a.verdict, "TooMany")
	t.eq(a.keep, 6)
	t.eq(a.trim, 2)
	t.eq(metrics.percent(a.load), 34)
	t.eq(a.target, 0.50)
	t.eq(a.profitPerVehicle, 50)
	t.eq(a.balancePerYear, 400)
	t.eq(a.annualised, false)
end)

t.test("assess: a passenger line uses the default target", function()
	-- 8 × 34% ÷ 70% = 3.89 → keep 4, trim 4.
	local a = metrics.assess(line({ carriesPassengers = true }))
	t.eq(a.target, 0.70)
	t.eq(metrics.percent(a.load), 34)
	t.eq(a.verdict, "TooMany")
	t.eq(a.keep, 4)
	t.eq(a.trim, 4)
end)

t.test("assess: exact division keeps exactly that many", function()
	-- 8 × 25% ÷ 50% = 4 → keep 4, trim 4 (no float round-up to 5).
	local a = metrics.assess(line({ itemsTransported = 300 }))
	t.eq(a.keep, 4)
	t.eq(a.trim, 4)
end)

t.test("assess: at the target is OK", function()
	local a = metrics.assess(line({ itemsTransported = 600 }))
	t.eq(a.verdict, "Ok")
	t.eq(a.trim, 0)
	t.eq(a.keep, nil)
end)

t.test("assess: below target but nothing to trim falls through to OK", function()
	-- 2 vehicles, 45% vs 50%: 2 × 0.45 ÷ 0.5 = 1.8 → keep 2, trim 0.
	local a = metrics.assess(line({ vehicleCount = 2, totalCapacity = 200, itemsTransported = 540 }))
	t.eq(a.verdict, "Ok")
	t.eq(a.trim, 0)
end)

t.test("assess: a single vehicle is never trimmed", function()
	local a = metrics.assess(line({ vehicleCount = 1, totalCapacity = 100, itemsTransported = 120 }))
	t.eq(a.verdict, "Ok")
	t.eq(a.trim, 0)
end)

t.test("assess: losing money wins, and still carries the trim", function()
	local a = metrics.assess(line({ balance = -80 }))
	t.eq(a.verdict, "Losing")
	t.eq(a.trim, 2)
	t.eq(a.profitPerVehicle, -10)
end)

t.test("assess: busy at 95% and above uses the default target for mixed lines", function()
	local a = metrics.assess(line({ cargoTypeCount = 2, itemsTransported = 1150 }))
	t.eq(a.verdict, "Busy")
	t.eq(a.target, 0.70)
	t.eq(a.trim, 0)
end)

t.test("assess: no vehicles", function()
	local a = metrics.assess(line({ vehicleCount = 0, totalCapacity = 0, balance = 0 }))
	t.eq(a.verdict, "NoVehicles")
	t.eq(a.profitPerVehicle, nil)
	t.eq(a.trim, 0)
end)

t.test("assess: too new below a month of data", function()
	local a = metrics.assess(line({ dataMs = 50 }))
	t.eq(a.verdict, "TooNew")
	t.eq(a.trim, 0)
end)

t.test("assess: unknown interval gives no load and no trim", function()
	local a = metrics.assess(line({ intervalMs = NIL }))
	t.eq(a.verdict, "Ok")
	t.eq(a.load, nil)
	t.eq(a.trim, 0)
end)

t.test("assess: a young line's balance is annualised", function()
	local a = metrics.assess(line({ dataMs = 600, balance = 100, itemsTransported = 300 }))
	t.eq(a.balancePerYear, 200)
	t.eq(a.annualised, true)
	t.eq(a.profitPerVehicle, 25)
end)

t.test("assess: losing beats busy", function()
	local a = metrics.assess(line({ cargoTypeCount = 2, itemsTransported = 1150, balance = -10 }))
	t.eq(a.verdict, "Losing")
	t.eq(a.trim, 0)
end)

t.test("assess: exactly a month of data is enough", function()
	local a = metrics.assess(line({ dataMs = 100, itemsTransported = 34 }))
	t.eq(a.verdict, "TooMany")
end)

t.test("constants: not-delivering thresholds", function()
	t.eq(metrics.STUCK_LOAD_NOW, 0.75)
	t.eq(metrics.STUCK_AVERAGE_LOAD, 0.25)
end)

t.test("assess: full now but little carried is not delivering, and no trim", function()
	local a = metrics.assess(line({ loadNow = 1.0, itemsTransported = 70 }))
	near(a.load, 70 / 1200, "load")
	t.eq(a.notDelivering, true)
	t.eq(a.trim, 0)
	t.eq(a.keep, nil)
	t.eq(a.verdict, "Ok")
end)

t.test("assess: not delivering keeps the Losing verdict", function()
	local a = metrics.assess(line({ loadNow = 1.0, itemsTransported = 70, balance = -100 }))
	t.eq(a.verdict, "Losing")
	t.eq(a.notDelivering, true)
	t.eq(a.trim, 0)
end)

t.test("assess: below the load-now threshold still trims", function()
	local a = metrics.assess(line({ loadNow = 0.70, itemsTransported = 70 }))
	t.eq(a.notDelivering, false)
	t.eq(a.trim > 0, true, "trim suggested")
end)

-- Seen in-game: two trucks at 100% and 70% on a line averaging 7%.
t.test("assess: one of two vehicles part-loaded is still not delivering", function()
	local a = metrics.assess(line({ loadNow = 0.85, itemsTransported = 70 }))
	t.eq(a.notDelivering, true)
	t.eq(a.trim, 0)
end)

t.test("assess: full now with a decent average is delivering", function()
	local a = metrics.assess(line({ loadNow = 1.0 }))
	t.eq(a.notDelivering, false)
end)

t.test("assess: unknown load now is not flagged", function()
	local a = metrics.assess(line({ loadNow = NIL }))
	t.eq(a.notDelivering, false)
end)

-- Vehicle-time: each vehicle offers capacity only while it has been on the line.
t.test("averageLoad: vehicles added recently count only for their own time", function()
	-- 2 vehicles ran all year (one round trip each, 1200 ms) and were 95% full; 4 more were bought just now, so
	-- today's interval is a sixth of the round trip.
	local input = line({ vehicleCount = 6, totalCapacity = 600, intervalMs = 200, itemsTransported = 380,
		vehicleDataMs = 2 * 1200 })
	near(metrics.averageLoad(input), 0.95)
	t.eq(metrics.assess(input).verdict, "Busy")
end)

t.test("averageLoad: nil when no vehicle has any time on the line", function()
	t.eq(metrics.averageLoad(line({ vehicleDataMs = 0 })), nil)
end)

t.test("averageLoad: vehicle-time over a full year matches the line-time formula", function()
	near(metrics.averageLoad(line({ vehicleDataMs = 8 * 1200 })), 0.34)
end)

-- Money booked on an entity: nonzero for any window ending after `firstMoney`.
local function moneyFrom(firstMoney)
	return function(from, to)
		return to > firstMoney and -1 or 0
	end
end

t.test("dataSpan: capped at a year", function()
	t.eq(metrics.dataSpan(moneyFrom(0), 1000, 5000, 1200), 1200)
end)

t.test("dataSpan: a new vehicle has data since it was bought", function()
	t.eq(metrics.dataSpan(moneyFrom(4700), 4700, 5000, 1200), 300)
end)

t.test("dataSpan: a replaced vehicle keeps its earlier history", function()
	-- Year window 3800..5000 in slices of 100; money from 4000, purchase time reset to 4700.
	t.eq(metrics.dataSpan(moneyFrom(4000), 4700, 5000, 1200), 1000)
end)

t.test("dataSpan: early in the game the window starts at 0", function()
	t.eq(metrics.dataSpan(moneyFrom(0), 300, 600, 1200), 600)
end)

t.test("dataSpan: a year too short to slice falls back to the purchase time", function()
	t.eq(metrics.dataSpan(moneyFrom(0), 7, 10, 6), 3)
end)

local function assessment(fields)
	local a = { verdict = "Ok", trim = 0, notDelivering = false, balancePerYear = 0 }
	for k, v in pairs(fields) do
		a[k] = v
	end
	return a
end

t.test("verdictKind: one kind per verdict", function()
	t.eq(metrics.verdictKind(assessment({ verdict = "Ok" })), "Ok")
	t.eq(metrics.verdictKind(assessment({ verdict = "Busy" })), "Busy")
	t.eq(metrics.verdictKind(assessment({ verdict = "TooNew" })), "TooNew")
	t.eq(metrics.verdictKind(assessment({ verdict = "NoVehicles" })), "NoVehicles")
	t.eq(metrics.verdictKind(assessment({ verdict = "TooMany", trim = 2 })), "TooMany")
	t.eq(metrics.verdictKind(assessment({ verdict = "Losing" })), "Losing")
end)

t.test("verdictKind: losing with a trim or not delivering", function()
	t.eq(metrics.verdictKind(assessment({ verdict = "Losing", trim = 3 })), "LosingTrim")
	t.eq(metrics.verdictKind(assessment({ verdict = "Losing", notDelivering = true })), "LosingStuck")
end)

t.test("severity: losing first, OK last", function()
	local order = { "LosingStuck", "TooMany", "Busy", "TooNew", "NoVehicles", "Ok" }
	for i = 2, #order do
		t.eq(metrics.severity(order[i - 1]) < metrics.severity(order[i]), true, order[i - 1] .. " < " .. order[i])
	end
	t.eq(metrics.severity("Losing"), metrics.severity("LosingTrim"))
	t.eq(metrics.severity("Losing"), metrics.severity("LosingStuck"))
end)

t.test("summarise: counts and sums", function()
	local s = metrics.summarise({
		assessment({ verdict = "Losing", balancePerYear = -100, trim = 2 }),
		assessment({ verdict = "Losing", balancePerYear = -50 }),
		assessment({ verdict = "TooMany", balancePerYear = 30, trim = 3 }),
		assessment({ verdict = "Ok", balancePerYear = 500 }),
	})
	t.eq(s.losingCount, 2)
	t.eq(s.losingPerYear, -150)
	t.eq(s.tooManyCount, 2, "lines with a trim, losing or not")
	t.eq(s.trimTotal, 5)
end)

t.test("summarise: empty", function()
	local s = metrics.summarise({})
	t.eq(s.losingCount, 0)
	t.eq(s.losingPerYear, 0)
	t.eq(s.tooManyCount, 0)
	t.eq(s.trimTotal, 0)
end)

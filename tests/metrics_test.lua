local t = ...
local metrics = t.requireTl("gui/pgrace_trim_the_fat/metrics.tl")

t.test("constants: starting targets", function()
	t.eq(metrics.TARGET_DEFAULT, 0.70)
	t.eq(metrics.TARGET_SINGLE_CARGO, 0.50)
	t.eq(metrics.BUSY_LOAD, 0.95)
end)

t.test("targetFor: single cargo vs everything else", function()
	t.eq(metrics.targetFor(1), 0.50, "one cargo type")
	t.eq(metrics.targetFor(2), 0.70, "two cargo types")
	t.eq(metrics.targetFor(0), 0.70, "unknown")
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

-- A line of 8 vehicles × 100 capacity, a departure every 100 ms, a full year of 1200 ms of data:
-- 12 departures × 100 per vehicle = 1200 capacity offered.
-- pairs() skips nil values, so an override of NIL clears the field.
local NIL = {}

local function line(overrides)
	local input = {
		vehicleCount = 8,
		balance = 400,
		itemsTransported = 408,
		totalCapacity = 800,
		intervalMs = 100,
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

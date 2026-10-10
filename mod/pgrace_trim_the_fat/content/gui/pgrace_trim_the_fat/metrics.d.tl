-- Pure helpers (no api.* calls), so tests/metrics_test.lua can run them in plain Lua.
global record PgraceTrimTheFatMetrics
	enum Verdict
		"NoVehicles"
		"TooNew"
		"Losing"
		"TooMany"
		"Busy"
		"Ok"
	end

	-- What line_data.tl reads from the engine for one line. Times are game time in milliseconds.
	record LineInput
		vehicleCount : integer
		-- Money over the last 12 months (less for a young line): income minus running and maintenance costs,
		-- purchase price excluded, as the base game's Balance.
		balance : integer
		-- Items carried over the last 12 months, all cargo types (the line window's "Transported").
		itemsTransported : integer
		-- Sum of the vehicles' capacities in their current load configuration, all cargo types.
		totalCapacity : number
		-- Time between departures at a stop; nil or <= 0 when unknown.
		intervalMs : number
		-- Length of the data window: min(one year, time since the oldest vehicle was bought).
		dataMs : number
		yearMs : number
		-- Cargo types the vehicles currently carry (capacity > 0).
		cargoTypeCount : integer
	end

	record Assessment
		verdict : Verdict
		-- Average load over the data window, nil when unknown (no capacity, interval or data).
		load : number
		target : number
		-- Balance scaled to a full year; equal to the balance once the window is a full year.
		balancePerYear : number
		-- True when balancePerYear was scaled up from less than a year.
		annualised : boolean
		-- balancePerYear / vehicleCount; nil when there are no vehicles.
		profitPerVehicle : number
		-- Vehicles to keep and to remove. trim is 0 (and keep nil) when no trim is suggested.
		keep : integer
		trim : integer
	end

	-- Target average load for lines carrying several cargo types or passengers.
	TARGET_DEFAULT : number
	-- Target for single-cargo lines, which usually run empty one way.
	TARGET_SINGLE_CARGO : number
	-- At or above this average load the verdict is Busy.
	BUSY_LOAD : number
	-- Below this share of a year of data the verdict is TooNew.
	MIN_DATA_FRACTION : number

	-- TARGET_SINGLE_CARGO for exactly one cargo type, TARGET_DEFAULT otherwise.
	targetFor : function(cargoTypeCount : integer) : number
	-- itemsTransported / (departures in the window × capacity per vehicle); nil when unknown.
	averageLoad : function(input : LineInput) : number
	-- amount × yearMs / spanMs and true when 0 < spanMs < yearMs; otherwise amount and false.
	annualise : function(amount : number, spanMs : number, yearMs : number) : number, boolean
	-- The verdict and the numbers behind it. See the spec §1 for the rules.
	assess : function(input : LineInput) : Assessment
	-- Whole percent, rounded half up (0.344 → 34); nil for nil.
	percent : function(fraction : number) : integer
	-- The plural form a language uses for a count: "one", "few", "many" or "other" (CLDR integer rules).
	-- The language is a TF3 code such as "de" or "pt_BR"; unknown ones get English's one/other.
	pluralCategory : function(language : string, count : integer) : string
end

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

	-- What the overview's verdict column shows: the verdict, split where the text differs.
	enum VerdictKind
		"Losing"
		"LosingTrim"
		"LosingStuck"
		"TooMany"
		"Busy"
		"TooNew"
		"NoVehicles"
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
		-- Stops on the line; each round trip runs one leg per stop.
		stopCount : integer
		-- Length of the data window: how long the line has had money booked, at most a year (dataSpan).
		dataMs : number
		-- Sum over the vehicles of how long each has been on the line within the data window (dataSpan of its own
		-- money). nil means every vehicle covers dataMs.
		vehicleDataMs : number
		-- Length of a game year in ms. Required (never nil).
		yearMs : number
		-- Cargo types the vehicles currently carry (capacity > 0).
		cargoTypeCount : integer
		-- True when passengers are among those cargo types.
		carriesPassengers : boolean
		-- Line-wide cargo on board ÷ capacity at snapshot time; nil when unknown.
		loadNow : number
		-- The most passengers waiting for the line at any one of its stops right now; nil when unknown or not a
		-- passenger line.
		waitingMax : integer
	end

	record Assessment
		verdict : Verdict
		-- Average load over the data window, nil when unknown (no capacity, interval, stops or data).
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
		-- True when the vehicles are full now but carried little over the window: cargo is on board but not being
		-- unloaded. No trim is suggested then.
		notDelivering : boolean
		-- True when waitingMax is at least BACKLOG_VEHICLES vehicles' worth of capacity: no trim, and Busy unless
		-- Losing.
		backlog : boolean
		-- True when waiting passengers kept the trim smaller than the load alone suggests (possibly 0).
		queueLimited : boolean
	end

	-- Totals over a set of lines, for the overview's summary line.
	record Summary
		-- Lines whose verdict is Losing, and the sum of their balance per year.
		losingCount : integer
		losingPerYear : number
		-- Lines with a trim suggestion (losing or not), and the sum of the trims.
		tooManyCount : integer
		trimTotal : integer
		-- Lines whose verdict is Busy.
		busyCount : integer
	end

	-- Target average load for passenger lines and lines carrying several cargo types.
	TARGET_DEFAULT : number
	-- Target for freight lines carrying one cargo type, which usually run empty one way.
	TARGET_SINGLE_CARGO : number
	-- At or above this average load the verdict is Busy.
	BUSY_LOAD : number
	-- Below this share of a year of data the verdict is TooNew.
	MIN_DATA_FRACTION : number
	-- At or above this current load (line-wide, right now), with a low average, the line is not delivering. Well
	-- below "full", because one part-loaded vehicle on a small line moves the snapshot a lot.
	STUCK_LOAD_NOW : number
	-- Below this average load, with full vehicles now, the line is not delivering.
	STUCK_AVERAGE_LOAD : number
	-- Passengers waiting at one stop, in vehicles' worth of capacity, that count as a backlog.
	BACKLOG_VEHICLES : number
	-- Below this share of a year of data a vehicle's balance per year is "too new": a vehicle's first trips (from the
	-- depot, a few round trips) scaled up mislead for longer than a whole line's money does.
	MIN_VEHICLE_DATA_FRACTION : number
	-- A trim keeps enough vehicles that each stop's queue, grown by count ÷ keep, stays at or under this many
	-- vehicles' worth of capacity. Below BACKLOG_VEHICLES, so adding and removing a vehicle doesn't go back and forth.
	TRIM_QUEUE_LIMIT : number

	-- TARGET_SINGLE_CARGO for exactly one cargo type that isn't passengers, TARGET_DEFAULT otherwise.
	targetFor : function(cargoTypeCount : integer, carriesPassengers : boolean) : number
	-- itemsTransported / (round trips in the window × capacity per vehicle × stops); nil when unknown
	-- (no vehicles, capacity, interval, stops or data).
	averageLoad : function(input : LineInput) : number
	-- amount × yearMs / spanMs and true when 0 < spanMs < yearMs; otherwise amount and false.
	annualise : function(amount : number, spanMs : number, yearMs : number) : number, boolean
	-- A vehicle's balance per year: nil (and false) under MIN_VEHICLE_DATA_FRACTION of a year of data, where a few days of
	-- running costs scaled up to a year would mislead (a new bus showed -381k*); otherwise annualise.
	vehiclePerYear : function(balance : number, spanMs : number, yearMs : number) : number, boolean
	-- How long money has been booked on something within the last year, in ms, given balanceBetween(from, to).
	-- Usually since `bought`, but replacing a vehicle resets its purchase time and keeps its balance history, so
	-- this looks for money booked before `bought`, a twelfth of a year at a time.
	dataSpan : function(balanceBetween : function(integer, integer) : number, bought : integer, now : integer,
		yearMs : integer) : integer
	-- The verdict and the numbers behind it.
	-- First match wins: NoVehicles (0 vehicles), TooNew (dataMs < yearMs × MIN_DATA_FRACTION), Losing (balancePerYear < 0), Busy (backlog), TooMany (trim > 0), Busy (load >= BUSY_LOAD), Ok. Losing still carries a trim suggestion, limited by TRIM_QUEUE_LIMIT. A line that is not delivering (loadNow >= STUCK_LOAD_NOW and a known load < STUCK_AVERAGE_LOAD) gets notDelivering and no trim, its verdict otherwise unchanged.
	assess : function(input : LineInput) : Assessment
	-- Whole percent, rounded half up (0.344 → 34); nil for nil.
	percent : function(fraction : number) : integer
	-- The plural form a language uses for a count: "one", "few", "many" or "other" (CLDR integer rules).
	-- The language is a TF3 code such as "de" or "pt_BR"; unknown ones get English's one/other.
	pluralCategory : function(language : string, count : integer) : string
	-- Losing becomes LosingStuck when not delivering, LosingTrim when it carries a trim; other verdicts map 1:1.
	verdictKind : function(a : Assessment) : VerdictKind
	-- Sort rank, lowest first: Losing kinds 1, TooMany 2, Busy 3, TooNew 4, NoVehicles 5, Ok 6.
	severity : function(kind : VerdictKind) : integer
	summarise : function(assessments : {Assessment}) : Summary
end

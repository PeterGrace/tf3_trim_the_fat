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
		"BusyThin"
		"TooNew"
		"NoVehicles"
		"Ok"
	end

	-- Average yearly income over the last TREND_RECENT_YEARS full years, and income and balance over the
	-- TREND_BEFORE_YEARS before them.
	record Trend
		recentIncome : number
		beforeIncome : number
		beforeBalance : number
	end

	-- One itemsAtStop<k>_c<cargo> log: a running total of what was on board arriving at stop k, one entry per arrival
	-- with anything on board (seen in-game: 365 of 365 such arrivals matched, no entry for 19 empty ones).
	record StopLog
		times : {integer}
		values : {integer}
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
		-- The line's running costs in the last full calendar year (a positive number); nil before its first full year.
		runningCostsPerYear : number
		-- Income and running costs (positive) per calendar year, oldest first, the current (partial) year last, as
		-- the line window's Balance chart; nil when unknown. At least 10 years for a trend.
		incomeByYear : {number}
		costsByYear : {number}
		-- When the line's vehicles last changed (bought, replaced, sold or moved), as far as is known; nil for never.
		lastChangeMs : integer
		-- The game time the input was read at.
		nowMs : integer
		-- At the stop and cargo type whose departures over the last year most often left full (loaded a vehicle's
		-- capacity for that cargo; stops set to wait for a full load don't count): how many did, out of how many; nil
		-- when unknown.
		fullDepartures : integer
		departures : integer
		-- From the stop logs over the last year (lineStopTotals): what was carried into all stops (a rider counts on each
		-- leg), and the capacity offered at the stop that offered the most; nil or 0 when nothing is logged (averageLoad
		-- then falls back to intervalMs).
		loggedCarried : number
		busiestStopOffered : number
	end

	record Assessment
		verdict : Verdict
		-- Average load over the last 12 months (averageLoad), nil when unknown.
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
		-- True when waitingMax (unless queueIgnored) is at least BACKLOG_VEHICLES vehicles' worth of capacity, or fullShare is at least
		-- FULL_DEPARTURE_SHARE: no trim, and Busy unless Losing.
		backlog : boolean
		-- Which made it a backlog: waitingMax, or fullShare (either or both).
		waitingBacklog : boolean
		fullBacklog : boolean
		-- True when waiting passengers kept the trim smaller than the load alone suggests (possibly 0).
		queueLimited : boolean
		-- balancePerYear ÷ runningCostsPerYear; nil when the running costs are unknown.
		margin : number
		-- True when another vehicle fills from passengers or cargo left behind: DEEP_QUEUE_VEHICLES vehicles' worth
		-- waiting, or fullBacklog. It then earns about what the average vehicle does.
		deepQueue : boolean
		-- True when the verdict is Busy but margin is under THIN_MARGIN, unless deepQueue on a line that makes
		-- money: another vehicle would likely lose money.
		thinMargin : boolean
		-- nil without enough history (metrics.trend).
		trend : Trend
		-- True when the line made money over the earlier years and its recent income is under DECLINE_RATIO of
		-- theirs. A marker beside the verdict, which it doesn't change.
		declining : boolean
		-- True when the vehicles changed less than RECENT_CHANGE_FRACTION of a year ago: the 12-month numbers still
		-- mix the old setup in. The verdict is unchanged.
		changedRecently : boolean
		-- True when balancePerYear is negative but no lower than BREAK_EVEN_BAND of runningCostsPerYear: not Losing.
		breakEven : boolean
		-- Average balance (income minus running costs) over the last LOSING_YEARS full calendar years; nil without them.
		recentYearsBalance : number
		-- True when the 12-month balance is a loss beyond the band but recentYearsBalance isn't negative: not Losing.
		shortLoss : boolean
		-- fullDepartures ÷ departures; nil under MIN_DEPARTURES departures.
		fullShare : number
		-- True when waitingMax would have made a backlog or limited the trim, but fullShare is under QUEUE_FULL_SHARE:
		-- each vehicle takes the whole queue, so it was left out (also of deepQueue).
		queueIgnored : boolean
	end

	-- Totals over a set of lines, for the overview's summary line.
	record Summary
		-- Lines whose verdict is Losing, and the sum of their balance per year.
		losingCount : integer
		losingPerYear : number
		-- Lines with a trim suggestion (losing or not), and the sum of the trims.
		tooManyCount : integer
		trimTotal : integer
		-- Lines whose verdict is Busy, without a thin margin (lines that may need more vehicles).
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
	-- Under this fullShare, people waiting at a stop don't count: no backlog, deep queue or trim limit from them.
	QUEUE_FULL_SHARE : number
	-- Under this balance ÷ running costs, a Busy line is too thin for another vehicle to pay for itself.
	THIN_MARGIN : number
	-- Waiting passengers, in vehicles' worth of capacity, from which another vehicle fills from the queue: a thin
	-- margin no longer counts.
	DEEP_QUEUE_VEHICLES : number
	-- Years averaged for a trend: the recent ones, and the ones before them.
	TREND_RECENT_YEARS : integer
	TREND_BEFORE_YEARS : integer
	-- Recent income under this share of the earlier income is a decline.
	DECLINE_RATIO : number
	-- A vehicle change younger than this share of a year counts as recent. A whole year: the balance and the average
	-- load cover 12 months, so they settle only a year after the vehicles change (seen in-game: 3 → 5 buses, the load
	-- had come down from 56% to 47% half a year later).
	RECENT_CHANGE_FRACTION : number
	-- At or above this share of full departures from one stop, the line has a backlog.
	FULL_DEPARTURE_SHARE : number
	-- Fewer departures than this say nothing.
	MIN_DEPARTURES : integer
	-- A loss down to this share of the running costs is break-even, not Losing.
	BREAK_EVEN_BAND : number
	-- Full calendar years whose average balance must also be negative for Losing.
	LOSING_YEARS : integer

	-- TARGET_SINGLE_CARGO for exactly one cargo type that isn't passengers, TARGET_DEFAULT otherwise.
	targetFor : function(cargoTypeCount : integer, carriesPassengers : boolean) : number
	-- loggedCarried / (stops × busiestStopOffered); without them, itemsTransported / (round trips in the window, from
	-- intervalMs, × capacity per vehicle × stops). nil when unknown (no vehicles, capacity or stops; or nothing
	-- logged and no interval or data).
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
	-- The year before the current one in a yearly series (current year last); nil before the first full year.
	lastFullYear : function(values : {number}) : number
	-- Averages over the last TREND_RECENT_YEARS full years and the TREND_BEFORE_YEARS before them; nil when the
	-- series are missing, differ in length or are too short (the first and current years don't count).
	trend : function(income : {number}, costs : {number}) : Trend
	-- From a stop's itemsAtStop log (one entry per arrival with anything on board): the departures from the stop
	-- before, after `since`, and how many of them carried at least `capacity`. 0, 0 without a log or capacity.
	countFullDepartures : function(times : {integer}, values : {integer}, capacity : number, since : integer) : integer, integer
	-- What was carried into one stop, and the capacity offered, over arrivals after `since`, from its itemsAtStop logs
	-- (one per cargo type). Each entry's load is its rise over the entry before; entries at the same time in different
	-- logs are one arrival. An arrival offered max(capacity, carried): vehicles arriving together can share an entry,
	-- and a vehicle replaced by a smaller one carried up to its old capacity. 0, 0 without logs.
	stopTotals : function(logs : {StopLog}, since : integer, capacity : number) : number, number
	-- stopTotals over every stop (one list of logs per stop): carried summed, and the most any one stop offered.
	lineStopTotals : function(stops : {{StopLog}}, since : integer, capacity : number) : number, number
	-- Average of income minus costs over the last `years` full years of yearly series (current year last); nil when
	-- missing, of different lengths or too short (the first and current years don't count).
	recentBalance : function(income : {number}, costs : {number}, years : integer) : number
	-- The verdict and the numbers behind it.
	-- First match wins: NoVehicles (0 vehicles), TooNew (dataMs < yearMs × MIN_DATA_FRACTION), Losing (balancePerYear below -BREAK_EVEN_BAND × runningCostsPerYear, or below 0 when the costs are unknown, and recentYearsBalance negative or unknown), Busy (backlog), TooMany (trim > 0), Busy (load >= BUSY_LOAD), Ok. Losing still carries a trim suggestion, limited by TRIM_QUEUE_LIMIT. A line that is not delivering (loadNow >= STUCK_LOAD_NOW and a known load < STUCK_AVERAGE_LOAD) gets notDelivering and no trim, its verdict otherwise unchanged.
	assess : function(input : LineInput) : Assessment
	-- Whole percent, rounded half up (0.344 → 34); nil for nil.
	percent : function(fraction : number) : integer
	-- The plural form a language uses for a count: "one", "few", "many" or "other" (CLDR integer rules).
	-- The language is a TF3 code such as "de" or "pt_BR"; unknown ones get English's one/other.
	pluralCategory : function(language : string, count : integer) : string
	-- Losing becomes LosingStuck when not delivering, LosingTrim when it carries a trim; Busy becomes BusyThin on a thin
	-- margin; other verdicts map 1:1.
	verdictKind : function(a : Assessment) : VerdictKind
	-- Sort rank, lowest first: Losing kinds 1, TooMany 2, Busy kinds 3, TooNew 4, NoVehicles 5, Ok 6.
	severity : function(kind : VerdictKind) : integer
	summarise : function(assessments : {Assessment}) : Summary
end

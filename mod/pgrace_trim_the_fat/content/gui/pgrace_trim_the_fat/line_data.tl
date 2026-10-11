local metrics = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/metrics.tl" as PgraceTrimTheFatMetrics

local line_data : PgraceTrimTheFatLineData = {}

local type VehicleRow = PgraceTrimTheFatLineData.VehicleRow
local type Noun = PgraceTrimTheFatLineData.Noun

local function nowMs() : integer
	local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return gameTime.gameTime
end

-- nil when the vehicle no longer exists (sold, replaced) or has no vehicle component.
local function transportVehicle(vehicle : Engine.Entity) : Engine.Component.TransportVehicle
	if not api.engine.entityExists(vehicle) then
		return nil
	end
	return api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
end

-- A vehicle is as old as its oldest part (as the base game's vehicle_util.getAge).
local function purchaseTime(tv : Engine.Component.TransportVehicle) : integer
	local oldest : integer = nil
	for __, part in ipairs(tv.transportVehicleConfig.vehicles) do
		if oldest == nil or part.purchaseTime < oldest then
			oldest = part.purchaseTime
		end
	end
	return oldest
end

local function nounFor(carrier : Carrier, carriesPassengers : boolean) : Noun
	local carriers = api.type["enum"].Carrier
	if carrier == carriers.RAIL then
		return "train"
	elseif carrier == carriers.TRAM then
		return "tram"
	elseif carrier == carriers.WATER then
		return "ship"
	elseif carrier == carriers.AIR then
		return "aircraft"
	elseif carrier == carriers.ROAD then
		return carriesPassengers and "bus" or "truck"
	end
	return "vehicle"
end

-- Used and total capacity over the cargo types the vehicles currently carry, how many such types, and whether
-- passengers are among them.
-- Used and total capacity over all cargo types, how many types, whether passengers are one, and the passenger
-- capacity alone.
local function capacityTotals(line : Engine.Entity, allCapacities : boolean) : number, number, integer, boolean, number
	local usages = api.engine.util.line.getLineCapacityUsages(line, allCapacities)
	local passengerIndex = api.res.cargoTypeRep.getPassengerCargoTypeId() + 1
	local used, capacity, types, passengers, passengerCapacity = 0.0, 0.0, 0, false, 0.0
	-- Keys are cargoTypeId + 1 (as in the base cargo_util), despite the tealdef's key type.
	for index, usage in pairs(usages or {}) do
		if usage.capacity > 0 then
			used = used + usage.used
			capacity = capacity + usage.capacity
			types = types + 1
			if index == passengerIndex then
				passengers = true
				passengerCapacity = usage.capacity
			end
		end
	end
	return used, capacity, types, passengers, passengerCapacity
end

function line_data.lineLoadNow(line : Engine.Entity) : number
	local used, capacity = capacityTotals(line, false)
	if capacity <= 0 then
		return nil
	end
	return used / capacity
end

function line_data.vehicleLoadNow(vehicle : Engine.Entity) : number
	local tv = transportVehicle(vehicle)
	if tv == nil then
		return nil
	end
	local used, capacity = 0, 0
	-- capacities[i] is the capacity for cargo type i - 1 in the current load configuration.
	for i, cap in ipairs(tv.config.capacities) do
		if cap > 0 then
			capacity = capacity + cap
			used = used + api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType(vehicle, i - 1)
		end
	end
	if capacity <= 0 then
		return nil
	end
	return used / capacity
end

-- Listed on the line as vehicleSignature lists it, so the row and the refresh prompt agree.
function line_data.isOnLine(vehicle : Engine.Entity, line : Engine.Entity) : boolean
	if transportVehicle(vehicle) == nil then
		return false
	end
	for __, listed in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		if listed == vehicle then
			return true
		end
	end
	return false
end

-- Which vehicles the line has and when each was bought. Changes when a vehicle is bought, sold or replaced
-- (replacing keeps the entity but resets its purchase time).
-- Sorts `parts` ("vehicle:purchaseTime") in place.
local function signatureOf(parts : {string}) : string
	table.sort(parts)
	return table.concat(parts, ",")
end

function line_data.vehicleSignature(line : Engine.Entity) : string
	local parts : {string} = {}
	for __, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		local tv = transportVehicle(vehicle)
		if tv ~= nil then
			parts[#parts + 1] = tostring(vehicle) .. ":" .. tostring(purchaseTime(tv))
		end
	end
	return signatureOf(parts)
end

-- How long money has been booked on `entities` within the last year (metrics.dataSpan).
local function dataSpan(entities : {Engine.Entity}, bought : integer, now : integer, yearMs : integer) : integer
	return metrics.dataSpan(function(from : integer, to : integer) : number
		return api.engine.util.finance.calculateBalance(entities, from, to, true)
	end, bought, now, yearMs)
end

-- The most passengers waiting for the line at one of its stops (as Commuter Compass counts them); nil when the
-- count fails.
local function waitingMax(line : Engine.Entity, stopCount : integer) : integer
	local ok, result = pcall(function() : integer
		local passenger = api.res.cargoTypeRep.getPassengerCargoTypeId()
		local most = 0
		for stop = 0, stopCount - 1 do
			local waiting = api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntitiesCount(line, stop, passenger)
			if waiting > most then
				most = waiting
			end
		end
		return most
	end)
	return ok and result as integer or nil
end

-- The line's income and running costs per calendar year, oldest first, the current (partial) year last, as the
-- line window's Balance chart draws them; nil when the chart can't be read. Costs are positive.
local function accountYears(line : Engine.Entity, years : integer) : {number}, {number}
	local ok, result = pcall(function() : {{number}}
		local config : ChartConfig = api.type.ChartConfig.new()
		config.count = years
		-- Seen in-game: series[1] is income and series[2] running costs, each { years, values }.
		local series = api.engine.util.finance.getAccountChart(line, config).series
		return { series[1][2], series[2][2] }
	end)
	if not ok then
		return nil, nil
	end
	local pair = result as {{number}}
	return pair[1], pair[2]
end

-- Over the last year, at the stop whose departures most often left full: how many did, out of how many departures
-- (nil, nil when unknown). The line logs a running total of boarders per stop, one entry per departure
-- ("itemsAtStop<stop>_c<cargo>"; its stop number runs one ahead of the line's stop index, which doesn't matter here).
local function fullDepartures(line : Engine.Entity, capacityPerVehicle : number, now : integer, yearMs : integer) : integer, integer
	local ok, best = pcall(function() : {integer}
		local book = api.engine.getComponent(line, api.type.ComponentType.LOG_BOOK) as Engine.Component.LogBook
		if book == nil then
			return nil
		end
		local suffix = "_c" .. api.res.cargoTypeRep.getPassengerCargoTypeId()
		local result : {integer} = nil
		for name, log in pairs(book.name2log_native:asTable()) do
			if name:sub(1, 11) == "itemsAtStop" and name:sub(-#suffix) == suffix and name:find("Unsatisfied") == nil then
				local full, count = metrics.countFullDepartures(log.times_native:asTable(), log.values_native:asTable(),
					capacityPerVehicle, now - yearMs)
				if count >= metrics.MIN_DEPARTURES and (result == nil or full / count > result[1] / result[2]) then
					result = { full, count }
				end
			end
		end
		return result
	end)
	if not ok or best == nil then
		return nil, nil
	end
	local pair = best as {integer}
	return pair[1], pair[2]
end

-- Each line's vehicles when last read, and when they were last seen to change. Sales and vehicles moved between lines
-- leave no trace in the game's data, so this is the only way to see them; it starts empty after a restart.
local record Seen
	signature : string
	changedAt : integer
end
local seen : {Engine.Entity : Seen} = {}

-- When the line's vehicles last changed: the newest purchase (or replacement), or a change in the vehicle list
-- since the line was last read; nil when neither is known.
local function lastChange(line : Engine.Entity, signature : string, newestPurchase : integer, now : integer) : integer
	local entry = seen[line]
	if entry == nil then
		seen[line] = { signature = signature }
	elseif entry.signature ~= signature then
		seen[line] = { signature = signature, changedAt = now }
	end
	local changedAt = seen[line].changedAt
	if changedAt == nil or (newestPurchase ~= nil and newestPurchase > changedAt) then
		return newestPurchase
	end
	return changedAt
end

-- The line-level numbers, and the vehicle rows when withRows is set (the overview skips them).
local function collect(line : Engine.Entity, withRows : boolean) : PgraceTrimTheFatLineData.LineFacts, {VehicleRow}
	local now = nowMs()
	local yearMs = api.util.getDefaultYearDuration()
	local from = math.max(now - yearMs, 0)
	local rows : {VehicleRow} = {}
	local count = 0
	local oldest : integer = nil
	local vehicleDataMs = 0
	local carrier : Carrier = nil
	local newest : integer = nil
	local parts : {string} = {}
	for __, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		local tv = transportVehicle(vehicle)
		if tv ~= nil then
			count = count + 1
			local bought = purchaseTime(tv) or now
			if oldest == nil or bought < oldest then
				oldest = bought
			end
			if newest == nil or bought > newest then
				newest = bought
			end
			parts[#parts + 1] = tostring(vehicle) .. ":" .. tostring(bought)
			if carrier == nil then
				carrier = tv.carrier
			end
			local spanMs = dataSpan({ vehicle }, bought, now, yearMs)
			vehicleDataMs = vehicleDataMs + spanMs
			if withRows then
				local balance = api.engine.util.finance.calculateBalance({ vehicle }, from, now, true)
				local perYear, annualised = metrics.vehiclePerYear(balance, spanMs, yearMs)
				rows[#rows + 1] = {
					entity = vehicle,
					name = api.engine.util.getEntityName(vehicle),
					ageText = api.engine.util.formatAge(bought, now),
					ageMs = now - bought,
					balancePerYear = perYear,
					annualised = annualised,
					loadNow = line_data.vehicleLoadNow(vehicle),
				}
			end
		end
	end
	local __, capacity, cargoTypes, passengers, passengerCapacity = capacityTotals(line, false)
	local full, departures : integer, integer = nil, nil
	if passengers and count > 0 then
		full, departures = fullDepartures(line, passengerCapacity / count, now, yearMs)
	end
	local frequency = api.engine.util.line.getMaxFrequency(line)
	local lineComponent = api.engine.getComponent(line, api.type.ComponentType.LINE) as Engine.Component.Line
	local income, costs = accountYears(line, metrics.TREND_RECENT_YEARS + metrics.TREND_BEFORE_YEARS + 2)
	local facts : PgraceTrimTheFatLineData.LineFacts = {
		input = {
			vehicleCount = count,
			balance = api.engine.util.finance.calculateBalance({ line }, from, now, true),
			itemsTransported = api.engine.util.logbook.getLogValuePerYear(line, "itemsTransported"),
			totalCapacity = capacity,
			-- getMaxFrequency is departures per second; the line window shows 1 / frequency seconds.
			intervalMs = (frequency ~= nil and frequency > 0.0001) and 1000 / frequency or nil,
			stopCount = lineComponent ~= nil and #lineComponent.stops or nil,
			dataMs = oldest ~= nil and dataSpan({ line }, oldest, now, yearMs) or 0,
			vehicleDataMs = vehicleDataMs,
			yearMs = yearMs,
			cargoTypeCount = cargoTypes,
			loadNow = line_data.lineLoadNow(line),
			carriesPassengers = passengers,
			waitingMax = (passengers and lineComponent ~= nil) and waitingMax(line, #lineComponent.stops) or nil,
			runningCostsPerYear = metrics.lastFullYear(costs),
			incomeByYear = income,
			costsByYear = costs,
			lastChangeMs = lastChange(line, signatureOf(parts), newest, now),
			nowMs = now,
			fullDepartures = full,
			departures = departures,
		},
		noun = nounFor(carrier, passengers),
	}
	return facts, rows
end

function line_data.lineInput(line : Engine.Entity) : PgraceTrimTheFatLineData.LineFacts
	local facts = collect(line, false)
	return facts
end

function line_data.snapshot(line : Engine.Entity) : PgraceTrimTheFatLineData.LineSnapshot
	local facts, rows = collect(line, true)
	return {
		input = facts.input,
		vehicles = rows,
		signature = line_data.vehicleSignature(line),
		noun = facts.noun,
	}
end

function line_data.playerLines() : {Engine.Entity}
	return api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())
end

return line_data

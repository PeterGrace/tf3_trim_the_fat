local metrics = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/metrics.tl" as PgraceTrimTheFatMetrics

local line_data : PgraceTrimTheFatLineData = {}

local LOG_PREFIX = "[trim_the_fat] "

local type VehicleRow = PgraceTrimTheFatLineData.VehicleRow
local type Noun = PgraceTrimTheFatLineData.Noun

local function nowMs() : integer
	local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return gameTime.gameTime
end

local function transportVehicle(vehicle : Engine.Entity) : Engine.Component.TransportVehicle
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
local function capacityTotals(line : Engine.Entity) : number, number, integer, boolean
	local usages = api.engine.util.line.getLineCapacityUsages(line, false)
	local passengerIndex = api.res.cargoTypeRep.getPassengerCargoTypeId() + 1
	local used, capacity, types, passengers = 0.0, 0.0, 0, false
	for index, usage in pairs(usages or {}) do
		if usage.capacity > 0 then
			used = used + usage.used
			capacity = capacity + usage.capacity
			types = types + 1
			if index == passengerIndex then
				passengers = true
			end
		end
	end
	return used, capacity, types, passengers
end

function line_data.lineLoadNow(line : Engine.Entity) : number
	local used, capacity = capacityTotals(line)
	if capacity <= 0 then
		return nil
	end
	return used / capacity
end

function line_data.vehicleLoadNow(vehicle : Engine.Entity) : number
	local tv = transportVehicle(vehicle)
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

function line_data.snapshot(line : Engine.Entity) : PgraceTrimTheFatLineData.LineSnapshot
	local now = nowMs()
	local yearMs = api.util.getDefaultYearDuration()
	local from = math.max(now - yearMs, 0)
	local rows : {VehicleRow} = {}
	local oldest : integer = nil
	local carrier : Carrier = nil
	for __, vehicle in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
		local tv = transportVehicle(vehicle)
		local bought = purchaseTime(tv) or now
		if oldest == nil or bought < oldest then
			oldest = bought
		end
		if carrier == nil then
			carrier = tv.carrier
		end
		local ageMs = now - bought
		local balance = api.engine.util.finance.calculateBalance({ vehicle }, from, now, true)
		local perYear, annualised = metrics.annualise(balance, ageMs, yearMs)
		rows[#rows + 1] = {
			entity = vehicle,
			name = api.engine.util.getEntityName(vehicle),
			ageText = api.engine.util.formatAge(bought, now),
			ageMs = ageMs,
			balancePerYear = perYear,
			annualised = annualised,
			loadNow = line_data.vehicleLoadNow(vehicle),
		}
	end
	local __, capacity, cargoTypes, passengers = capacityTotals(line)
	local frequency = api.engine.util.line.getMaxFrequency(line)
	return {
		input = {
			vehicleCount = #rows,
			balance = api.engine.util.finance.calculateBalance({ line }, from, now, true),
			itemsTransported = api.engine.util.logbook.getLogValuePerYear(line, "itemsTransported"),
			totalCapacity = capacity,
			-- getMaxFrequency is departures per second; the line window shows 1 / frequency seconds.
			intervalMs = (frequency ~= nil and frequency > 0.0001) and 1000 / frequency or nil,
			dataMs = oldest ~= nil and math.min(yearMs, now - oldest) or 0,
			yearMs = yearMs,
			cargoTypeCount = cargoTypes,
		},
		vehicles = rows,
		noun = nounFor(carrier, passengers),
	}
end

-- PROBE (remove before release): the raw inputs, to check units and calibrate the targets in-game.
function line_data.probe(line : Engine.Entity, snap : PgraceTrimTheFatLineData.LineSnapshot, assessment : PgraceTrimTheFatMetrics.Assessment)
	local ok, err = pcall(function() : boolean
		local i = snap.input
		debugPrint(LOG_PREFIX .. "probe line " .. tostring(line)
			.. " name=" .. tostring(api.engine.util.getEntityName(line))
			.. " frequency=" .. tostring(api.engine.util.line.getMaxFrequency(line))
			.. " intervalMs=" .. tostring(i.intervalMs)
			.. " vehicles=" .. tostring(i.vehicleCount)
			.. " capacity=" .. tostring(i.totalCapacity)
			.. " cargoTypes=" .. tostring(i.cargoTypeCount)
			.. " items=" .. tostring(i.itemsTransported)
			.. " dataMs=" .. tostring(i.dataMs)
			.. " yearMs=" .. tostring(i.yearMs)
			.. " balance=" .. tostring(i.balance)
			.. " loadA=" .. tostring(assessment.load)
			.. " loadNow=" .. tostring(line_data.lineLoadNow(line))
			.. " verdict=" .. tostring(assessment.verdict)
			.. " noun=" .. tostring(snap.noun))
		for __, row in ipairs(snap.vehicles) do
			local logOk, items = pcall(api.engine.util.logbook.getLogValuePerYear, row.entity, "itemsTransported")
			debugPrint(LOG_PREFIX .. "probe vehicle " .. tostring(row.entity)
				.. " itemsTransportedOk=" .. tostring(logOk)
				.. " itemsTransported=" .. tostring(items)
				.. " ageMs=" .. tostring(row.ageMs)
				.. " balancePerYear=" .. tostring(row.balancePerYear))
		end
		return true
	end)
	if not ok then
		debugPrint(LOG_PREFIX .. "probe failed: " .. tostring(err))
	end
end

return line_data

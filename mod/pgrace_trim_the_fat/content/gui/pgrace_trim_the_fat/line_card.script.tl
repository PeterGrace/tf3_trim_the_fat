local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local line_react_util = ug_require "::/gui/line_vehicle_mgmt/line_react_util.tl" as LineReactUtil
local line_eow = ug_require "::/gui/entity_window/line/line_eow.script.tl" as LineEow
local metrics = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/metrics.tl" as PgraceTrimTheFatMetrics
local line_data = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/line_data.tl" as PgraceTrimTheFatLineData
local ui = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/ui.tl" as PgraceTrimTheFatUi

local LOG_PREFIX = "[trim_the_fat] "
-- Live loads poll this often (AGENTS.md: useStepState runs every frame in every cell).
local LIVE_POLL_SECONDS = 0.25

local type Assessment = PgraceTrimTheFatMetrics.Assessment
local type LineSnapshot = PgraceTrimTheFatLineData.LineSnapshot
local type VehicleRow = PgraceTrimTheFatLineData.VehicleRow

local function passengersText(count : integer) : string
	return ui.countText(count, {
		one = _("{count} passengers|one"), few = _("{count} passengers|few"),
		many = _("{count} passengers|many"), other = _("{count} passengers|other"),
	})
end

-- Card data ----------------------------------------------------------------------------------------------------

-- Built once when the window opens and handed to the table as userParam (cells keep their first userParam).
local record CardData
	error : boolean
	line : Engine.Entity
	snapshot : LineSnapshot
	assessment : Assessment
	-- Vehicle rows by entity, which are also the table's row keys.
	rows : {integer : VehicleRow}
	-- Each vehicle's load as of the card build or the last header click. Frozen in between, so the shown numbers
	-- and the sort always agree (live values made a sorted column look out of order).
	sortLoad : {integer : number}
	-- sortLoad as text, by entity; the Load cells only read this.
	loadText : {integer : string}
	-- Balance per year as text, by entity: formatted once here, so cells don't call api.util.formatMoney.
	balanceText : {integer : string}
	-- The player's sort, kept across re-renders. Starts on Balance per year (column 3), lowest first.
	sortColumn : integer
	sortAscending : boolean
	-- Differs for every build, so a refresh remounts the table with fresh cells (cells keep their first userParam).
	generation : integer
end

local nextGeneration = 0

-- Never throws: everything that reads the engine or formats runs inside the pcall.
local function buildCardData(line : Engine.Entity) : CardData
	nextGeneration = nextGeneration + 1
	local generation = nextGeneration
	local ok, dataOrError = pcall(function() : CardData
		local snap = line_data.snapshot(line)
		local data : CardData = {
			error = false,
			line = line,
			snapshot = snap,
			assessment = metrics.assess(snap.input),
			rows = {},
			sortLoad = {},
			loadText = {},
			balanceText = {},
			sortColumn = 3,
			sortAscending = true,
			generation = generation,
		}
		for __, row in ipairs(snap.vehicles) do
			data.rows[row.entity] = row
			data.sortLoad[row.entity] = row.loadNow
			data.loadText[row.entity] = ui.formatPercent(row.loadNow)
			data.balanceText[row.entity] = row.balancePerYear ~= nil
				and ui.moneyText(row.balancePerYear, row.annualised) or _("Too new")
		end
		return data
	end)
	if not ok then
		debugPrint(LOG_PREFIX .. "error for line " .. tostring(line) .. ": " .. tostring(dataOrError))
		return { error = true, generation = generation }
	end
	local data = dataOrError as CardData
	return data
end

-- Verdict -------------------------------------------------------------------------------------------------------

local function verdictLabel(a : PgraceTrimTheFatMetrics.Assessment) : string, string
	local verdict = a.verdict
	if a.thinMargin then
		return _("Busy, but another vehicle would likely lose money"), "font-scale-body, warning"
	elseif verdict == "NoVehicles" then
		return _("No vehicles on this line"), "font-scale-body"
	elseif verdict == "TooNew" then
		return _("Too new to judge"), "font-scale-body"
	elseif verdict == "Losing" then
		return _("Losing money"), "font-scale-body, negative"
	elseif verdict == "TooMany" then
		return _("Too many vehicles"), "font-scale-body, warning"
	elseif verdict == "Busy" then
		return _("Busy: may need more vehicles"), "font-scale-body, warning"
	end
	return _("OK"), "font-scale-body, positive"
end

local function verdictTooltip(data : CardData) : string
	local a = data.assessment
	local count = data.snapshot.input.vehicleCount
	local parts : {string} = {}
	if a.verdict == "TooNew" then
		parts[#parts + 1] = _("This line has less than a month of data.")
	end
	if a.verdict == "Losing" then
		parts[#parts + 1] = _("The balance over the last 12 months is negative: income minus running and maintenance costs, without the purchase price.")
	end
	if a.queueLimited then
		parts[#parts + 1] = ui.fill(_("{count} × {load} ÷ {target} = {exact}."), {
			count = ui.formatCount(count),
			load = ui.formatPercent(a.load),
			target = ui.formatPercent(a.target),
			exact = ui.formatOneDecimal(count * a.load / a.target),
		})
		parts[#parts + 1] = ui.fill(_("With {passengers} waiting at one stop, fewer than {keep} would let the queue grow past half a vehicle's load."), {
			passengers = passengersText(data.snapshot.input.waitingMax),
			keep = ui.formatCount(a.keep or count),
		})
	elseif a.trim > 0 then
		parts[#parts + 1] = ui.fill(_("{count} × {load} ÷ {target} = {exact}, so keep {keep}."), {
			count = ui.formatCount(count),
			load = ui.formatPercent(a.load),
			target = ui.formatPercent(a.target),
			exact = ui.formatOneDecimal(count * a.load / a.target),
			keep = ui.formatCount(a.keep),
		})
	end
	if a.trim > 0 then
		parts[#parts + 1] = _("Fewer vehicles means a longer wait, which can cost passengers or cargo.")
	end
	if a.backlog then
		parts[#parts + 1] = _("Passengers are piling up at a stop, so the line needs more vehicles, whatever the average load says.")
	elseif a.verdict == "Busy" then
		parts[#parts + 1] = ui.fill(_("The average load is {busy} or more, so vehicles may leave passengers or cargo behind."),
			{ busy = ui.formatPercent(metrics.BUSY_LOAD) })
	end
	if a.verdict == "Busy" and not a.thinMargin and a.margin ~= nil and a.margin < metrics.THIN_MARGIN then
		parts[#parts + 1] = ui.fill(_("The balance is only {percent} of the running costs: bigger vehicles may pay off better than more of them."),
			{ percent = ui.formatPercent(a.margin) })
	end
	if a.thinMargin then
		parts[#parts + 1] = ui.fill(_("But the balance is only {percent} of the running costs ({costs} last year): another vehicle adds its own running costs and shares the same riders. Bigger or newer vehicles may pay off better."), {
			percent = ui.formatPercent(a.margin),
			costs = ui.formatMoney(data.snapshot.input.runningCostsPerYear),
		})
	end
	if a.verdict == "Ok" and not a.queueLimited then
		parts[#parts + 1] = _("Profitable, and the average load is close to or above the target.")
	end
	return table.concat(parts, "\n")
end

-- Load line (polls the line's current load) ---------------------------------------------------------------------

local record LoadLineParams
	line : Engine.Entity
	load : number
	target : number
end

local LoadLine = react.RegisterRecipe("PgraceTrimTheFatLoadLine", function(params : LoadLineParams) : TreeNodeId
	local nowState = engine_react_util.useStepStateTimer(function() : string
		local ok, loadOrError = pcall(line_data.lineLoadNow, params.line)
		return ok and ui.formatPercent(loadOrError as number) or ui.UNKNOWN
	end, LIVE_POLL_SECONDS)
	-- A load just under the target can round to the same whole percent ("50% (target 50%)") and contradict a
	-- "too many" verdict; show one decimal then.
	local loadText = ui.formatPercent(params.load)
	if params.load ~= nil and params.target ~= nil and params.load < params.target
		and metrics.percent(params.load) == metrics.percent(params.target) then
		loadText = ui.fill(_("{percent}%"), { percent = ui.formatOneDecimal(params.load * 100) })
	end
	return ui.tooltipRow(
		ui.fill(_("Average load {load} (target {target}) · now {now}"), {
			load = loadText,
			target = ui.formatPercent(params.target),
			now = nowState:old(),
		}),
		"font-scale-body",
		_("Average load: items carried in the last 12 months ÷ capacity offered (capacity × departures × stops). A passenger riding several stops counts once, so on lines with many stops this reads lower than seat occupancy.")
	)
end)

-- Vehicle table -------------------------------------------------------------------------------------------------

local NameCell = react.RegisterRecipe("PgraceTrimTheFatNameCell", function(params : Builtin.TableCellParam) : TreeNodeId
	local data = params.userParam as CardData
	local row = data.rows[params.rowKey]
	-- A sold vehicle's row stays until the player refreshes; its buttons would act on a missing entity, or on
	-- whatever reuses its ID (seen in-game: the locate button came back seconds after a sale).
	local existsState = engine_react_util.useStepStateTimer(function() : boolean
		local ok, onLineOrError = pcall(line_data.isOnLine, params.rowKey, data.line)
		return ok and onLineOrError as boolean
	end, 1.0)
	if row == nil then
		return builtin.BoxLayout{ children = {} }
	end
	if not existsState:old() then
		return ui.textRow(row.name, "font-scale-body")
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			line_react_util.LocateButton{ entity = row.entity },
			-- The full name on hover, for long custom names the column clips.
			line_react_util.makeEntityWindowButton(row.name, row.entity, nil, nil, nil, nil, row.name),
		},
	}
end)

local function makeTextCell(name : string, textOf : function(VehicleRow) : string) : Recipe<Builtin.TableCellParam>
	return react.RegisterRecipe(name, function(params : Builtin.TableCellParam) : TreeNodeId
		local data = params.userParam as CardData
		local row = data.rows[params.rowKey]
		return ui.textRow(row ~= nil and textOf(row) or "", "font-scale-body")
	end)
end

local AgeCell = makeTextCell("PgraceTrimTheFatAgeCell", function(row : VehicleRow) : string
	return row.ageText
end)

local BalanceCell = react.RegisterRecipe("PgraceTrimTheFatBalanceCell", function(params : Builtin.TableCellParam) : TreeNodeId
	local data = params.userParam as CardData
	return ui.textRow(data.balanceText[params.rowKey] or "", "font-scale-body")
end)

local LoadCell = react.RegisterRecipe("PgraceTrimTheFatLoadCell", function(params : Builtin.TableCellParam) : TreeNodeId
	local data = params.userParam as CardData
	local entity = params.rowKey
	-- A plain table read (no engine calls, no formatting): cells keep their first userParam and may not re-render
	-- on a re-sort, so this picks up the values frozen at the last header click.
	local textState = engine_react_util.useStepStateTimer(function() : string
		return data.loadText[entity] or ui.UNKNOWN
	end, LIVE_POLL_SECONDS)
	return ui.textRow(textState:old(), "font-scale-body")
end)

-- Starts sorted by balance per year, lowest first: the vehicles to look at first are on top.
-- onSort refreshes the sort values and re-renders, so the table re-sorts on them (as Commuter Compass).
local function makeVehicleTable(data : CardData, onSort : function(integer, boolean)) : TreeNodeId
	local rowKeys : {integer} = {}
	for i, row in ipairs(data.snapshot.vehicles) do
		rowKeys[i] = row.entity
	end
	return builtin.DataTable{
		meta = { localKey = "vehicles_" .. tostring(data.generation) },
		columns = {
			builtin.ColumnDesc{
				name = _("Vehicle"),
				recipe = NameCell,
				weight = 2,
				getCompareValue = function(rowKey : integer) : any
					return data.rows[rowKey].name
				end,
			},
			builtin.ColumnDesc{
				name = _("Age"),
				recipe = AgeCell,
				weight = 0.9,
				getCompareValue = function(rowKey : integer) : any
					return data.rows[rowKey].ageMs
				end,
			},
			builtin.ColumnDesc{
				name = _("Per year"),
				tooltip = _("Balance per year"),
				recipe = BalanceCell,
				weight = 1.1,
				getCompareValue = function(rowKey : integer) : any
					-- Too new to judge sorts after every amount.
					return data.rows[rowKey].balancePerYear or math.huge
				end,
			},
			builtin.ColumnDesc{
				name = _("Load now"),
				tooltip = _("Load when you last clicked a column header. Click any header to update it."),
				recipe = LoadCell,
				weight = 1.1,
				getCompareValue = function(rowKey : integer) : any
					return data.sortLoad[rowKey] or -1
				end,
			},
		},
		rowKeys = rowKeys,
		userParam = data,
		initialSortColumn = { data.sortColumn, data.sortAscending },
		onSortColumnChange = onSort,
	}
end

-- Card body -----------------------------------------------------------------------------------------------------

local record BodyParams
	line : Engine.Entity
end

-- Computed once when the window opens; only the "now" loads update live.
local Body = react.RegisterRecipe("PgraceTrimTheFatBody", function(params : BodyParams) : TreeNodeId
	local dataState = react.useStateLazy(function() : CardData
		return buildCardData(params.line)
	end)
	local data = dataState:old()
	-- Hooks run before any early return, so their order never changes.
	-- Polls the line's vehicles, so the card can offer a refresh after vehicles are bought, sold or replaced.
	-- nil on error.
	local signatureState = engine_react_util.useStepStateTimer(function() : string
		local ok, signatureOrError = pcall(line_data.vehicleSignature, params.line)
		return ok and signatureOrError as string or nil
	end, 1.0)
	-- Bumped on a header click, so the table re-sorts on the fresh sort values right away (as Commuter Compass).
	local sortVersion = react.useStateLazy(function() : integer
		return 0
	end)

	local function onSort(column : integer, ascending : boolean)
		if column == data.sortColumn and ascending == data.sortAscending then
			return
		end
		data.sortColumn, data.sortAscending = column, ascending
		-- Any header click re-reads the loads, then the table re-sorts on them.
		local sortLoad : {integer : number} = {}
		local loadText : {integer : string} = {}
		for entity in pairs(data.rows) do
			local ok, loadOrError = pcall(line_data.vehicleLoadNow, entity)
			local load = ok and loadOrError as number or nil
			sortLoad[entity] = load
			loadText[entity] = ui.formatPercent(load)
		end
		data.sortLoad, data.loadText = sortLoad, loadText
		sortVersion:set(sortVersion:old() + 1)
	end

	if data.error then
		return ui.textRow(_("Error (see log)"), "font-scale-body, negative")
	end
	local a = data.assessment
	local input = data.snapshot.input
	local children : {TreeNodeId} = {}
	local function add(node : TreeNodeId)
		children[#children + 1] = node
	end

	local label, class = verdictLabel(a)
	local tooltip = verdictTooltip(data)
	add(tooltip ~= "" and ui.tooltipRow(label, class, tooltip) or ui.textRow(label, class))
	local signature = signatureState:old()
	if signature ~= nil and signature ~= data.snapshot.signature then
		add(builtin.BoxLayout{
			children = {
				builtin.Button{
					content = builtin.BoxLayout{
						children = {
							builtin.TextView{
								meta = { class = "font-scale-body, warning" },
								text = _("Vehicles changed: click to refresh"),
							},
						},
					},
					onClick = function()
						local fresh = buildCardData(params.line)
						-- Keep the player's sort across the refresh.
						if not fresh.error then
							fresh.sortColumn, fresh.sortAscending = data.sortColumn, data.sortAscending
						end
						dataState:set(fresh)
					end,
				},
			},
		})
	end
	if a.waitingBacklog then
		add(ui.textRow(ui.fill(_("{passengers} waiting at one stop: fewer vehicles would leave more behind."),
			{ passengers = passengersText(input.waitingMax) }), "font-scale-body, warning"))
	end
	if a.fullBacklog then
		-- Both keys stay literal, so both stay translated.
		local template = a.waitingBacklog and _("Full on {percent} of departures from one stop over the last year.")
			or _("Full on {percent} of departures from one stop over the last year: fewer vehicles would leave more behind.")
		add(ui.textRow(ui.fill(template, { percent = ui.formatPercent(a.fullShare) }), "font-scale-body, warning"))
	end
	if a.notDelivering then
		add(ui.textRow(_("Vehicles are full but deliver little: check where the cargo is unloaded."),
			"font-scale-body, warning"))
	end
	if a.changedRecently then
		add(ui.textRow(ui.fill(_("Vehicles changed {age} ago: the numbers still include the old setup."),
			{ age = api.engine.util.formatAge(input.lastChangeMs, input.nowMs) }), "font-scale-body"))
	end
	if a.declining then
		add(ui.textRow(ui.fill(_("Income fell to {recent} a year over the last 3 years, from {before} in the 5 before: check what changed around the line."),
			{ recent = ui.formatMoney(a.trend.recentIncome), before = ui.formatMoney(a.trend.beforeIncome) }),
			"font-scale-body, warning"))
	end
	if a.verdict == "NoVehicles" then
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
	end
	if a.trim > 0 then
		add(ui.textRow(ui.fill(_("Suggestion: remove {vehicles}, one at a time."),
			{ vehicles = ui.vehiclesText(data.snapshot.noun, a.trim) }), "font-scale-body"))
	end
	-- A few weeks of money scaled up to a year would mislead, so TooNew lines skip the money row.
	if a.verdict ~= "TooNew" then
		local values : {string : string} = {
			balance = ui.moneyText(a.balancePerYear, a.annualised),
			profit = ui.moneyText(a.profitPerVehicle, a.annualised),
			vehicles = ui.vehiclesText(data.snapshot.noun, input.vehicleCount),
		}
		-- Both keys stay literal, so both stay translated; the shorter one when the stop count is unknown.
		local template : string
		if input.stopCount ~= nil then
			values.stops = ui.stopsText(input.stopCount)
			template = _("{balance} per year · {profit} per vehicle · {vehicles} · {stops}")
		else
			template = _("{balance} per year · {profit} per vehicle · {vehicles}")
		end
		add(ui.textRow(ui.fill(template, values), "font-scale-body"))
	end
	add(LoadLine{ line = params.line, load = a.load, target = a.target })
	add(makeVehicleTable(data, onSort))

	local anyAnnualised = a.annualised
	for __, row in ipairs(data.snapshot.vehicles) do
		anyAnnualised = anyAnnualised or row.annualised
	end
	if anyAnnualised then
		add(ui.textRow(_("* scaled up to a full year from less than a year of data"), "font-scale-annotation"))
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end)

-- Plugin --------------------------------------------------------------------------------------------------------

local LinePlugin = react.RegisterPluginRecipe(line_eow.LineEowExtensionPoint, "PgraceTrimTheFatLinePlugin", function(params : LineEow.LineWidgetPluginParams) : TreeNodeId
	return builtin.BoxLayout{
		child = content_card.ContentCard{
			title = _("Line efficiency"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(Body, { line = params.entityId } as BodyParams),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	}
end)

-- Only the player's own lines have balances (as the base income graph's condition). Shows on error.
local function isPlayerLine(params : LineEow.LineWidgetPluginParams) : boolean
	local ok, resultOrError = pcall(function() : boolean
		return params.ownershipState ~= "Foreign"
	end)
	return not ok or resultOrError as boolean
end

debugPrint(LOG_PREFIX .. "script loaded")

return {
	LinePlugin = LinePlugin,
	isPlayerLine = isPlayerLine,
}

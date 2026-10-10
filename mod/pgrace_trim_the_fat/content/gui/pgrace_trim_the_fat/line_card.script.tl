local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local line_react_util = ug_require "::/gui/line_vehicle_mgmt/line_react_util.tl" as LineReactUtil
local line_eow = ug_require "::/gui/entity_window/line/line_eow.script.tl" as LineEow
local metrics = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/metrics.tl" as PgraceTrimTheFatMetrics
local line_data = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/line_data.tl" as PgraceTrimTheFatLineData

local LOG_PREFIX = "[trim_the_fat] "
-- Live loads poll this often (AGENTS.md: useStepState runs every frame in every cell).
local LIVE_POLL_SECONDS = 0.25
local UNKNOWN = "—"

local type Assessment = PgraceTrimTheFatMetrics.Assessment
local type LineSnapshot = PgraceTrimTheFatLineData.LineSnapshot
local type VehicleRow = PgraceTrimTheFatLineData.VehicleRow
local type Noun = PgraceTrimTheFatLineData.Noun

-- Text helpers ---------------------------------------------------------------------------------------------------

-- Replaces {name} placeholders; unknown names are left as they are.
local function fill(template : string, values : {string : string}) : string
	return (template:gsub("{(%w+)}", function(key : string) : string
		return values[key] or ("{" .. key .. "}")
	end))
end

local function currentLanguage() : string
	local ok, code = pcall(function() : string
		return app.getUserProfile():getLanguage().code
	end)
	return ok and code as string or "en"
end

local function formatCount(count : integer) : string
	local ok, text = pcall(api.util.lang.formatInt, count)
	if ok and text ~= nil then
		return text as string
	end
	return tostring(count)
end

local function formatMoney(amount : number) : string
	if amount == nil then
		return UNKNOWN
	end
	local rounded = math.floor(amount + 0.5)
	local ok, text = pcall(api.util.formatMoney, rounded)
	if ok and text ~= nil then
		return text as string
	end
	return tostring(rounded)
end

-- Money with "*" when it was scaled up from less than a year (see the table footnote).
local function moneyText(amount : number, annualised : boolean) : string
	return formatMoney(amount) .. (annualised and "*" or "")
end

-- "34%", or as the player's language writes it (German "34 %"); UNKNOWN for nil.
local function formatPercent(fraction : number) : string
	local whole = metrics.percent(fraction)
	if whole == nil then
		return UNKNOWN
	end
	return fill(_("{percent}%"), { percent = tostring(whole) })
end

-- "5.4", with the language's decimal separator.
local function formatOneDecimal(value : number) : string
	local tenths = math.floor(value * 10 + 0.5)
	return fill(_("{integer}.{decimal}"), {
		integer = string.format("%d", math.floor(tenths / 10)),
		decimal = string.format("%d", math.floor(tenths % 10)),
	})
end

-- A count with its noun, in the form the player's language uses for that count. Each form is its own key; mods get
-- no plural-aware gettext, so the rule is ours (metrics.pluralCategory). Copied from Commuter Compass.
local record PluralForms
	one : string
	few : string
	many : string
	other : string
end

local function countText(count : integer, forms : PluralForms) : string
	local category = metrics.pluralCategory(currentLanguage(), count)
	local template = (forms as {string : string})[category] or forms.other
	return fill(template, { count = formatCount(count) })
end

local function stopsText(count : integer) : string
	return countText(count, {
		one = _("{count} stops|one"), few = _("{count} stops|few"),
		many = _("{count} stops|many"), other = _("{count} stops|other"),
	})
end

local function vehiclesText(noun : Noun, count : integer) : string
	if noun == "train" then
		return countText(count, {
			one = _("{count} trains|one"), few = _("{count} trains|few"),
			many = _("{count} trains|many"), other = _("{count} trains|other"),
		})
	elseif noun == "bus" then
		return countText(count, {
			one = _("{count} buses|one"), few = _("{count} buses|few"),
			many = _("{count} buses|many"), other = _("{count} buses|other"),
		})
	elseif noun == "truck" then
		return countText(count, {
			one = _("{count} trucks|one"), few = _("{count} trucks|few"),
			many = _("{count} trucks|many"), other = _("{count} trucks|other"),
		})
	elseif noun == "tram" then
		return countText(count, {
			one = _("{count} trams|one"), few = _("{count} trams|few"),
			many = _("{count} trams|many"), other = _("{count} trams|other"),
		})
	elseif noun == "ship" then
		return countText(count, {
			one = _("{count} ships|one"), few = _("{count} ships|few"),
			many = _("{count} ships|many"), other = _("{count} ships|other"),
		})
	elseif noun == "aircraft" then
		return countText(count, {
			one = _("{count} aircraft|one"), few = _("{count} aircraft|few"),
			many = _("{count} aircraft|many"), other = _("{count} aircraft|other"),
		})
	end
	return countText(count, {
		one = _("{count} vehicles|one"), few = _("{count} vehicles|few"),
		many = _("{count} vehicles|many"), other = _("{count} vehicles|other"),
	})
end

-- Small widgets -------------------------------------------------------------------------------------------------

-- A recipe must return a layout; a bare TextView crashes the whole UI ("Recipe child must be a layout").
local function textRow(text : string, class : string) : TreeNodeId
	return builtin.BoxLayout{
		children = {
			builtin.TextView{ meta = { class = class or "font-scale-body" }, text = text },
		},
	}
end

-- Tooltips only show on buttons, not on a BoxLayout. The click does nothing.
local function tooltipRow(text : string, class : string, tooltip : string) : TreeNodeId
	return builtin.BoxLayout{
		children = {
			builtin.Button{
				meta = { tooltip = tooltip },
				content = builtin.BoxLayout{
					children = {
						builtin.TextView{ meta = { class = class or "font-scale-body" }, text = text },
					},
				},
				onClick = function() end,
			},
		},
	}
end

-- Card data ----------------------------------------------------------------------------------------------------

-- Built once when the window opens and handed to the table as userParam (cells keep their first userParam).
local record CardData
	error : boolean
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
			data.loadText[row.entity] = formatPercent(row.loadNow)
			data.balanceText[row.entity] = moneyText(row.balancePerYear, row.annualised)
		end
		return data
	end)
	if not ok then
		debugPrint(LOG_PREFIX .. "error for line " .. tostring(line) .. ": " .. tostring(dataOrError))
		return { error = true, generation = generation }
	end
	local data = dataOrError as CardData
	line_data.probe(line, data.snapshot, data.assessment) -- PROBE (remove before release)
	return data
end

-- Verdict -------------------------------------------------------------------------------------------------------

local function verdictLabel(verdict : PgraceTrimTheFatMetrics.Verdict) : string, string
	if verdict == "NoVehicles" then
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
	if a.trim > 0 then
		parts[#parts + 1] = fill(_("{count} × {load} ÷ {target} = {exact}, so keep {keep}."), {
			count = formatCount(count),
			load = formatPercent(a.load),
			target = formatPercent(a.target),
			exact = formatOneDecimal(count * a.load / a.target),
			keep = formatCount(a.keep),
		})
		parts[#parts + 1] = _("Fewer vehicles means a longer wait, which can cost passengers or cargo.")
	end
	if a.verdict == "Busy" then
		parts[#parts + 1] = fill(_("The average load is {busy} or more, so vehicles may leave passengers or cargo behind."),
			{ busy = formatPercent(metrics.BUSY_LOAD) })
	end
	if a.verdict == "Ok" then
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
		return ok and formatPercent(loadOrError as number) or UNKNOWN
	end, LIVE_POLL_SECONDS)
	-- A load just under the target can round to the same whole percent ("50% (target 50%)") and contradict a
	-- "too many" verdict; show one decimal then.
	local loadText = formatPercent(params.load)
	if params.load ~= nil and params.target ~= nil and params.load < params.target
		and metrics.percent(params.load) == metrics.percent(params.target) then
		loadText = fill(_("{percent}%"), { percent = formatOneDecimal(params.load * 100) })
	end
	return tooltipRow(
		fill(_("Average load {load} (target {target}) · now {now}"), {
			load = loadText,
			target = formatPercent(params.target),
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
	if row == nil then
		return builtin.BoxLayout{ children = {} }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			line_react_util.LocateButton{ entity = row.entity },
			line_react_util.makeEntityWindowButton(row.name, row.entity),
		},
	}
end)

local function makeTextCell(name : string, textOf : function(VehicleRow) : string) : Recipe<Builtin.TableCellParam>
	return react.RegisterRecipe(name, function(params : Builtin.TableCellParam) : TreeNodeId
		local data = params.userParam as CardData
		local row = data.rows[params.rowKey]
		return textRow(row ~= nil and textOf(row) or "", "font-scale-body")
	end)
end

local AgeCell = makeTextCell("PgraceTrimTheFatAgeCell", function(row : VehicleRow) : string
	return row.ageText
end)

local BalanceCell = react.RegisterRecipe("PgraceTrimTheFatBalanceCell", function(params : Builtin.TableCellParam) : TreeNodeId
	local data = params.userParam as CardData
	return textRow(data.balanceText[params.rowKey] or "", "font-scale-body")
end)

local LoadCell = react.RegisterRecipe("PgraceTrimTheFatLoadCell", function(params : Builtin.TableCellParam) : TreeNodeId
	local data = params.userParam as CardData
	local entity = params.rowKey
	-- A plain table read (no engine calls, no formatting): cells keep their first userParam and may not re-render
	-- on a re-sort, so this picks up the values frozen at the last header click.
	local textState = engine_react_util.useStepStateTimer(function() : string
		return data.loadText[entity] or UNKNOWN
	end, LIVE_POLL_SECONDS)
	return textRow(textState:old(), "font-scale-body")
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
				weight = 1.6,
				getCompareValue = function(rowKey : integer) : any
					return data.rows[rowKey].name
				end,
			},
			builtin.ColumnDesc{
				name = _("Age"),
				recipe = AgeCell,
				weight = 1,
				getCompareValue = function(rowKey : integer) : any
					return data.rows[rowKey].ageMs
				end,
			},
			builtin.ColumnDesc{
				name = _("Per year"),
				tooltip = _("Balance per year"),
				recipe = BalanceCell,
				weight = 1.2,
				getCompareValue = function(rowKey : integer) : any
					return data.rows[rowKey].balancePerYear
				end,
			},
			builtin.ColumnDesc{
				name = _("Load now"),
				tooltip = _("Load when you last clicked a column header. Click any header to update it."),
				recipe = LoadCell,
				weight = 1.4,
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
	-- Polls the vehicle count, so the card can offer a refresh after vehicles are bought or sold. -1 on error.
	local countState = engine_react_util.useStepStateTimer(function() : integer
		local ok, countOrError = pcall(line_data.vehicleCount, params.line)
		return ok and countOrError as integer or -1
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
			loadText[entity] = formatPercent(load)
		end
		data.sortLoad, data.loadText = sortLoad, loadText
		sortVersion:set(sortVersion:old() + 1)
	end

	if data.error then
		return textRow(_("Error (see log)"), "font-scale-body, negative")
	end
	local a = data.assessment
	local input = data.snapshot.input
	local children : {TreeNodeId} = {}
	local function add(node : TreeNodeId)
		children[#children + 1] = node
	end

	local label, class = verdictLabel(a.verdict)
	local tooltip = verdictTooltip(data)
	add(tooltip ~= "" and tooltipRow(label, class, tooltip) or textRow(label, class))
	local count = countState:old()
	if count ~= -1 and count ~= #data.snapshot.vehicles then
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
	if a.verdict == "NoVehicles" then
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
	end
	if a.trim > 0 then
		add(textRow(fill(_("Suggestion: remove {vehicles}, one at a time."),
			{ vehicles = vehiclesText(data.snapshot.noun, a.trim) }), "font-scale-body"))
	end
	-- A few weeks of money scaled up to a year would mislead, so TooNew lines skip the money row.
	if a.verdict ~= "TooNew" then
		local values : {string : string} = {
			balance = moneyText(a.balancePerYear, a.annualised),
			profit = moneyText(a.profitPerVehicle, a.annualised),
			vehicles = vehiclesText(data.snapshot.noun, input.vehicleCount),
		}
		-- Both keys stay literal, so both stay translated; the shorter one when the stop count is unknown.
		local template : string
		if input.stopCount ~= nil then
			values.stops = stopsText(input.stopCount)
			template = _("{balance} per year · {profit} per vehicle · {vehicles} · {stops}")
		else
			template = _("{balance} per year · {profit} per vehicle · {vehicles}")
		end
		add(textRow(fill(template, values), "font-scale-body"))
	end
	add(LoadLine{ line = params.line, load = a.load, target = a.target })
	add(makeVehicleTable(data, onSort))

	local anyAnnualised = a.annualised
	for __, row in ipairs(data.snapshot.vehicles) do
		anyAnnualised = anyAnnualised or row.annualised
	end
	if anyAnnualised then
		add(textRow(_("* scaled up to a full year from less than a year of data"), "font-scale-annotation"))
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

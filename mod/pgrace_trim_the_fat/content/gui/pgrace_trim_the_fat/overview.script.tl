local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local tool_react_util = ug_require "::/gui/main/tool_react_util.tl" as ToolReactUtil
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
local metrics = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/metrics.tl" as PgraceTrimTheFatMetrics
local line_data = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/line_data.tl" as PgraceTrimTheFatLineData
local ui = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/ui.tl" as PgraceTrimTheFatUi
local line_react_util = ug_require "::/gui/line_vehicle_mgmt/line_react_util.tl" as LineReactUtil
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl" as LineUtil
local gui_react_util = ug_require "::/gui/main/gui_react_util.tl" as GuiReactUtil

local LOG_PREFIX = "[trim_the_fat] "
local WINDOW_ID = "pgrace_trim_the_fat_overview"
local BUTTON_ICON = "::/gui/statistics/icons/symbol_configure_line.tga"
local REFRESH_ICON = "::/gui/builtin/window/icons/refresh.tga"
-- F2's class for numeric columns (statistic_lines.tl); overview.css.lua aligns it inside our window.
local RIGHT_ALIGNED = "right-aligned"

local type ToolParam = ToolReactUtil.IToolParam

local type Assessment = PgraceTrimTheFatMetrics.Assessment
local type VerdictKind = PgraceTrimTheFatMetrics.VerdictKind

-- F2's Lines filters, in F2's order.
local record Category
	icon : string
	tooltip : string
	carrier : Carrier
end

local function categories() : {Category}
	local c = api.type["enum"].Carrier
	return {
		{ icon = "::/gui/statistics/icons/vehicle_bus_18.tga", tooltip = _("Show Road Lines"), carrier = c.ROAD },
		{ icon = "::/gui/statistics/icons/vehicle_tram_18.tga", tooltip = _("Show Tram Lines"), carrier = c.TRAM },
		{ icon = "::/gui/statistics/icons/vehicle_train_18.tga", tooltip = _("Show Train Lines"), carrier = c.RAIL },
		{ icon = "::/gui/statistics/icons/vehicle_ship_18.tga", tooltip = _("Show Ship Lines"), carrier = c.WATER },
		{ icon = "::/gui/statistics/icons/vehicle_airplane_18.tga", tooltip = _("Show Air Lines"), carrier = c.AIR },
	}
end

-- One line, computed and formatted once per build; cells only read it.
local record Row
	line : Engine.Entity
	name : string
	error : boolean
	assessment : Assessment
	vehicleCount : integer
	-- matches[i]: the line belongs to categories()[i].
	matches : {integer : boolean}
	verdictText : string
	verdictClass : string
	-- Severity, then balance per year (lower first); errors last.
	verdictSort : number
	balanceText : string
	-- As F2's LineBalance: "negative" below zero, else "positive"; plain for errors and missing data.
	balanceClass : string
	loadText : string
	vehiclesText : string
end

local record OverviewData
	error : boolean
	rows : {integer : Row}
	keys : {integer}
	-- The player's sort, kept across refreshes. Starts on Per year (column 3), lowest first.
	sortColumn : integer
	sortAscending : boolean
	-- Differs per build, so a refresh remounts the table (cells keep their first userParam).
	generation : integer
end

local function verdictText(kind : VerdictKind, a : Assessment) : string, string
	local trim = ui.formatCount(a.trim)
	if kind == "LosingStuck" then
		return _("Losing · not delivering"), "font-scale-body, negative"
	elseif kind == "LosingTrim" then
		return ui.fill(_("Losing money (−{count})"), { count = trim }), "font-scale-body, negative"
	elseif kind == "Losing" then
		return _("Losing money"), "font-scale-body, negative"
	elseif kind == "TooMany" then
		return ui.fill(_("Too many (−{count})"), { count = trim }), "font-scale-body, warning"
	elseif kind == "Busy" then
		return _("Busy"), "font-scale-body, warning"
	elseif kind == "TooNew" then
		return _("Too new"), "font-scale-body"
	elseif kind == "NoVehicles" then
		return _("No vehicles"), "font-scale-body"
	end
	return _("OK"), "font-scale-body, positive"
end

local ERROR_SEVERITY = 7
-- Keeps severity groups apart in one number: balances stay far below this.
local SEVERITY_SCALE = 1e13

local function buildRow(line : Engine.Entity, cats : {Category}) : Row
	local row : Row = { line = line, matches = {}, error = true, balanceClass = "font-scale-body" }
	local nameOk, name = pcall(api.engine.util.getEntityName, line)
	row.name = nameOk and name as string or tostring(line)
	for i, cat in ipairs(cats) do
		local ok, match = pcall(line_util.filterLine, { cat.carrier }, line)
		row.matches[i] = ok and match as boolean
	end
	local ok, err = pcall(function() : boolean
		local facts = line_data.lineInput(line)
		local a = metrics.assess(facts.input)
		local kind = metrics.verdictKind(a)
		row.assessment = a
		row.vehicleCount = facts.input.vehicleCount
		row.verdictText, row.verdictClass = verdictText(kind, a)
		row.verdictSort = metrics.severity(kind) * SEVERITY_SCALE + (a.balancePerYear or 0)
		row.balanceText = ui.moneyText(a.balancePerYear, a.annualised)
		if a.balancePerYear ~= nil then
			row.balanceClass = a.balancePerYear < 0 and "font-scale-body, negative" or "font-scale-body, positive"
		end
		row.loadText = ui.formatPercent(a.load)
		row.vehiclesText = ui.vehiclesText(facts.noun, facts.input.vehicleCount)
		row.error = false
		return true
	end)
	if not ok then
		debugPrint(LOG_PREFIX .. "overview error for line " .. tostring(line) .. ": " .. tostring(err))
		row.verdictText, row.verdictClass = _("Error"), "font-scale-body, negative"
		row.verdictSort = ERROR_SEVERITY * SEVERITY_SCALE
		row.balanceText, row.loadText, row.vehiclesText = ui.UNKNOWN, ui.UNKNOWN, ui.UNKNOWN
	end
	return row
end

local nextGeneration = 0

-- Never throws.
local function buildOverview(cats : {Category}) : OverviewData
	nextGeneration = nextGeneration + 1
	local data : OverviewData = { error = false, rows = {}, keys = {}, sortColumn = 3, sortAscending = true,
		generation = nextGeneration }
	local start = os.clock() -- PROBE (remove before release)
	local ok, err = pcall(function() : boolean
		for __, line in ipairs(line_data.playerLines()) do
			data.rows[line] = buildRow(line, cats)
			data.keys[#data.keys + 1] = line
		end
		return true
	end)
	debugPrint(LOG_PREFIX .. "probe overview " .. tostring(#data.keys) .. " lines in " -- PROBE (remove before release)
		.. tostring(math.floor((os.clock() - start) * 1000 + 0.5)) .. " ms") -- PROBE (remove before release)
	if not ok then
		debugPrint(LOG_PREFIX .. "overview error: " .. tostring(err))
		data.error = true
	end
	return data
end

local LineCell = react.RegisterRecipe("PgraceTrimTheFatOverviewLineCell", function(params : Builtin.TableCellParam) : TreeNodeId
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			line_react_util.ColorWidget{ entity = params.rowKey },
			line_react_util.NameTextView{ entity = params.rowKey, locationButton = true, stackEntityOpen = true },
		},
	}
end)

local VerdictCell = react.RegisterRecipe("PgraceTrimTheFatOverviewVerdictCell", function(params : Builtin.TableCellParam) : TreeNodeId
	local row = (params.userParam as OverviewData).rows[params.rowKey]
	if row == nil then
		return builtin.BoxLayout{ children = {} }
	end
	return ui.textRow(row.verdictText, row.verdictClass)
end)

-- A right-aligned numeric cell, as F2's (react.setStyleClasses("right-aligned")).
local function makeNumberCell(name : string, textOf : function(Row) : string, classOf : function(Row) : string) : Recipe<Builtin.TableCellParam>
	return react.RegisterRecipe(name, function(params : Builtin.TableCellParam) : TreeNodeId
		react.setStyleClasses(RIGHT_ALIGNED)
		local row = (params.userParam as OverviewData).rows[params.rowKey]
		if row == nil then
			return ui.textRow("", "font-scale-body")
		end
		return ui.textRow(textOf(row), classOf ~= nil and classOf(row) or "font-scale-body")
	end)
end

local BalanceCell = makeNumberCell("PgraceTrimTheFatOverviewBalanceCell", function(row : Row) : string
	return row.balanceText
end, function(row : Row) : string
	return row.balanceClass
end)
local LoadCell = makeNumberCell("PgraceTrimTheFatOverviewLoadCell", function(row : Row) : string
	return row.loadText
end, nil)
local VehiclesCell = makeNumberCell("PgraceTrimTheFatOverviewVehiclesCell", function(row : Row) : string
	return row.vehiclesText
end, nil)

local function makeTable(data : OverviewData, visible : {integer : boolean}, filterKey : string,
		onSort : function(integer, boolean)) : TreeNodeId
	local function number(rowKey : integer, field : function(Row) : number, missing : number) : number
		local row = data.rows[rowKey]
		local value = (row ~= nil and not row.error) and field(row) or nil
		return value or missing
	end
	return builtin.DataTable{
		meta = { localKey = "lines_" .. tostring(data.generation) .. "_" .. filterKey },
		columns = {
			builtin.ColumnDesc{ name = _("Line"), recipe = LineCell, weight = 3,
				getCompareValue = function(rowKey : integer) : any return data.rows[rowKey].name end },
			builtin.ColumnDesc{ name = _("Verdict"), recipe = VerdictCell, weight = 2,
				getCompareValue = function(rowKey : integer) : any return data.rows[rowKey].verdictSort end },
			builtin.ColumnDesc{ name = _("Per year"), tooltip = _("Balance per year"), recipe = BalanceCell, weight = 1.2,
				headerStyleClass = RIGHT_ALIGNED,
				getCompareValue = function(rowKey : integer) : any
					return number(rowKey, function(r : Row) : number return r.assessment.balancePerYear end, math.huge)
				end },
			builtin.ColumnDesc{ name = _("Load"), tooltip = _("Average load over the last 12 months"), recipe = LoadCell, weight = 0.8,
				headerStyleClass = RIGHT_ALIGNED,
				getCompareValue = function(rowKey : integer) : any
					return number(rowKey, function(r : Row) : number return r.assessment.load end, -1)
				end },
			builtin.ColumnDesc{ name = _("Vehicles"), recipe = VehiclesCell, weight = 1.2,
				headerStyleClass = RIGHT_ALIGNED,
				getCompareValue = function(rowKey : integer) : any
					return number(rowKey, function(r : Row) : number return r.vehicleCount end, -1)
				end },
		},
		rowKeys = data.keys,
		userParam = data,
		initialSortColumn = { data.sortColumn, data.sortAscending },
		onSortColumnChange = onSort,
		fnUserFilter = function(rowKey : integer) : boolean
			return visible[rowKey] or false
		end,
	}
end

local function summaryText(s : PgraceTrimTheFatMetrics.Summary) : string
	local parts : {string} = {}
	if s.losingCount > 0 then
		parts[#parts + 1] = ui.fill(_("{lines} losing money: {money} per year"),
			{ lines = ui.linesText(s.losingCount), money = ui.formatMoney(s.losingPerYear) })
	end
	if s.tooManyCount > 0 then
		parts[#parts + 1] = ui.fill(_("{lines} with too many vehicles: up to {vehicles} to remove"),
			{ lines = ui.linesText(s.tooManyCount), vehicles = ui.vehiclesText("vehicle", s.trimTotal) })
	end
	if #parts == 0 then
		return _("No lines are losing money or have too many vehicles.")
	end
	return table.concat(parts, " · ")
end

local record OverviewParams
	-- The window's expanded (maximised) state, owned by the window recipe, as F2.
	expanded : boolean
	setExpanded : function(boolean)
end

local Overview = react.RegisterRecipe("PgraceTrimTheFatOverview", function(params : OverviewParams) : TreeNodeId
	local cats = react.useStateLazy(function() : {Category}
		return categories()
	end):old()
	local dataState = react.useStateLazy(function() : OverviewData
		return buildOverview(cats)
	end)
	-- enabled[i] for categories()[i]; all on at first, as F2.
	local enabledState = react.useStateLazy(function() : {integer : boolean}
		local enabled : {integer : boolean} = {}
		for i = 1, #cats do
			enabled[i] = true
		end
		return enabled
	end)
	local data = dataState:old()
	local enabled = enabledState:old()

	local function onSort(column : integer, ascending : boolean)
		data.sortColumn, data.sortAscending = column, ascending
	end

	local function refresh()
		local fresh = buildOverview(cats)
		fresh.sortColumn, fresh.sortAscending = data.sortColumn, data.sortAscending
		dataState:set(fresh)
	end

	-- F2's category filter (statistics_react_util.createCarrierCategoryFilter): small toggles with an 18 px icon,
	-- class "category", inside a box of class "filter".
	local filterButtons : {TreeNodeId} = {}
	local filterKey = ""
	for i, cat in ipairs(cats) do
		filterKey = filterKey .. (enabled[i] and "1" or "0")
		filterButtons[#filterButtons + 1] = builtin.ToggleButton{
			meta = { tooltip = cat.tooltip },
			value = enabled[i] and 1 or 0,
			content = builtin.ImageView{
				meta = { class = "category" },
				path = cat.icon,
				scaling = builtin.type.ImageViewScaling.AutoFit,
			},
			onValueChange = function(value : integer)
				local next : {integer : boolean} = {}
				for j = 1, #cats do
					next[j] = enabled[j]
				end
				next[i] = value == 1
				enabledState:set(next)
			end,
		}
	end
	-- Where F2 has its eye toggle: a flat icon button, spaced off like the eye.
	filterButtons[#filterButtons + 1] = builtin.Button{
		meta = { class = "refresh", tooltip = _("Recalculate every line") },
		content = builtin.ImageView{
			meta = { class = "category" },
			path = REFRESH_ICON,
			scaling = builtin.type.ImageViewScaling.AutoFit,
		},
		onClick = refresh,
	}

	-- F2's expand toggle (statistics.tl): the stylesheet gives the expanded window most of the screen height.
	local expandButton = builtin.ToggleButton{
		meta = { class = "expand", tooltip = params.expanded and _("Shrink") or _("Expand") },
		value = params.expanded and 1 or 0,
		content = builtin.ImageView{
			path = params.expanded and "::/gui/builtin/window/icons/symbol_minimize_18.tga"
				or "::/gui/builtin/window/icons/symbol_maximize_18.tga",
		},
		onValueChange = function(value : integer)
			params.setExpanded(value == 1)
		end,
	}

	local toolbar = builtin.BoxLayout{
		meta = { class = "look-up" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					builtin.BoxLayout{
						meta = { class = "filter" },
						orientation = builtin.type.Orientation.Horizontal,
						children = filterButtons,
					},
					gui_react_util.makeHorizontalSpacer(),
					builtin.BoxLayout{
						meta = { class = "filter" },
						orientation = builtin.type.Orientation.Horizontal,
						children = { expandButton },
					},
				},
			},
		},
	}

	local body : {TreeNodeId} = {}
	if data.error then
		body[#body + 1] = ui.textRow(_("Error (see log)"), "font-scale-body, negative")
	elseif #data.keys == 0 then
		body[#body + 1] = ui.textRow(_("No lines yet."), "font-scale-body")
	else
		local visible : {integer : boolean} = {}
		local shown : {Assessment} = {}
		local anyAnnualised = false
		for line, row in pairs(data.rows) do
			local match = false
			for i = 1, #cats do
				match = match or (enabled[i] and row.matches[i])
			end
			visible[line] = match
			if match and not row.error then
				shown[#shown + 1] = row.assessment
				anyAnnualised = anyAnnualised or row.assessment.annualised
			end
		end
		body[#body + 1] = ui.textRow(summaryText(metrics.summarise(shown)), "font-scale-annotation")
		body[#body + 1] = makeTable(data, visible, filterKey, onSort)
		if anyAnnualised then
			body[#body + 1] = ui.textRow(_("* scaled up to a full year from less than a year of data"), "font-scale-annotation")
		end
	end

	-- F2's layout (StatisticsContainer): a tab widget filling the window, here with our one tab, and the toolbar
	-- floated over the tab row's right end.
	return builtin.FloatingLayout{
		children = {
			builtin.FloatingLayoutChild{
				localKey = "tabs",
				h = -1,
				v = -1,
				item = builtin.TabWidget{
					orientation = builtin.type.TabOrientation.North,
					deselectAllowed = false,
					value = "overview",
					onValueChange = function(__ : integer|number|string) end,
					tabs = {
						builtin.TabWidgetChild{
							localKey = "overview",
							value = "overview",
							indicator = builtin.TextView{ meta = { class = "font-scale-tab-widget-indicator" }, text = _("Trim the Fat") },
							item = builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = body },
						},
					},
				},
			},
			builtin.FloatingLayoutChild{
				localKey = "toolbar",
				h = 1.0,
				v = 0.0,
				item = toolbar,
			},
		},
	}
end)

local OverviewWindow = react.RegisterWrapperRecipe("PgraceTrimTheFatOverviewWindow", builtin.Window, function(params : ToolReactUtil.IToolWindowParam<ToolParam>) : TreeNodeId
	local expandedState = react.useState(false) as ReactStateT<boolean>
	-- Size, position and animations come from overview.css.lua, by this class: F2's rules for its window.
	return builtin.Window{
		meta = { class = "pgrace-trim-the-fat-overview" },
		id = WINDOW_ID,
		title = _("Trim the Fat"),
		closable = true,
		-- As F2: no title bar (the close button overlaps the content's top-right corner), docked, not movable.
		compact = true,
		movable = false,
		onClose = params.onClose,
		expanded = expandedState:old(),
		content = Overview{
			expanded = expandedState:old(),
			setExpanded = function(expanded : boolean)
				expandedState:set(expanded)
			end,
		},
	}
end)

local OverviewTool = tool_react_util.registerToolWithWindow("PgraceTrimTheFatOverview", WINDOW_ID, OverviewWindow)

-- The tool machinery only reads gameCtx.windowContainer (and the button its tool stack); the mod-area plugin gets
-- no gameCtx, so build one from the game's defaults.
local function makeToolParam() : ToolParam
	local gameCtx = {
		windowContainer = game_react_globals.getDefaultWindowContainer(),
		toolStack = game_react_globals.getDefaultToolStack(),
	} as GameContext
	return { gameCtx = gameCtx }
end

local OverviewButton = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "PgraceTrimTheFatOverviewButton", function() : TreeNodeId
	return builtin.BoxLayout{
		children = {
			builtin.ToolButton{
				meta = { tooltip = _("Trim the Fat: all lines") },
				toolDefinition = OverviewTool,
				toolStack = game_react_globals.getDefaultToolStack(),
				content = builtin.ImageView{
					path = BUTTON_ICON,
					scaling = builtin.type.ImageViewScaling.AutoFit,
				},
				showFn = function()
					local ok, err = pcall(function() : boolean
						game_react_globals.getDefaultToolStackApi().push(OverviewTool, nil, makeToolParam())
						return true
					end)
					if not ok then
						debugPrint(LOG_PREFIX .. "open failed: " .. tostring(err))
					end
				end,
				hideFn = function()
					pcall(function() : boolean
						game_react_globals.getDefaultToolStackApi().pop(OverviewTool, nil)
						return true
					end)
				end,
			},
		},
	}
end)

return {
	OverviewButton = OverviewButton,
}

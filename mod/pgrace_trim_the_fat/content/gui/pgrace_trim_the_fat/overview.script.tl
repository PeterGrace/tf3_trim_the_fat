local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local tool_react_util = ug_require "::/gui/main/tool_react_util.tl" as ToolReactUtil
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
local metrics = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/metrics.tl" as PgraceTrimTheFatMetrics
local line_data = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/line_data.tl" as PgraceTrimTheFatLineData
local ui = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/ui.tl" as PgraceTrimTheFatUi

local LOG_PREFIX = "[trim_the_fat] "
local WINDOW_ID = "pgrace_trim_the_fat.overview"
local BUTTON_ICON = "::/gui/statistics/icons/symbol_configure_line.tga"

local type ToolParam = ToolReactUtil.IToolParam

-- PROBE (remove before release): how long assessing every line takes on the player's save.
local function probeAllLines() : string
	local start = os.clock()
	local lines = line_data.playerLines()
	local failed = 0
	for __, line in ipairs(lines) do
		local ok = pcall(function() : boolean
			metrics.assess(line_data.lineInput(line).input)
			return true
		end)
		if not ok then
			failed = failed + 1
		end
	end
	local ms = math.floor((os.clock() - start) * 1000 + 0.5)
	local text = tostring(#lines) .. " lines, " .. tostring(failed) .. " failed, " .. tostring(ms) .. " ms"
	debugPrint(LOG_PREFIX .. "probe overview " .. text)
	return text
end

local Overview = react.RegisterRecipe("PgraceTrimTheFatOverview", function() : TreeNodeId
	local textState = react.useStateLazy(function() : string
		local ok, textOrError = pcall(probeAllLines)
		if not ok then
			debugPrint(LOG_PREFIX .. "overview error: " .. tostring(textOrError))
			return _("Error (see log)")
		end
		return textOrError as string
	end)
	return ui.textRow(textState:old(), "font-scale-body")
end)

local OverviewWindow = react.RegisterWrapperRecipe("PgraceTrimTheFatOverviewWindow", builtin.Window, function(params : ToolReactUtil.IToolWindowParam<ToolParam>) : TreeNodeId
	return builtin.Window{
		id = WINDOW_ID,
		title = _("Trim the Fat"),
		closable = true,
		onClose = params.onClose,
		content = Overview(),
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

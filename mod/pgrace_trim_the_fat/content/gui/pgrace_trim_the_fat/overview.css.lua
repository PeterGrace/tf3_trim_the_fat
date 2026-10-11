local ssu = require "::/gui/main/stylesheetutil.lua"

-- Copies the F2 Statistics window's rules (base gui/statistics/statistics.css.lua), keyed on our window's class and
-- our content recipe, so other windows are unaffected.
function data()
	local result = {}
	local a = ssu.makeAdder(result)

	-- The window. Matched by its class with a font prefix, as the base map editor window: an id selector
	-- ("#pgrace_trim_the_fat.overview") didn't apply in-game, and the window shrank to its content.
	-- Docked bottom-centre, kept clear of the game bar; F2's animations are referenced by name.
	local window = "Window!pgrace-trim-the-fat-overview"
	a(window, {
		gravity = { 0.5, 1.0 },
		anchorPoint = { 0.5, 1.0 },
		padding = { 0, 0, 64, 0 },

		animationName = "open-statistics",
		animationIterationCount = 1,
		animationDuration = 0.2,
		animationTimingFunction = "EaseOutSine",
	})
	a(window .. "!window-expanded", {
		animationName = "expand-statistics",
		animationIterationCount = 1,
		animationDuration = 0.25,
		animationTimingFunction = "EaseOutSine",
	})
	a(window .. "!window-collapsed", {
		animationName = "collapse-statistics",
		animationIterationCount = 1,
		animationDuration = 0.25,
		animationTimingFunction = "EaseOutSine",
	})
	a(window .. " Window::Content", {
		padding = { 8, 8, 12, 8 },
	})

	local sizes = {
		["!font-small"] = { collapsed = { "80vw", 380 }, expanded = { "80vw", "80vh" } },
		["!font-medium"] = { collapsed = { "90vw", 380 }, expanded = { "90vw", "85vh" } },
		["!font-large"] = { collapsed = { "96vw", 380 }, expanded = { "96vw", "90vh" } },
	}
	for font, size in pairs(sizes) do
		a(font .. " " .. window, {
			size = size.collapsed,
		})
		a(font .. " " .. window .. "!window-expanded", {
			size = size.expanded,
		})
	end

	-- The content (F2: R::StatisticsContainer).
	local root = "R::PgraceTrimTheFatOverview"

	-- Let the table fill the window.
	a(root .. " Table", {
		gravity = { -1, -1 },
		margin = { 0, 0, 0, 0 },
	})
	a("!font-medium " .. root .. " Table", {
		margin = { 0, 0, 8, 0 },
	})
	a("!font-large " .. root .. " Table", {
		margin = { 0, 0, 12, 0 },
	})
	a(root .. " Table::Layout", {
		gravity = { -1, -1 },
	})

	-- The toolbar: filter toggles, refresh, expand.
	a(root .. " !look-up", {
		innerSpacing = { 16, 16 },
	})
	a(root .. " !look-up BoxLayout", {
		innerSpacing = { 2, 2 },
	})
	a(root .. " !filter ToggleButton", {
		padding = { 0, 0, 0, 0 },
	})
	a(root .. " !filter Button", {
		padding = { 0, 0, 0, 0 },
	})
	a(root .. " !filter ImageView!category", {
		padding = { 6, 6, 6, 6 },
	})
	-- Text toggles for the verdict filters: as tall as the icon toggles (6 + 18 + 6).
	a(root .. " !filter ToggleButton!verdict", {
		padding = { 4, 8, 4, 8 },
	})
	-- Spaced off the filters as F2's eye toggle.
	a(root .. " !filter !refresh", {
		margin = { 0, 0, 0, 12 },
	})
	-- F2's search field (R::StatisticsContainer !search); folded with a controller, as F2.
	a(root .. " !search", {
		size = { 300, 22 },
		gravity = { -1, 0.5 },
	})
	a("!input-controller " .. root .. " !search", {
		visibility = "folded",
	})
	a(root .. " !expand", {
		padding = { 6, 6, 6, 6 },
		margin = { 0, 32, 0, 0 }, -- leave space for the close button (which overlaps due to compact mode)
	})
	a("!input-controller " .. root .. " !expand", {
		margin = { 0, 12, 0, 0 },
	})
	a(root .. " ToggleButton!expand ImageView", {
		padding = { 6, 6, 6, 6 },
	})

	-- Right-aligned numeric columns: cells with react.setStyleClasses("right-aligned") and headers with
	-- headerStyleClass = "right-aligned".
	a(root .. " !table-item!right-aligned TextView, "
		.. root .. " DataTable::HeaderItem !right-aligned, "
		.. root .. " DataTable::HeaderItem !right-aligned TextView", {
		gravity = { -1, -1 },
		textAlignment = { 1, 0.5 },
	})

	-- Our own pin in the Line column, placed as the base table places its LocateButton (line_react_util.css.lua).
	a("Table::TableLayout R::PgraceTrimTheFatLocateButton Button", {
		gravity = { 0, -1 },
	})

	return result
end

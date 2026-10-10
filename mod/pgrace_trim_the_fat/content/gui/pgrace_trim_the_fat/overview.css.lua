local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = {}
	local a = ssu.makeAdder(result)

	-- Matched by the window's class with a font prefix, as the base map editor window: an id selector
	-- ("#pgrace_trim_the_fat.overview") didn't apply in-game, and the window shrank to its content.
	local window = "Window!pgrace-trim-the-fat-overview"
	a(window, {
		gravity = { 0.5, 0.5 },
		anchorPoint = { 0.5, 0.5 },
	})
	a(window .. " Window::Content", {
		padding = { 8, 8, 12, 8 },
	})
	for __, font in ipairs({ "!font-small", "!font-medium", "!font-large" }) do
		a(font .. " " .. window, {
			size = { "70vw", "70vh" },
		})
		-- Leaves room for the game bar below and the buttons above.
		a(font .. " " .. window .. "!window-expanded", {
			size = { "98vw", "86vh" },
		})
	end

	-- Let the table fill the window, as F2 does (R::StatisticsContainer Table).
	a("R::PgraceTrimTheFatOverview Table", {
		gravity = { -1, -1 },
	})
	a("R::PgraceTrimTheFatOverview Table::Layout", {
		gravity = { -1, -1 },
	})

	return result
end

local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = {}
	local a = ssu.makeAdder(result)

	a("#pgrace_trim_the_fat.overview Window::Content", {
		padding = { 8, 8, 12, 8 },
	})
	a("#pgrace_trim_the_fat.overview", {
		size = { "70vw", "75vh" },
	})

	-- Let the table fill the window, as F2 does (R::StatisticsContainer Table).
	a("R::PgraceTrimTheFatOverview Table", {
		gravity = { -1, -1 },
	})
	a("R::PgraceTrimTheFatOverview Table::Layout", {
		gravity = { -1, -1 },
	})

	return result
end

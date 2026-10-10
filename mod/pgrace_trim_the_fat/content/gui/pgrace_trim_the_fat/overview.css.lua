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

	return result
end

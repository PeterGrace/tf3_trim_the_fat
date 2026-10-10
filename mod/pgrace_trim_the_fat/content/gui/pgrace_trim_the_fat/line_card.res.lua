function data()
	return {
		type = "react-plugin ::LineEowExtensionPoint",
		data = {
			filePath = "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/line_card.script@LinePlugin",
			condition = "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/line_card.script@isPlayerLine",
			-- Between the line's vehicle list (50) and its income graph (60).
			order = 55,
		}
	}
end

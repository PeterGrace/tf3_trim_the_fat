local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local metrics = ug_require "pgrace_trim_the_fat::/gui/pgrace_trim_the_fat/metrics.tl" as PgraceTrimTheFatMetrics

local ui : PgraceTrimTheFatUi = {}

ui.UNKNOWN = "—"

local type Noun = PgraceTrimTheFatLineData.Noun

-- Replaces {name} placeholders; unknown names are left as they are.
function ui.fill(template : string, values : {string : string}) : string
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

function ui.formatCount(count : integer) : string
	local ok, text = pcall(api.util.lang.formatInt, count)
	if ok and text ~= nil then
		return text as string
	end
	return tostring(count)
end

function ui.formatMoney(amount : number) : string
	if amount == nil then
		return ui.UNKNOWN
	end
	local rounded = math.floor(amount + 0.5)
	local ok, text = pcall(api.util.formatMoney, rounded)
	if ok and text ~= nil then
		return text as string
	end
	return tostring(rounded)
end

-- Money with "*" when it was scaled up from less than a year (see the table footnote).
function ui.moneyText(amount : number, annualised : boolean) : string
	return ui.formatMoney(amount) .. (annualised and "*" or "")
end

-- "34%", or as the player's language writes it (German "34 %"); UNKNOWN for nil.
function ui.formatPercent(fraction : number) : string
	local whole = metrics.percent(fraction)
	if whole == nil then
		return ui.UNKNOWN
	end
	return ui.fill(_("{percent}%"), { percent = tostring(whole) })
end

-- "5.4", with the language's decimal separator.
function ui.formatOneDecimal(value : number) : string
	local tenths = math.floor(value * 10 + 0.5)
	return ui.fill(_("{integer}.{decimal}"), {
		integer = string.format("%d", math.floor(tenths / 10)),
		decimal = string.format("%d", math.floor(tenths % 10)),
	})
end

-- A count with its noun, in the form the player's language uses for that count. Each form is its own key; mods get
-- no plural-aware gettext, so the rule is ours (metrics.pluralCategory). Copied from Commuter Compass.
function ui.countText(count : integer, forms : PgraceTrimTheFatUi.PluralForms) : string
	local category = metrics.pluralCategory(currentLanguage(), count)
	local template = (forms as {string : string})[category] or forms.other
	return ui.fill(template, { count = ui.formatCount(count) })
end

function ui.stopsText(count : integer) : string
	return ui.countText(count, {
		one = _("{count} stops|one"), few = _("{count} stops|few"),
		many = _("{count} stops|many"), other = _("{count} stops|other"),
	})
end

function ui.vehiclesText(noun : Noun, count : integer) : string
	if noun == "train" then
		return ui.countText(count, {
			one = _("{count} trains|one"), few = _("{count} trains|few"),
			many = _("{count} trains|many"), other = _("{count} trains|other"),
		})
	elseif noun == "bus" then
		return ui.countText(count, {
			one = _("{count} buses|one"), few = _("{count} buses|few"),
			many = _("{count} buses|many"), other = _("{count} buses|other"),
		})
	elseif noun == "truck" then
		return ui.countText(count, {
			one = _("{count} trucks|one"), few = _("{count} trucks|few"),
			many = _("{count} trucks|many"), other = _("{count} trucks|other"),
		})
	elseif noun == "tram" then
		return ui.countText(count, {
			one = _("{count} trams|one"), few = _("{count} trams|few"),
			many = _("{count} trams|many"), other = _("{count} trams|other"),
		})
	elseif noun == "ship" then
		return ui.countText(count, {
			one = _("{count} ships|one"), few = _("{count} ships|few"),
			many = _("{count} ships|many"), other = _("{count} ships|other"),
		})
	elseif noun == "aircraft" then
		return ui.countText(count, {
			one = _("{count} aircraft|one"), few = _("{count} aircraft|few"),
			many = _("{count} aircraft|many"), other = _("{count} aircraft|other"),
		})
	end
	return ui.countText(count, {
		one = _("{count} vehicles|one"), few = _("{count} vehicles|few"),
		many = _("{count} vehicles|many"), other = _("{count} vehicles|other"),
	})
end

-- Small widgets -------------------------------------------------------------------------------------------------

-- A recipe must return a layout; a bare TextView crashes the whole UI ("Recipe child must be a layout").
function ui.textRow(text : string, class : string) : TreeNodeId
	return builtin.BoxLayout{
		children = {
			builtin.TextView{ meta = { class = class or "font-scale-body" }, text = text },
		},
	}
end

-- Tooltips only show on buttons, not on a BoxLayout. The click does nothing.
function ui.tooltipRow(text : string, class : string, tooltip : string) : TreeNodeId
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

return ui

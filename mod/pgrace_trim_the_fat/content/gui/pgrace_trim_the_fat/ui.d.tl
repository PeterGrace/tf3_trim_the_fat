-- Text and small widgets shared by the line card and the overview. Uses the mod's _() translations.
global record PgraceTrimTheFatUi
	-- One key per plural form; metrics.pluralCategory picks one.
	record PluralForms
		one : string
		few : string
		many : string
		other : string
	end

	-- Shown for unknown values.
	UNKNOWN : string

	-- Replaces {name} placeholders; unknown names are left as they are.
	fill : function(template : string, values : {string : string}) : string
	formatCount : function(count : integer) : string
	-- UNKNOWN for nil.
	formatMoney : function(amount : number) : string
	-- Money with "*" when it was scaled up from less than a year.
	moneyText : function(amount : number, annualised : boolean) : string
	-- "34%" as the player's language writes it; UNKNOWN for nil.
	formatPercent : function(fraction : number) : string
	-- "5.4" with the language's decimal separator.
	formatOneDecimal : function(value : number) : string
	countText : function(count : integer, forms : PluralForms) : string
	stopsText : function(count : integer) : string
	vehiclesText : function(noun : PgraceTrimTheFatLineData.Noun, count : integer) : string
	-- A layout holding one TextView (a recipe must return a layout).
	textRow : function(text : string, class : string) : TreeNodeId
	-- Like textRow, with a tooltip (tooltips only show on buttons; the click does nothing).
	tooltipRow : function(text : string, class : string, tooltip : string) : TreeNodeId
end

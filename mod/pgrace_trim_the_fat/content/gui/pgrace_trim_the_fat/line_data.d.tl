-- Reads one line from the engine. The only module that calls api.engine.
global record PgraceTrimTheFatLineData
	-- What the line's vehicles are called in the verdict text.
	enum Noun
		"train"
		"bus"
		"truck"
		"tram"
		"ship"
		"aircraft"
		"vehicle"
	end

	record VehicleRow
		entity : Engine.Entity
		name : string
		-- Localised age ("2 years 3 months"), from api.engine.util.formatAge.
		ageText : string
		ageMs : number
		-- Last 12 months' balance, scaled to a year when the vehicle is younger than that.
		balancePerYear : number
		annualised : boolean
		-- Cargo on board ÷ capacity when the snapshot was taken; nil without capacity.
		loadNow : number
	end

	record LineSnapshot
		input : PgraceTrimTheFatMetrics.LineInput
		vehicles : {VehicleRow}
		noun : Noun
	end

	snapshot : function(line : Engine.Entity) : LineSnapshot
	-- Cargo on board ÷ capacity across the line's vehicles right now; nil without capacity.
	lineLoadNow : function(line : Engine.Entity) : number
	-- Cargo on board ÷ capacity of one vehicle right now; nil without capacity.
	vehicleLoadNow : function(vehicle : Engine.Entity) : number
	-- PROBE (remove before release): logs the raw inputs for calibration.
	probe : function(line : Engine.Entity, snap : LineSnapshot, assessment : PgraceTrimTheFatMetrics.Assessment)
end

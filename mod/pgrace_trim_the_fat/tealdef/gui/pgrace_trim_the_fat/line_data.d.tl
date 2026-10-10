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
		-- Last 12 months' balance, scaled to a year when it has less than a year of history (not the same as age:
		-- a replaced vehicle keeps its history but its age restarts).
		-- Per-vehicle journal (the statistics window's convention); rows need not sum to the line's balance, which
		-- uses the line's own journal like the line window.
		balancePerYear : number
		annualised : boolean
		-- Cargo on board ÷ capacity when the snapshot was taken; nil without capacity.
		-- Value at snapshot time; the UI seeds its cell with it, then polls vehicleLoadNow.
		loadNow : number
	end

	record LineSnapshot
		input : PgraceTrimTheFatMetrics.LineInput
		vehicles : {VehicleRow}
		-- vehicleSignature at snapshot time.
		signature : string
		noun : Noun
	end

	snapshot : function(line : Engine.Entity) : LineSnapshot
	-- Cargo on board ÷ capacity across the line's vehicles right now; nil without capacity.
	lineLoadNow : function(line : Engine.Entity) : number
	-- Cargo on board ÷ capacity of one vehicle right now; nil without capacity.
	vehicleLoadNow : function(vehicle : Engine.Entity) : number
	-- The line's vehicles and their purchase times; differs from snapshot.signature once vehicles are bought, sold
	-- or replaced.
	vehicleSignature : function(line : Engine.Entity) : string
end

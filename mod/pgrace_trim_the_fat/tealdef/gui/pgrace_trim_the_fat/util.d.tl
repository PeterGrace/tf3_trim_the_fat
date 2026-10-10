-- Pure helpers (no api.* calls), so tests/util_test.lua can run them in plain Lua.
global record PgraceTrimTheFatUtil
	-- "Hello, <name>!", or "Hello!" when the name is empty.
	greet : function(name : string) : string
end

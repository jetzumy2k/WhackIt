--!strict
--[[
	Boots folders of ModuleScripts (server Services/Controllers, client Controllers)
	in two phases: every module's init() runs before any module's start(), so
	start() may safely call into other modules. Within a folder, modules load in
	name order so every server boots identically.

	Module contract: return a table with optional `init: () -> ()` (must not
	yield; wire up state and connections) and `start: () -> ()` (may yield).
]]

export type Module = {
	init: (() -> ())?,
	start: (() -> ())?,
}

type LoadedModule = {
	name: string,
	module: Module,
}

local Lifecycle = {}

local function loadFolder(folder: Instance): { LoadedModule }
	local scripts: { ModuleScript } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(scripts, child)
		end
	end
	table.sort(scripts, function(a: ModuleScript, b: ModuleScript): boolean
		return a.Name < b.Name
	end)

	local loaded: { LoadedModule } = {}
	for _, moduleScript in scripts do
		-- The module set is discovered at runtime, so the require can't be typed statically.
		local result = (require :: any)(moduleScript)
		if typeof(result) ~= "table" then
			error(string.format("[Lifecycle] %s must return a table", moduleScript:GetFullName()))
		end
		table.insert(loaded, { name = moduleScript:GetFullName(), module = result :: Module })
	end
	return loaded
end

-- Folders boot in the order given (e.g. Services before Controllers).
function Lifecycle.boot(folders: { Instance }): ()
	local loaded: { LoadedModule } = {}
	for _, folder in folders do
		for _, entry in loadFolder(folder) do
			table.insert(loaded, entry)
		end
	end

	-- init errors propagate: a half-initialised game must not start.
	for _, entry in loaded do
		local init = entry.module.init
		if init then
			init()
		end
	end

	-- Each start() runs in its own thread so one yielding module can't stall the rest.
	for _, entry in loaded do
		local start = entry.module.start
		if start then
			task.spawn(start)
		end
	end
end

return Lifecycle

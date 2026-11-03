local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)

return function(T)
	T.test("every ready game has something to show at the table", function()
		local boards = ServerScriptService.Server.Tables.Boards
		for _, entry in GameCatalog.entries do
			if entry.status == "ready" then
				local listed = Config.Boards3D[entry.id] or Config.TableScenes[entry.id]
				T.ok(listed, `{entry.id} isn't in Config.Boards3D or Config.TableScenes`)
				T.ok(boards:FindFirstChild(entry.module) ~= nil, `no server/Tables/Boards/{entry.module}.luau`)
			end
		end
	end)

	T.test("games played on the table have an input handler", function()
		local handlers = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Table3D
		for id in Config.Boards3D do
			local entry = GameCatalog.get(id)
			T.ok(entry ~= nil and handlers:FindFirstChild(entry.module) ~= nil, `no client/Table3D/{id}.luau`)
		end
	end)

	T.test("there are enough tables for every seat count", function()
		local biggest = 0
		for _, spec in Config.DefaultTables do
			biggest = math.max(biggest, if spec.shape == "Round8" then 8 else 4)
		end
		for _, entry in GameCatalog.entries do
			T.ok(entry.maxSeats <= biggest, `{entry.id} needs a {entry.maxSeats}-seat table`)
		end
	end)
end

-- No z-fighting anywhere: every model the game builds from parts (lobby, tables, pieces,
-- each game's table scene mid-game and at the end) must have no two visible faces in the
-- same place facing the same way. See src/server/Lobby/Overlaps.luau for what counts.
-- To see the full list while fixing: node tools/run-tests.mjs --run OverlapReport
local Overlaps = require(game:GetService("ServerScriptService").Server.Lobby.Overlaps)
local ModelScenes = require(game:GetService("Tests").ModelScenes)

return function(T)
	local function check(scenes: { any })
		local problems = {}
		for _, scene in scenes do
			for _, hit in Overlaps.find(scene.root) do
				if #problems < 8 then
					table.insert(problems, `{scene.name}: {Overlaps.describe(hit, scene.root)}`)
				end
			end
		end
		T.ok(#problems == 0, "faces fight (flicker):\n        " .. table.concat(problems, "\n        "))
	end

	T.test("tables and stools have no overlapping faces", function()
		check(ModelScenes.furniture())
	end)

	T.test("pieces have no overlapping faces, big or small", function()
		check(ModelScenes.pieces())
	end)

	T.test("the lobby room has no overlapping faces", function()
		check(ModelScenes.lobby())
	end)

	T.test("every game's table scene has no overlapping faces", function()
		check(ModelScenes.games())
	end)

	T.test("the checker catches two boxes sharing a face", function()
		local root = Instance.new("Model")
		for i, color in { Color3.new(1, 0, 0), Color3.new(0, 0, 1) } do
			local p = Instance.new("Part")
			p.Size = Vector3.new(2, 1, 2)
			p.CFrame = CFrame.new(i * 0.5, 0, 0) -- overlapping, tops in one plane
			p.Color = color
			p.Parent = root
		end
		T.ok(#Overlaps.find(root) > 0, "missed a shared top face")
		local fixed, left = Overlaps.fix(root)
		T.ok(fixed > 0 and left == 0, `fix left {left}`)
	end)
end

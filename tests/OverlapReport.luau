-- Prints every z-fighting overlap in the code-built models.
--   node tools/run-tests.mjs --run OverlapReport            (everything)
--   node tools/run-tests.mjs --run OverlapReport lobby      (furniture|pieces|lobby|games)
--   node tools/run-tests.mjs --run OverlapReport games Chess
local Tests = game:GetService("Tests")
local Overlaps = require(game:GetService("ServerScriptService").Server.Lobby.Overlaps)
local ModelScenes = require(Tests.ModelScenes)

return function(args: { string })
	local which, only = args[1], args[2]
	local ok, scenes = xpcall(function()
		return if which then (ModelScenes :: any)[which](only) else ModelScenes.all()
	end, debug.traceback)
	if not ok then
		print(scenes)
		return 1
	end
	local total = 0
	for _, scene in scenes do
		local hits = Overlaps.find(scene.root)
		print(`{scene.name}: {#Overlaps.parts(scene.root)} parts, {#hits} overlaps`)
		for _, hit in hits do
			print(`  {Overlaps.describe(hit, scene.root)}`)
		end
		total += #hits
	end
	print(`\n{total} overlaps`)
	return 0
end

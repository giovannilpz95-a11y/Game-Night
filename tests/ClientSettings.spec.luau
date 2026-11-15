local ServerScriptService = game:GetService("ServerScriptService")
local ClientSettings = require(ServerScriptService.Server.Core.ClientSettings)
local Profile = require(ServerScriptService.Server.Core.Profile)

return function(T)
	T.test("defaults are the first choice of each field", function()
		local state = ClientSettings.new()
		for key, allowed in ClientSettings.Choices do
			T.eq((state :: any)[key], allowed[1])
		end
		T.eq(state.invertY, false)
		T.eq(state.reduceMotion, false)
		T.eq(state.lookSpeed, 1)
	end)

	T.test("apply takes valid fields and ignores junk", function()
		local state = ClientSettings.new()
		T.eq(ClientSettings.apply(state, { graphics = "low", camera = "calm" }), true)
		T.eq(state.graphics, "low")
		T.eq(state.camera, "calm")
		T.eq(ClientSettings.apply(state, { graphics = "low" }), false)
		for _, junk in { "ultra", 5, true, {}, "" } do
			T.eq(ClientSettings.apply(state, { graphics = junk, camera = junk, view = junk }), false)
		end
		for _, junk in { "yes", 1, {} } do
			T.eq(ClientSettings.apply(state, { invertY = junk, reduceMotion = junk }), false)
		end
		T.eq(ClientSettings.apply(state, { reduceMotion = true }), true)
		T.eq(state.reduceMotion, true)
		T.eq(ClientSettings.apply(state, { invertY = true, view = "raised" }), true)
		T.eq(state.invertY, true)
		T.eq(state.view, "raised")
		T.eq(ClientSettings.apply(state, nil), false)
		T.eq(ClientSettings.apply(state, "graphics"), false)
	end)

	T.test("look speed is clamped, stepped and rejects non-numbers", function()
		local state = ClientSettings.new()
		T.eq(ClientSettings.apply(state, { lookSpeed = 1.52 }), true)
		T.ok(math.abs(state.lookSpeed - 1.5) < 1e-6, "rounds to 0.05")
		ClientSettings.apply(state, { lookSpeed = 99 })
		T.eq(state.lookSpeed, ClientSettings.LookSpeedMax)
		ClientSettings.apply(state, { lookSpeed = -4 })
		T.eq(state.lookSpeed, ClientSettings.LookSpeedMin)
		for _, junk in { 0 / 0, math.huge, -math.huge, "2" } do
			T.eq(ClientSettings.apply(state, { lookSpeed = junk }), false)
		end
	end)

	T.test("clean repairs a damaged save", function()
		local cleaned = ClientSettings.clean({ graphics = "ultra", camera = "calm", lookSpeed = "fast", extra = 1 })
		T.eq(cleaned.graphics, "auto")
		T.eq(cleaned.camera, "calm")
		T.eq(cleaned.lookSpeed, 1)
		T.eq((cleaned :: any).extra, nil)
		T.eq(ClientSettings.clean(nil).view, "eye")
	end)

	T.test("new profiles and old saves get settings", function()
		local fresh = Profile.new(0)
		T.eq(type(fresh.settings), "table")
		T.eq(fresh.settings.graphics, "auto")
		local old = Profile.new(0)
		old.settings = nil :: any
		local fixed = Profile.reconcile(old, 0)
		T.eq(fixed.settings.camera, "full")
		-- A save from before Reduce motion gets the field.
		local older = Profile.new(0)
		older.settings = { graphics = "low", camera = "calm", view = "eye", invertY = false, lookSpeed = 1 } :: any
		T.eq(Profile.reconcile(older, 0).settings.reduceMotion, false)
	end)
end

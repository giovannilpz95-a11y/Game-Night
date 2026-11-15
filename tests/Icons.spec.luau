local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Icons = require(ReplicatedStorage.Shared.Icons)

return function(T)
	T.test("every icon has a unique name, an emoji and a cell on the sheet", function()
		local seen = {}
		for i, entry in Icons.list do
			local name, emoji = entry[1], entry[2]
			T.ok(type(name) == "string" and not seen[name], `icon {i} named once`)
			seen[name] = true
			T.ok(type(emoji) == "string" and emoji ~= "", `{name} has an emoji`)
			local x, y = Icons.offset(name)
			T.ok(x ~= nil and y ~= nil, `{name} has a cell`)
			T.ok((x :: number) + Icons.CELL <= 1024 and (y :: number) + Icons.CELL <= 640, `{name} fits the 1024 x 640 sheet`)
		end
		T.eq(#Icons.list, 36)
	end)

	T.test("unknown names fall back safely; emoji until the sheet is uploaded", function()
		T.eq(Icons.offset("nope"), nil)
		T.eq(Icons.emoji("nope"), "?")
		T.eq(Icons.emoji("settings"), "⚙️")
		T.eq(Icons.drawn(), Icons.sheet ~= "" and Icons.sheet ~= "rbxassetid://0")
	end)
end

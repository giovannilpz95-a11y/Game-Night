local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameCatalog = require(ReplicatedStorage.Shared.GameCatalog)
local GameArt = require(ReplicatedStorage.Shared.GameArt)

return function(T)
	T.test("every game has a picker icon and a known category", function()
		for _, entry in GameCatalog.entries do
			T.ok(GameArt.icons[entry.id] ~= nil, `{entry.id} has an icon`)
			T.ok(GameArt.category(entry.category) ~= nil, `{entry.id} category {entry.category} has a color`)
		end
	end)

	T.test("every filter chip has at least one game", function()
		for _, category in GameArt.categories do
			local count = 0
			for _, entry in GameCatalog.entries do
				if entry.category == category.key then
					count += 1
				end
			end
			T.ok(count > 0, `{category.key} has games`)
		end
	end)
end

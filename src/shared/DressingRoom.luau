-- The Dressing Room: which Roblox catalog items players can try on, the browse categories
-- and the limits on a look. Pure data, shared by the server (which checks everything) and
-- the client (which browses the catalog). Design: vault "03 Design/Avatar Designer.md".
--
-- Items are Roblox avatar assets, identified by asset ID and their AssetTypeId.
-- v1 sells single assets. Bundles (bodies, heads, shoes, animations) come in v2.

local DressingRoom = {}

export type ItemType = {
	name: string, -- shown in the UI
	search: string, -- Enum.AvatarAssetType name used for catalog search
	accessory: string?, -- Enum.AccessoryType name, for accessories
	layered: boolean?, -- layered clothing (3D clothes that wrap the body)
	clothing: string?, -- HumanoidDescription property for classic 2D clothes
	order: number?, -- layering order for layered clothing (higher = on top)
	tryOnly: boolean?, -- kept on your own avatar, but not offered in the catalog in v1
}

-- Keyed by AssetTypeId, the number Roblox's GetProductInfo returns.
DressingRoom.Types = {
	[8] = { name = "Hat", search = "Hat", accessory = "Hat" },
	[41] = { name = "Hair", search = "HairAccessory", accessory = "Hair" },
	[42] = { name = "Face", search = "FaceAccessory", accessory = "Face" },
	[43] = { name = "Neck", search = "NeckAccessory", accessory = "Neck" },
	[44] = { name = "Shoulder", search = "ShoulderAccessory", accessory = "Shoulder" },
	[45] = { name = "Front", search = "FrontAccessory", accessory = "Front" },
	[46] = { name = "Back", search = "BackAccessory", accessory = "Back" },
	[47] = { name = "Waist", search = "WaistAccessory", accessory = "Waist" },

	[64] = { name = "T-Shirt", search = "TShirtAccessory", accessory = "TShirt", layered = true, order = 4 },
	[65] = { name = "Shirt", search = "ShirtAccessory", accessory = "Shirt", layered = true, order = 5 },
	[66] = { name = "Pants", search = "PantsAccessory", accessory = "Pants", layered = true, order = 2 },
	[67] = { name = "Jacket", search = "JacketAccessory", accessory = "Jacket", layered = true, order = 8 },
	[68] = { name = "Sweater", search = "SweaterAccessory", accessory = "Sweater", layered = true, order = 7 },
	[69] = { name = "Shorts", search = "ShortsAccessory", accessory = "Shorts", layered = true, order = 3 },
	[72] = { name = "Dress or skirt", search = "DressSkirtAccessory", accessory = "DressSkirt", layered = true, order = 6 },
	[70] = { name = "Left shoe", search = "LeftShoeAccessory", accessory = "LeftShoe", layered = true, order = 1, tryOnly = true },
	[71] = { name = "Right shoe", search = "RightShoeAccessory", accessory = "RightShoe", layered = true, order = 1, tryOnly = true },

	[2] = { name = "Classic T-Shirt", search = "TShirt", clothing = "GraphicTShirt" },
	[11] = { name = "Classic shirt", search = "Shirt", clothing = "Shirt" },
	[12] = { name = "Classic pants", search = "Pants", clothing = "Pants" },
} :: { [number]: ItemType }

-- AccessoryType name -> AssetTypeId, to read the accessories already on a player's avatar.
DressingRoom.TypeByAccessory = {} :: { [string]: number }
for typeId, info in DressingRoom.Types do
	if info.accessory then
		DressingRoom.TypeByAccessory[info.accessory] = typeId
	end
end

-- Browse tabs. `types` are AssetTypeIds searched together.
DressingRoom.Categories = {
	{ key = "featured", name = "Popular", types = { 8, 41, 42, 43, 44, 45, 46, 47, 64, 65, 66, 67, 68, 69, 72 } },
	{ key = "hats", name = "Hats", types = { 8 } },
	{ key = "hair", name = "Hair", types = { 41 } },
	{ key = "face", name = "Face", types = { 42 } },
	{ key = "neck", name = "Neck & shoulder", types = { 43, 44 } },
	{ key = "back", name = "Back, front & waist", types = { 45, 46, 47 } },
	{ key = "tops", name = "Tops", types = { 64, 65, 67, 68 } },
	{ key = "bottoms", name = "Bottoms", types = { 66, 69, 72 } },
	{ key = "classic", name = "Classic clothes", types = { 11, 12, 2 } },
}

-- Limits on a look (Roblox's own avatar rules are close to these).
DressingRoom.MaxRigidAccessories = 10 -- hats, hair, face, neck, shoulder, front, back, waist together
DressingRoom.MaxHair = 2
DressingRoom.MaxItems = 20 -- everything in one look
DressingRoom.SearchPageSize = 30
DressingRoom.MaxBulkItems = 20 -- most items "Buy the whole look" prompts at once

-- Starting point for a look: "mine" layers the look over the player's own avatar,
-- "blank" keeps their body and skin but drops their clothes and accessories.
DressingRoom.Bases = { mine = true, blank = true }

function DressingRoom.typeOf(typeId: number): ItemType?
	return DressingRoom.Types[typeId]
end

-- Roblox asset thumbnail for an ImageLabel.
function DressingRoom.thumbnail(assetId: number, size: number?): string
	local px = size or 150
	return `rbxthumb://type=Asset&id={assetId}&w={px}&h={px}`
end

return DressingRoom

-- Robux purchases: Gem packs, the Starter Pack and the reaction bundle (developer
-- products), VIP and Party Host
-- (game passes). Product IDs live in shared/Economy.luau.
--
-- Developer products go through ProcessReceipt, which Roblox retries until we say
-- PurchaseGranted. Each purchase ID is saved in the profile, so a pack is granted exactly
-- once, and we only report success after the profile has saved.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Season = require(ReplicatedStorage.Shared.Season)
local Net = require(ReplicatedStorage.Shared.Net)
local Profile = require(script.Parent.Parent.Core.Profile)
local Shop = require(script.Parent.Parent.Core.Shop)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local AnalyticsService = require(script.Parent.AnalyticsService)

local PurchaseService = {}

local notifyRemote: RemoteEvent

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted next time they join
	end
	local data = DataService.waitFor(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if Profile.hasReceipt(data, purchaseId) then
		-- Granted on an earlier try. Only tell Roblox it's done once that is saved: an
		-- earlier save may have failed, or this profile may not be saving at all
		-- (DataStore down when they joined), and then the purchase must stay pending.
		return if DataService.saveNow(player)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local kind, product = Economy.productById(info.ProductId)
	if kind == "gems" then
		Profile.addGems(data, product.gems)
	elseif kind == "starter" then
		Profile.addGems(data, product.gems)
		Shop.grant(data, product.items)
		data.grants.starter = true
	elseif kind == "reactions" then
		Shop.grant(data, product.items)
	elseif kind == "season" then
		-- Premium for the season it's processed in. If they already had it (bought with
		-- Gems in another server a moment ago), the Robux still count: refund as Gems.
		if not EconomyService.grantSeasonPremium(data) then
			Profile.addGems(data, product.gems)
		end
	else
		warn(`[GameNight] receipt for unknown product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Profile.addReceipt(data, purchaseId)

	if not DataService.saveNow(player) then
		-- Kept in memory with the receipt recorded, so a retry won't grant it twice.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	AnalyticsService.robuxPurchase(player, product.key, data, if kind == "season" then nil else product.gems)
	notify(player, if kind == "starter"
		then "Starter Pack unlocked! Thanks for supporting Game Night."
		elseif kind == "reactions" then "Every reaction pack is on your 😀 wheel. Thanks!"
		elseif kind == "season" then "Premium pass unlocked! Claim your rewards in 🎟️ Pass. Thanks!"
		else `+{product.gems} Gems. Thanks!`)
	EconomyService.push(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Client asks to buy something with Robux. We check it's set up and allowed, then prompt.
function PurchaseService.handleRequest(player: Player, request: any)
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return
	end
	if request.action == "buyGems" then
		for _, pack in Economy.GemPacks do
			if pack.key == request.key then
				if pack.productId == 0 then
					return notify(player, "Gem packs aren't set up yet")
				end
				AnalyticsService.robuxPrompt(player, pack.key)
				return MarketplaceService:PromptProductPurchase(player, pack.productId)
			end
		end
	elseif request.action == "buyStarter" then
		if Economy.StarterPack.productId == 0 then
			return notify(player, "The Starter Pack isn't set up yet")
		end
		if not EconomyService.isStarterAvailable(player) then
			return notify(player, "The Starter Pack is only for your first 3 days")
		end
		AnalyticsService.robuxPrompt(player, Economy.StarterPack.key)
		MarketplaceService:PromptProductPurchase(player, Economy.StarterPack.productId)
	elseif request.action == "buyReactionBundle" then
		local bundle = Economy.ReactionBundle
		if bundle.productId == 0 then
			return notify(player, "The reaction bundle isn't set up yet")
		end
		local data = DataService.get(player)
		if data and Shop.missing(data, bundle.items) == 0 then
			return notify(player, "You already have every reaction pack")
		end
		AnalyticsService.robuxPrompt(player, bundle.key)
		MarketplaceService:PromptProductPurchase(player, bundle.productId)
	elseif request.action == "buySeasonPass" then
		if Season.Premium.productId == 0 then
			return notify(player, "The premium pass isn't set up yet. You can get it with Gems.")
		end
		local data = DataService.get(player)
		if data and data.season.premium and data.season.id == Season.number(os.time()) then
			return notify(player, "You already have the premium pass")
		end
		AnalyticsService.robuxPrompt(player, Season.Premium.key)
		MarketplaceService:PromptProductPurchase(player, Season.Premium.productId)
	elseif request.action == "buyPass" then
		local pass = if type(request.key) == "string" then Economy.Passes[request.key] else nil
		if not pass then
			return
		end
		if pass.gamePassId == 0 then
			return notify(player, `{pass.name} isn't set up yet`)
		end
		if EconomyService.hasPass(player, request.key) then
			return notify(player, `You already have {pass.name}`)
		end
		AnalyticsService.robuxPrompt(player, `pass:{request.key}`, request.key)
		MarketplaceService:PromptGamePassPurchase(player, pass.gamePassId)
	end
end

-- A finished pass prompt is only a hint: check with Roblox that the pass is really owned
-- before turning perks on (VIP changes Gem prices). Ownership can take a moment to show up
-- after buying, so ask twice. If Roblox can't be reached, trust the prompt for this session;
-- passes are checked again on every join and never saved.
local function confirmPass(player: Player, gamePassId: number): boolean
	for attempt = 1, 2 do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		if not ok then
			return true
		end
		if owns then
			return true
		end
		if attempt == 1 then
			task.wait(3)
		end
	end
	warn(`[GameNight] pass prompt for {player.Name} said bought, but Roblox says not owned`)
	return false
end

function PurchaseService.init()
	notifyRemote = Net.event(Net.Names.Notify)
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		local key = Economy.passByGamePassId(gamePassId)
		if purchased and key and confirmPass(player, gamePassId) then
			EconomyService.setPass(player, key, true)
			AnalyticsService.robuxPurchase(player, `pass:{key}`)
			notify(player, `{Economy.Passes[key].name} unlocked. Thanks for supporting Game Night!`)
		end
	end)
end

return PurchaseService

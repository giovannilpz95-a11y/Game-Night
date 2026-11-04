-- Fakes just enough of Roblox to run pure modules and the specs. Used by run-tests.mjs.

local Node = {}

local function newNode(name, parent)
	local node = setmetatable({ __name = name, __parent = parent, __children = {} }, Node)
	if parent then
		parent.__children[name] = node
	end
	return node
end

Node.__index = function(self, key)
	if key == "Name" then
		return rawget(self, "__name")
	elseif key == "Parent" then
		return rawget(self, "__parent")
	elseif Node[key] then
		return Node[key]
	end
	local child = rawget(self, "__children")[key]
	if child == nil then
		error(`{key} is not a valid member of {rawget(self, "__name")}`, 2)
	end
	return child
end

function Node.FindFirstChild(self, name)
	return rawget(self, "__children")[name]
end

function Node.WaitForChild(self, name)
	local child = rawget(self, "__children")[name]
	assert(child, `WaitForChild would hang: {name} missing in {rawget(self, "__name")}`)
	return child
end

function Node.GetChildren(self)
	local out = {}
	for _, child in rawget(self, "__children") do
		table.insert(out, child)
	end
	return out
end

local dataModel = newNode("game", nil)

local function nodeAt(path)
	local node = dataModel
	for _, segment in path do
		node = rawget(node, "__children")[segment] or newNode(segment, node)
	end
	return node
end

function Node.GetService(self, name)
	return rawget(self, "__children")[name] or newNode(name, self)
end

game = dataModel

-- Config modules use Color3 for display colors; tests only need it not to crash.
Color3 = {
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
}

-- Deterministic stand-in for Roblox's Random.
Random = {}
Random.__index = Random
function Random.new(seed)
	local r = setmetatable({ s = ((seed or 12345) * 7919 + 104729) % 2147483646 + 1 }, Random)
	for _ = 1, 8 do
		r:NextNumber() -- small seeds start with tiny values; warm up the generator
	end
	return r
end
function Random:NextNumber(min, max)
	self.s = (self.s * 48271) % 2147483647
	local x = self.s / 2147483647
	if min then
		return min + x * (max - min)
	end
	return x
end
function Random:NextInteger(min, max)
	return math.min(max, min + math.floor(self:NextNumber() * (max - min + 1)))
end

local loaders = {}
local cache = {}

function __define(path, file, fn)
	local node = nodeAt(path)
	loaders[node] = { fn = fn, file = file }
end

local realRequire = require
function require(node)
	if cache[node] ~= nil then
		return cache[node]
	end
	local loader = loaders[node]
	if not loader then
		error(`require: no module at {rawget(node, "__name")}`, 2)
	end
	local result = loader.fn(node)
	cache[node] = result
	return result
end
local _ = realRequire

-- Spec helpers ------------------------------------------------------------

local function fmt(v)
	if type(v) == "string" then
		return `"{v}"`
	end
	return tostring(v)
end

local T = {}
local tests = {}

function T.test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

function T.eq(actual, expected, message)
	if actual ~= expected then
		error(`{message or "values differ"}: expected {fmt(expected)}, got {fmt(actual)}`, 2)
	end
end

function T.ok(value, message)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

T.Random = Random

function __runSpecs()
	local specs = rawget(dataModel, "__children").Tests
	local total, failed = 0, 0
	for name, specNode in rawget(specs, "__children") do
		if string.sub(name, -5) == ".spec" then
			table.clear(tests)
			local register = require(specNode)
			register(T)
			for _, t in tests do
				total += 1
				local ok, err = pcall(t.fn)
				if ok then
					print(`  ok    {name} > {t.name}`)
				else
					failed += 1
					print(`  FAIL  {name} > {t.name}\n        {err}`)
				end
			end
		end
	end
	print(`\n{total - failed}/{total} tests passed`)
	return failed
end

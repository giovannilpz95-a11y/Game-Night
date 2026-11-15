local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIStyle = require(ReplicatedStorage.Shared.UIStyle)
local Config = require(ReplicatedStorage.Shared.Config)

return function(T)
	T.test("every style defines every token with valid colors", function()
		for name, style in UIStyle.Styles do
			for _, token in UIStyle.Tokens do
				local c = style.colors[token]
				T.ok(type(c) == "table" and #c == 3, `{name}.{token} missing`)
				for _, v in c or {} do
					T.ok(type(v) == "number" and v >= 0 and v <= 255 and v % 1 == 0, `{name}.{token} bad channel`)
				end
			end
			for token in style.colors do
				T.ok(table.find(UIStyle.Tokens, token) ~= nil, `{name}.{token} isn't in UIStyle.Tokens`)
			end
			T.ok(type(style.label) == "string", `{name} needs a label`)
			T.ok(style.frame >= 1 and style.frame <= 4, `{name} frame out of range`)
			T.ok(style.edge >= 1 and style.edge <= 4, `{name} edge out of range`)
			for _, key in { "body", "bold", "title" } do
				T.ok(type(style.fonts[key]) == "string", `{name} font {key}`)
			end
		end
	end)

	T.test("text reads on every surface (WCAG AA, 4.5:1)", function()
		for name, style in UIStyle.Styles do
			local c = style.colors
			for _, surface in { "Background", "Panel", "PanelLight" } do
				T.ok(UIStyle.contrast(c.Text, c[surface]) >= 4.5, `{name}: Text on {surface}`)
			end
			T.ok(UIStyle.contrast(c.SubText, c.Panel) >= 4.5, `{name}: SubText on Panel`)
			T.ok(UIStyle.contrast(c.AccentText, c.Accent) >= 4.5, `{name}: AccentText on Accent`)
			T.ok(UIStyle.contrast(c.Ink, c.Paper) >= 4.5, `{name}: Ink on Paper`)
			T.ok(UIStyle.contrast(c.Ink2, c.Paper) >= 3, `{name}: Ink2 on Paper (large/secondary text)`)
		end
	end)

	T.test("pick falls back to the default", function()
		T.eq(UIStyle.pick("Classic"), "Classic")
		T.eq(UIStyle.pick("Cafe"), "Cafe")
		T.eq(UIStyle.pick("Nope"), UIStyle.Default)
		T.eq(UIStyle.pick(nil), UIStyle.Default)
		T.ok(UIStyle.Styles[UIStyle.pick(Config.UIStyle)] ~= nil, "Config.UIStyle names a style")
	end)
end

-- Tiny UI toolkit: theme colors and helpers to build GUI objects in code.
-- Everything is built in code for now so it lives in Git; step 4 (polish) can swap in
-- designed assets without touching game logic.

local Kit = {}

Kit.Theme = {
	Background = Color3.fromRGB(24, 22, 38),
	Panel = Color3.fromRGB(38, 34, 60),
	PanelLight = Color3.fromRGB(54, 49, 84),
	Accent = Color3.fromRGB(255, 196, 64),
	AccentText = Color3.fromRGB(40, 28, 0),
	Good = Color3.fromRGB(88, 204, 120),
	Bad = Color3.fromRGB(235, 87, 87),
	Warn = Color3.fromRGB(255, 150, 60),
	Text = Color3.fromRGB(245, 243, 255),
	SubText = Color3.fromRGB(176, 170, 204),
	Seat = {
		Color3.fromRGB(255, 99, 132),
		Color3.fromRGB(54, 162, 235),
		Color3.fromRGB(255, 206, 86),
		Color3.fromRGB(75, 192, 192),
		Color3.fromRGB(153, 102, 255),
		Color3.fromRGB(255, 159, 64),
		Color3.fromRGB(102, 255, 153),
		Color3.fromRGB(255, 102, 204),
	},
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}

-- Kit.new("Frame", { Size = ..., Parent = ... }, { children })
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

function Kit.corner(radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Kit.padding(px: number): UIPadding
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function Kit.list(gap: number?, horizontal: boolean?): UIListLayout
	return Kit.new("UIListLayout", {
		Padding = UDim.new(0, gap or 6),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Kit.panel(props: { [string]: any }): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Kit.Theme.Panel,
		BorderSizePixel = 0,
	}, { Kit.corner(14), Kit.padding(12) })
	for key, value in props do
		(frame :: any)[key] = value
	end
	return frame
end

function Kit.label(text: string, props: { [string]: any }?): TextLabel
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Kit.Theme.Text,
		Font = Kit.Theme.Font,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		TextWrapped = true,
	})
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

function Kit.button(text: string, onClick: () -> (), props: { [string]: any }?): TextButton
	local button = Kit.new("TextButton", {
		Text = text,
		AutoButtonColor = true,
		BackgroundColor3 = Kit.Theme.Accent,
		TextColor3 = Kit.Theme.AccentText,
		Font = Kit.Theme.FontBold,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 36),
		BorderSizePixel = 0,
	}, { Kit.corner(10) })
	for key, value in props or {} do
		(button :: any)[key] = value
	end
	button.Activated:Connect(onClick)
	return button
end

-- A centered window over a dimmed screen. Tapping the dim area or the X closes it.
-- Put content in `body`. opts: name, maxSize (Vector2), zIndex, onClose.
function Kit.modal(parent: Instance, opts: { [string]: any }): any
	local z = opts.zIndex or 25
	local overlay = Kit.new("TextButton", {
		Name = opts.name or "Modal",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z,
		Parent = parent,
	})
	-- A button that does nothing, so taps on the window don't reach the dim area behind it.
	local panel = Kit.new("TextButton", {
		Name = "Window",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		BackgroundColor3 = Kit.Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = overlay,
	}, {
		Kit.corner(14),
		Kit.padding(12),
		Kit.new("UISizeConstraint", { MaxSize = opts.maxSize or Vector2.new(900, 640) }),
	})
	local body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = panel,
	})

	local modal: any = { overlay = overlay, panel = panel, body = body }
	function modal.close()
		if overlay.Visible then
			overlay.Visible = false
			if opts.onClose then
				opts.onClose()
			end
		end
	end
	function modal.open()
		overlay.Visible = true
	end
	function modal.toggle()
		if overlay.Visible then
			modal.close()
		else
			modal.open()
		end
	end
	function modal.isOpen(): boolean
		return overlay.Visible
	end
	-- Fit inside the free screen area (below Roblox's top bar).
	function modal.fit(top: number, bottom: number)
		panel.Position = UDim2.new(0.5, 0, 0.5, (top - bottom) / 2)
		panel.Size = UDim2.new(1, -24, 1, -(top + bottom + 12))
	end
	overlay.Activated:Connect(modal.close)
	Kit.button("X", modal.close, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.new(0, 36, 0, 36),
		BackgroundColor3 = Kit.Theme.PanelLight,
		TextColor3 = Kit.Theme.Text,
		TextSize = 18,
		ZIndex = z + 20,
		Parent = panel,
	})
	return modal
end

function Kit.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
end

return Kit

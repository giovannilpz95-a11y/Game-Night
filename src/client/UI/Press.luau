-- What a button does when it's pressed, kept so a key can press it too (UI/Hotkeys:
-- number keys press the buttons on screen while Table view has the mouse locked).
-- Connect with Press.connect(button, fn) instead of button.Activated:Connect(fn); a real
-- click and Press.fire(button) then run the same functions. Kit.button does it for you.

local Press = {}

local handlers: { [GuiButton]: { (...any) -> () } } = setmetatable({}, { __mode = "k" }) :: any

-- Like button.Activated:Connect(fn), and remembered for Press.fire.
function Press.connect(button: GuiButton, fn: (...any) -> ()): RBXScriptConnection
	local list = handlers[button]
	if not list then
		list = {}
		handlers[button] = list
	end
	table.insert(list, fn)
	return button.Activated:Connect(fn)
end

-- Whether a key can press this button.
function Press.has(button: GuiButton): boolean
	return handlers[button] ~= nil
end

-- Presses the button as a click would.
function Press.fire(button: GuiButton)
	for _, fn in handlers[button] or {} do
		task.spawn(fn)
	end
end

return Press

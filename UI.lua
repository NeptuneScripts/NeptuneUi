local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Lib = {}
Lib.__index = Lib
local Tab = {}
Tab.__index = Tab

local TEXT = Color3.fromRGB(236, 236, 238)
local OFF = Color3.fromRGB(18, 18, 20)
local DIM = Color3.fromRGB(150, 150, 155)
local DANGER = Color3.fromRGB(235, 80, 95)
local DEFAULT_ACCENT = Color3.fromRGB(95, 215, 152)

----------------------------------------------------------------------- helpers

local function tween(obj, props, t)
	TweenService:Create(obj, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

-- accepts 123456, "123456", "rbxassetid://123456" or any other content string
local function normalizeIcon(icon)
	if typeof(icon) == "number" then return "rbxassetid://" .. math.floor(icon) end
	if typeof(icon) == "string" then
		if icon:match("^%d+$") then return "rbxassetid://" .. icon end
		return icon
	end
	return nil
end

local function keyName(k)
	if typeof(k) == "EnumItem" then return k.Name end
	return tostring(k)
end

local function tweenHex(layer, color)
	for _, band in ipairs(layer:GetChildren()) do
		if band:IsA("Frame") then tween(band, {BackgroundColor3 = color}) end
	end
end

-- rows are transparent; hovering fades in a faint white tint
local function hoverFx(hitButton, frame)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	hitButton.MouseEnter:Connect(function() tween(frame, {BackgroundTransparency = 0.95}) end)
	hitButton.MouseLeave:Connect(function() tween(frame, {BackgroundTransparency = 1}) end)
end

-- global connections are tracked so Window:Destroy() can clean them up
function Lib:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self._conns, c)
	return c
end

----------------------------------------------------------------------- elements

local function titleLabel(f, kind)
	if kind == "Button" or kind == "Label" then return f end
	if kind == "Section" then return f.Header.Title end
	return f:FindFirstChild("Title")
end

local function newElement(win, frame, kind, tab)
	local ev = Instance.new("BindableEvent")
	local e = {Frame = frame, Type = kind, Name = frame.Name, Tab = tab, Changed = ev.Event, Callback = nil}
	function e:OnChanged(fn)
		return ev.Event:Connect(fn)
	end
	function e:_emit(...)
		ev:Fire(...)
		if self.Callback then task.spawn(self.Callback, ...) end
	end
	function e:SetVisible(v) frame.Visible = v end
	function e:SetTitle(text)
		local l = titleLabel(frame, kind)
		if l then l.Text = text end
		if tab then
			if tab.Elements[self.Name] == self then tab.Elements[self.Name] = nil end
			tab.Elements[text] = self
		end
		self.Name = text
		frame.Name = text
	end
	e.SetText = e.SetTitle
	function e:Destroy()
		if tab then
			if tab.Elements[self.Name] == self then tab.Elements[self.Name] = nil end
			if kind == "Section" and tab.CurrentBody == frame:FindFirstChild("Body") then tab.CurrentBody = nil end
		end
		local idx = table.find(win.Elements, self)
		if idx then table.remove(win.Elements, idx) end
		ev:Destroy()
		frame:Destroy()
	end
	return e
end

local Binders = {}

function Binders.Button(win, f, e)
	local base = f.BackgroundColor3
	f.MouseEnter:Connect(function() tween(f, {BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.07)}) end)
	f.MouseLeave:Connect(function() tween(f, {BackgroundColor3 = base}) end)
	f.MouseButton1Down:Connect(function() tween(f, {BackgroundColor3 = win.Accent}, 0.05) end)
	f.MouseButton1Up:Connect(function() tween(f, {BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.07)}, 0.2) end)
	f.MouseButton1Click:Connect(function() e:_emit() end)
end

function Binders.Toggle(win, f, e)
	local sw = f.Switch
	local value = f:GetAttribute("Value") == true
	local function render(animate)
		local col = value and win.Accent or OFF
		local pos = value and UDim2.new(1, -(sw.Knob.Size.X.Offset + 3), 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
		if animate then
			tween(sw, {BackgroundColor3 = col})
			tween(sw.Knob, {Position = pos})
		else
			sw.BackgroundColor3 = col
			sw.Knob.Position = pos
		end
	end
	function e:Set(v, silent)
		value = v and true or false
		f:SetAttribute("Value", value)
		render(true)
		if not silent then self:_emit(value) end
	end
	function e:Get() return value end
	function e:_applyAccent() render(true) end
	hoverFx(f.Hit, f)
	f.Hit.MouseButton1Click:Connect(function() e:Set(not value) end)
	render(false)
end

function Binders.Slider(win, f, e)
	local min = f:GetAttribute("Min") or 0
	local max = f:GetAttribute("Max") or 100
	local inc = f:GetAttribute("Increment") or 1
	local suffix = f:GetAttribute("Suffix") or ""
	local track = f.Track
	local value = f:GetAttribute("Value") or min

	local function snap(v)
		v = math.clamp(v, min, max)
		v = math.floor((v - min) / inc + 0.5) * inc + min
		return tonumber(string.format("%.4f", math.clamp(v, min, max)))
	end
	local function render()
		local a = (value - min) / math.max(max - min, 1e-9)
		track.Fill.Size = UDim2.fromScale(a, 1)
		track.Knob.Position = UDim2.fromScale(a, 0.5)
		f.ValueLabel.Text = tostring(value) .. suffix
	end
	function e:Set(v, silent)
		v = snap(v)
		local changed = v ~= value
		value = v
		f:SetAttribute("Value", value)
		render()
		if changed and not silent then self:_emit(value) end
	end
	function e:Get() return value end
	function e:_applyAccent()
		track.Fill.BackgroundColor3 = win.Accent
		if track.Knob:FindFirstChild("Ring") then track.Knob.Ring.Color = win.Accent end
	end

	e:_applyAccent()
	local dragging = false
	local function fromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		e:Set(min + (max - min) * a)
	end
	f.Hit.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging = true
			fromX(i.Position.X)
		end
	end)
	win:_connect(UserInputService.InputChanged, function(i)
		if dragging and isMove(i) then fromX(i.Position.X) end
	end)
	win:_connect(UserInputService.InputEnded, function(i)
		if isPress(i) then dragging = false end
	end)
	hoverFx(f.Hit, f)
	value = snap(value)
	render()
end

-- Dropdown: title + full-width select box; the options panel animates open below it.
-- Closes on outside click, scrolls past MAX_VISIBLE options, hover highlight, dot marks the selection.
function Binders.Dropdown(win, f, e)
	local ROW, GAP, MAX_VISIBLE = 34, 2, 5
	local HEAD = f.Size.Y.Offset -- collapsed height (title + select box)
	local box = f.Box
	local boxStroke = box:FindFirstChild("Hairline")
	local strokeColor = boxStroke and boxStroke.Color
	local strokeAlpha = boxStroke and boxStroke.Transparency
	local boxBase = box.BackgroundColor3
	local options = {}
	local selected
	local open = false
	local buttons = {}

	local function parse(str)
		local t = {}
		for opt in string.gmatch(str or "", "[^,]+") do
			table.insert(t, (opt:match("^%s*(.-)%s*$")))
		end
		return t
	end
	local function listHeight()
		local n = math.min(#options, MAX_VISIBLE)
		return n * (ROW + GAP) - GAP + 8
	end
	local function refresh()
		f.Value.Text = tostring(selected or "")
		for name, b in pairs(buttons) do
			local on = name == selected
			b.TextColor3 = on and win.Accent or TEXT
			b.Dot.Visible = on
			b.Dot.BackgroundColor3 = win.Accent
		end
		if boxStroke and open then boxStroke.Color = win.Accent end
	end
	local function setOpen(o)
		open = o
		local list = f.List
		if o then
			list.Size = UDim2.new(1, 0, 0, listHeight())
			list.Visible = true
		end
		local total = o and (HEAD + 6 + listHeight()) or HEAD
		tween(f, {Size = UDim2.new(f.Size.X.Scale, f.Size.X.Offset, 0, total)}, 0.2)
		tween(f.Arrow, {Rotation = o and 180 or 0}, 0.2)
		if boxStroke then
			tween(boxStroke, {Color = o and win.Accent or strokeColor, Transparency = o and 0.3 or strokeAlpha}, 0.15)
		end
		if not o then
			task.delay(0.22, function()
				if not open then f.List.Visible = false end
			end)
		else
			-- scroll the page so the whole opened dropdown is visible
			task.delay(0.22, function()
				local sf = f:FindFirstAncestorOfClass("ScrollingFrame")
				if not (open and sf) then return end
				local overflow = (f.AbsolutePosition.Y + f.AbsoluteSize.Y) - (sf.AbsolutePosition.Y + sf.AbsoluteSize.Y)
				if overflow > 0 then
					tween(sf, {CanvasPosition = Vector2.new(0, sf.CanvasPosition.Y + overflow + 8)}, 0.2)
				end
			end)
		end
	end
	local function build()
		for _, c in ipairs(f.List:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		buttons = {}
		for i, opt in ipairs(options) do
			local b = Instance.new("TextButton")
			b.Name = opt
			b.LayoutOrder = i
			b.Size = UDim2.new(1, 0, 0, ROW)
			b.BackgroundColor3 = Color3.new(1, 1, 1)
			b.BackgroundTransparency = 1
			b.BorderSizePixel = 0
			b.AutoButtonColor = false
			b.Text = opt
			b.TextSize = 16
			b.Font = Enum.Font.BuilderSans
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.ZIndex = 4
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = b
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 12)
			pad.Parent = b
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(1, 0.5)
			dot.Position = UDim2.new(1, -12, 0.5, 0)
			dot.Size = UDim2.fromOffset(8, 8)
			dot.BorderSizePixel = 0
			dot.Visible = false
			dot.ZIndex = 5
			local dc = Instance.new("UICorner")
			dc.CornerRadius = UDim.new(1, 0)
			dc.Parent = dot
			dot.Parent = b
			b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = 0.94}, 0.1) end)
			b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = 1}, 0.1) end)
			b.MouseButton1Click:Connect(function()
				e:Set(opt)
				setOpen(false)
			end)
			b.Parent = f.List
			buttons[opt] = b
		end
		refresh()
	end

	function e:Set(v, silent)
		selected = v
		f:SetAttribute("Selected", v)
		refresh()
		if not silent then self:_emit(v) end
	end
	function e:Get() return selected end
	function e:SetOptions(list, keep)
		options = list
		if not (keep and table.find(list, selected)) then selected = list[1] end
		f:SetAttribute("Options", table.concat(list, ","))
		build()
	end
	e._applyAccent = refresh

	options = parse(f:GetAttribute("Options"))
	selected = f:GetAttribute("Selected") or options[1]
	build()
	f.Hit.MouseEnter:Connect(function() tween(box, {BackgroundColor3 = boxBase:Lerp(Color3.new(1, 1, 1), 0.05)}, 0.1) end)
	f.Hit.MouseLeave:Connect(function() tween(box, {BackgroundColor3 = boxBase}, 0.1) end)
	f.Hit.MouseButton1Click:Connect(function() setOpen(not open) end)

	-- close when clicking anywhere outside the dropdown (uses Roblox hit-testing, no inset maths)
	win:_connect(UserInputService.InputBegan, function(i)
		if not open or not isPress(i) then return end
		local playerGui = win.Gui:FindFirstAncestorOfClass("PlayerGui")
		if not playerGui then return end
		for _, o in ipairs(playerGui:GetGuiObjectsAtPosition(i.Position.X, i.Position.Y)) do
			if o == f or o:IsDescendantOf(f) then return end
		end
		setOpen(false)
	end)
end

function Binders.Input(win, f, e)
	local box = f.Box
	local v = f:GetAttribute("Value")
	if v then box.Text = v end
	function e:Set(t, silent)
		box.Text = tostring(t)
		f:SetAttribute("Value", box.Text)
		if not silent then self:_emit(box.Text) end
	end
	function e:Get() return box.Text end
	box.FocusLost:Connect(function()
		f:SetAttribute("Value", box.Text)
		e:_emit(box.Text)
	end)
end

function Binders.Keybind(win, f, e)
	local key = f:GetAttribute("Key") or "RightShift"
	local listening = false
	local pressed = Instance.new("BindableEvent")
	e.Pressed = pressed.Event
	function e:OnPressed(fn) return pressed.Event:Connect(fn) end
	local function render() f.Hit.Text = listening and "..." or key end
	function e:Set(k, silent)
		key = keyName(k)
		f:SetAttribute("Key", key)
		render()
		if not silent then self:_emit(key) end
	end
	function e:Get() return key end
	f.Hit.MouseButton1Click:Connect(function()
		listening = true
		render()
	end)
	win:_connect(UserInputService.InputBegan, function(i, processed)
		if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if listening then
			listening = false
			if i.KeyCode ~= Enum.KeyCode.Escape then e:Set(i.KeyCode.Name) else render() end
		elseif not processed and i.KeyCode.Name == key then
			pressed:Fire()
		end
	end)
	if f:GetAttribute("MenuKey") then
		win.ToggleKey = Enum.KeyCode[key] or win.ToggleKey
		e:OnChanged(function(k) win.ToggleKey = Enum.KeyCode[k] or win.ToggleKey end)
	end
	render()
end

-- Section = collapsible card (Header + Body)
function Binders.Section(win, f, e)
	local collapsed = false
	function e:SetCollapsed(c)
		collapsed = c
		f.Body.Visible = not c
		tween(f.Header.Chevron, {Rotation = c and -90 or 0}, 0.15)
	end
	f.Header.Hit.MouseButton1Click:Connect(function() e:SetCollapsed(not collapsed) end)
end

function Binders.Label(win, f, e) end

function Lib:_bindElement(f, tab)
	local kind = f:GetAttribute("NeptuneType")
	local binder = kind and Binders[kind]
	if not binder then return nil end
	local e = newElement(self, f, kind, tab)
	binder(self, f, e)
	table.insert(self.Elements, e)
	if tab then tab.Elements[f.Name] = e end
	return e
end

----------------------------------------------------------------------- tabs

function Lib:_tabPosition(i)
	local tf = self.TabsFrame
	local x = (i % 2 == 1) and (tf:GetAttribute("ColumnA") or 4) or (tf:GetAttribute("ColumnB") or 36)
	local y = (tf:GetAttribute("StartY") or 66) + (i - 1) * (tf:GetAttribute("Pitch") or 64)
	if tf:GetAttribute("Side") == "Right" then
		return UDim2.new(1, -x, 0, y)
	end
	return UDim2.new(0, x, 0, y)
end

-- grow the window when there are more hexagons than fit down the side
function Lib:_fitWindow()
	local tf = self.TabsFrame
	local n = #self.Tabs
	local half = self.Templates.HexTab.Size.Y.Offset / 2
	local needed = (tf:GetAttribute("StartY") or 66) + math.max(n - 1, 0) * (tf:GetAttribute("Pitch") or 64) + half + 24
	local cur = self.Main.Size
	if needed > cur.Y.Offset then
		self.Main.Size = UDim2.new(cur.X.Scale, cur.X.Offset, 0, math.ceil(needed))
	end
end

function Lib:_layoutTabs()
	for i, t in ipairs(self.Tabs) do
		t.Hex.LayoutOrder = i
		t.Hex.Position = self:_tabPosition(i)
	end
	self:_fitWindow()
end

function Lib:_setHex(t, active)
	local base = self.Templates.HexTab
	local line = active and self.Accent or base.Outline.Band1.BackgroundColor3
	local fill = base.Fill.Band1.BackgroundColor3
	if active then fill = fill:Lerp(self.Accent, 0.14) end
	tweenHex(t.Hex.Outline, line)
	tweenHex(t.Hex.Fill, fill)
	local logoColor
	if self.IconTint then logoColor = active and self.Accent or DIM else logoColor = Color3.new(1, 1, 1) end
	tween(t.Hex.Logo, {ImageColor3 = logoColor}, 0.2)
end

function Lib:_showTip(t)
	local tip = self.TabsFrame:FindFirstChild("Tooltip")
	if not tip then return end
	tip.Text.Text = t.Name
	local tf = self.TabsFrame
	local reach = math.max(tf:GetAttribute("ColumnA") or 0, tf:GetAttribute("ColumnB") or 0) + t.Hex.AbsoluteSize.X / 2 + 8
	local y = t.Hex.Position.Y.Offset
	if tf:GetAttribute("Side") == "Right" then
		tip.AnchorPoint = Vector2.new(1, 0.5)
		tip.Position = UDim2.new(1, -reach, 0, y)
	else
		tip.AnchorPoint = Vector2.new(0, 0.5)
		tip.Position = UDim2.new(0, reach, 0, y)
	end
	tip.Visible = true
end

function Lib:_bindTab(hex)
	local name = hex:GetAttribute("TabName") or hex.Name
	local page = self.Content:FindFirstChild("Page_" .. name)
	local t = setmetatable({Window = self, Name = name, Hex = hex, Page = page, Elements = {}}, Tab)
	table.insert(self.Tabs, t)
	self.TabMap[name] = t

	hex.Hit.MouseEnter:Connect(function()
		tween(hex.Scale, {Scale = 1.1}, 0.15)
		if self.ActiveTab ~= t then
			tweenHex(hex.Outline, self.Templates.HexTab.Outline.Band1.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.35))
		end
		self:_showTip(t)
	end)
	hex.Hit.MouseLeave:Connect(function()
		tween(hex.Scale, {Scale = 1}, 0.15)
		if self.ActiveTab ~= t then self:_setHex(t, false) end
		local tip = self.TabsFrame:FindFirstChild("Tooltip")
		if tip then tip.Visible = false end
	end)
	hex.Hit.MouseButton1Click:Connect(function() self:SelectTab(t) end)

	if page then
		for _, child in ipairs(page:GetDescendants()) do
			if child:GetAttribute("NeptuneType") == "Section" then t.CurrentBody = child:FindFirstChild("Body") end
			self:_bindElement(child, t)
		end
	end
	return t
end

-- hide rows (and empty cards) on a tab whose names don't match the search text
function Lib:_filter(tab, q)
	if not tab or not tab.Page then return end
	q = string.lower(q)
	for _, card in ipairs(tab.Page:GetChildren()) do
		if card:GetAttribute("NeptuneType") == "Section" and card:FindFirstChild("Body") then
			local any = false
			for _, row in ipairs(card.Body:GetChildren()) do
				if row:IsA("GuiObject") then
					local hit = q == "" or string.find(string.lower(row.Name), q, 1, true) ~= nil
					row.Visible = hit
					any = any or hit
				end
			end
			card.Visible = any or q == ""
		end
	end
end

function Lib:SelectTab(t)
	if type(t) == "string" then t = self.TabMap[t] end
	if not t then return end
	local prev = self.ActiveTab
	self.ActiveTab = t
	if self.Subtitle then self.Subtitle.Text = t.Name end
	local search = self.Header:FindFirstChild("Search")
	if search and search.Text ~= "" then
		self:_filter(prev, "")
		search.Text = ""
	end
	for _, o in ipairs(self.Tabs) do
		if o.Page then o.Page.Visible = (o == t) end
		self:_setHex(o, o == t)
	end
end

function Lib:GetTab(name) return self.TabMap[name] end

function Lib:AddTab(name, icon)
	if self.TabMap[name] then
		warn("[Neptune] a tab named '" .. name .. "' already exists")
		return self.TabMap[name]
	end
	local idx = #self.Tabs + 1
	local hex = self.Templates.HexTab:Clone()
	hex.Name = "Tab_" .. name
	hex:SetAttribute("TabName", name)
	hex.LayoutOrder = idx
	hex.Visible = true
	hex.Position = self:_tabPosition(idx)
	local img = normalizeIcon(icon)
	if img then hex.Logo.Image = img end
	hex.Parent = self.TabsFrame
	local page = self.Templates.Page:Clone()
	page.Name = "Page_" .. name
	page.Visible = false
	page.Parent = self.Content
	local t = self:_bindTab(hex)
	self:_setHex(t, false)
	self:_fitWindow()
	if not self.ActiveTab then self:SelectTab(t) end
	return t
end

function Lib:RemoveTab(t)
	if type(t) == "string" then t = self.TabMap[t] end
	if not t then return end
	local idx = table.find(self.Tabs, t)
	if idx then table.remove(self.Tabs, idx) end
	self.TabMap[t.Name] = nil
	for i = #self.Elements, 1, -1 do
		if self.Elements[i].Tab == t then table.remove(self.Elements, i) end
	end
	t.Hex:Destroy()
	if t.Page then t.Page:Destroy() end
	self:_layoutTabs()
	if self.ActiveTab == t then
		self.ActiveTab = nil
		self:SelectTab(self.Tabs[1])
	end
end

-- change the hexagon icon; pass nil to restore the placeholder
function Tab:SetIcon(icon)
	self.Hex.Logo.Image = normalizeIcon(icon) or self.Window.Templates.HexTab.Logo.Image
end

function Tab:Rename(newName)
	local win = self.Window
	win.TabMap[self.Name] = nil
	self.Name = newName
	win.TabMap[newName] = self
	self.Hex.Name = "Tab_" .. newName
	self.Hex:SetAttribute("TabName", newName)
	if self.Page then self.Page.Name = "Page_" .. newName end
	if win.ActiveTab == self and win.Subtitle then win.Subtitle.Text = newName end
end

function Tab:_make(template, name)
	-- sections are cards on the page; everything else goes into the current card's body
	local container = (template == "Section") and self.Page or (self.CurrentBody or self.Page)
	self._pending = container
	local n = (container:GetAttribute("_count") or #container:GetChildren()) + 1
	container:SetAttribute("_count", n)
	local f = self.Window.Templates[template]:Clone()
	f.Name = name
	f.Visible = true
	f.LayoutOrder = n
	return f
end

function Tab:_finish(f, cfg)
	f.Parent = self._pending or self.Page
	local e = self.Window:_bindElement(f, self)
	if e and cfg and cfg.Callback then e.Callback = cfg.Callback end
	return e
end

function Tab:AddSection(text)
	if type(text) == "table" then text = text.Name end
	local f = self:_make("Section", text)
	f.Header.Title.Text = text
	local e = self:_finish(f)
	self.CurrentBody = f.Body
	return e
end

function Tab:AddLabel(text)
	if type(text) == "table" then text = text.Text or text.Name end
	local f = self:_make("Label", text)
	f.Text = text
	return self:_finish(f)
end

function Tab:AddButton(cfg)
	local f = self:_make("Button", cfg.Name)
	f.Text = cfg.Name
	return self:_finish(f, cfg)
end

function Tab:AddToggle(cfg)
	local f = self:_make("Toggle", cfg.Name)
	f.Title.Text = cfg.Name
	f:SetAttribute("Value", cfg.Default == true)
	return self:_finish(f, cfg)
end

function Tab:AddSlider(cfg)
	local f = self:_make("Slider", cfg.Name)
	f.Title.Text = cfg.Name
	f:SetAttribute("Min", cfg.Min or 0)
	f:SetAttribute("Max", cfg.Max or 100)
	f:SetAttribute("Increment", cfg.Increment or 1)
	f:SetAttribute("Suffix", cfg.Suffix or "")
	f:SetAttribute("Value", cfg.Default or cfg.Min or 0)
	return self:_finish(f, cfg)
end

function Tab:AddDropdown(cfg)
	local f = self:_make("Dropdown", cfg.Name)
	f.Title.Text = cfg.Name
	f:SetAttribute("Options", table.concat(cfg.Options, ","))
	f:SetAttribute("Selected", cfg.Default or cfg.Options[1])
	return self:_finish(f, cfg)
end

function Tab:AddInput(cfg)
	local f = self:_make("Input", cfg.Name)
	f.Title.Text = cfg.Name
	f.Box.PlaceholderText = cfg.Placeholder or "Type here..."
	if cfg.Default then f:SetAttribute("Value", tostring(cfg.Default)) end
	return self:_finish(f, cfg)
end

function Tab:AddKeybind(cfg)
	local f = self:_make("Keybind", cfg.Name)
	f.Title.Text = cfg.Name
	f:SetAttribute("Key", cfg.Default and keyName(cfg.Default) or "E")
	return self:_finish(f, cfg)
end

----------------------------------------------------------------------- window

function Lib:SetTitle(text)
	if self.Title then self.Title.Text = text end
end

function Lib:SetAccent(color)
	local old = self.Accent
	self.Accent = color
	self.Main:SetAttribute("Accent", color)
	if self.Title and self.Title.TextColor3 == old then self.Title.TextColor3 = color end
	for _, e in ipairs(self.Elements) do
		if e._applyAccent then e:_applyAccent() end
	end
	for _, t in ipairs(self.Tabs) do self:_setHex(t, t == self.ActiveTab) end
end

function Lib:SetSize(width, height)
	self.Main.Size = UDim2.fromOffset(width, height)
	self:_fitWindow()
end

function Lib:SetToggleKey(key)
	self.ToggleKey = (typeof(key) == "EnumItem") and key or Enum.KeyCode[key]
	self.Main:SetAttribute("ToggleKey", self.ToggleKey.Name)
end

function Lib:SetIconTint(state)
	self.IconTint = state and true or false
	self.Main:SetAttribute("IconTint", self.IconTint)
	for _, t in ipairs(self.Tabs) do self:_setHex(t, t == self.ActiveTab) end
end

function Lib:Toggle(state)
	if state == nil then state = not self.Main.Visible end
	local pop = self.Main:FindFirstChild("Pop")
	if state then
		if pop then pop.Scale = 0.92 end
		self.Main.Visible = true
		if pop then
			TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		end
	else
		if pop then
			local tw = TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Scale = 0.94})
			tw:Play()
			tw.Completed:Wait()
		end
		self.Main.Visible = false
	end
end

-- Toast notification: Window:Notify({Title = "Hi", Content = "Text", Duration = 4, Color = Color3})
function Lib:Notify(cfg)
	local host = self.Gui:FindFirstChild("Notifications")
	local n = self.Templates:FindFirstChild("Notification")
	if not host or not n then return end
	local f = n:Clone()
	f.Visible = true
	f.Body.Title.Text = cfg.Title or "Notification"
	f.Body.Content.Text = cfg.Content or ""
	f.Body.Content.Visible = (cfg.Content or "") ~= ""
	f.Bar.BackgroundColor3 = cfg.Color or self.Accent
	f.LayoutOrder = os.clock() * 100 // 1
	local parts = {f, f.Body.Title, f.Body.Content, f.Bar}
	local goal = {}
	for _, p in ipairs(parts) do
		local prop = p:IsA("TextLabel") and "TextTransparency" or "BackgroundTransparency"
		goal[p] = {prop, p[prop]}
		p[prop] = 1
	end
	f.Parent = host
	for p, g in pairs(goal) do tween(p, {[g[1]] = g[2]}, 0.25) end
	task.delay(cfg.Duration or 4, function()
		if not f.Parent then return end
		for p, g in pairs(goal) do tween(p, {[g[1]] = 1}, 0.25) end
		task.wait(0.3)
		f:Destroy()
	end)
end

function Lib:Minimize(state)
	if state == nil then state = not self.Minimized end
	self.Minimized = state
	self.Content.Visible = not state
	self.TabsFrame.Visible = not state
	tween(self.Window, {Size = state and UDim2.new(1, 0, 0, self.Header.Size.Y.Offset) or UDim2.fromScale(1, 1)}, 0.2)
end

function Lib:Destroy()
	for _, c in ipairs(self._conns) do c:Disconnect() end
	table.clear(self._conns)
	self.Gui:Destroy()
end

----------------------------------------------------------------------- config save / load

local SAVABLE = {Toggle = true, Slider = true, Dropdown = true, Input = true, Keybind = true}

function Lib:ExportConfig()
	local out = {}
	for _, e in ipairs(self.Elements) do
		if SAVABLE[e.Type] and e.Tab then
			out[e.Tab.Name .. "/" .. e.Name] = e:Get()
		end
	end
	return out
end

function Lib:ImportConfig(cfg)
	for key, value in pairs(cfg) do
		local tabName, name = tostring(key):match("^(.-)/(.*)$")
		local tab = tabName and self.TabMap[tabName]
		local e = tab and tab.Elements[name]
		if e and e.Set then e:Set(value) end
	end
end

function Lib:ExportConfigJson()
	return HttpService:JSONEncode(self:ExportConfig())
end

function Lib:ImportConfigJson(str)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, str)
	if ok and type(data) == "table" then self:ImportConfig(data) end
	return ok
end

----------------------------------------------------------------------- init

function Lib:_bindWindow()
	local dragging, dragStart, startPos = false, nil, nil
	self.Header.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging = true
			dragStart = i.Position
			startPos = self.Main.Position
		end
	end)
	self:_connect(UserInputService.InputChanged, function(i)
		if dragging and isMove(i) then
			local d = i.Position - dragStart
			self.Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	self:_connect(UserInputService.InputEnded, function(i)
		if isPress(i) then dragging = false end
	end)

	local search = self.Header:FindFirstChild("Search")
	if search then
		search:GetPropertyChangedSignal("Text"):Connect(function()
			self:_filter(self.ActiveTab, search.Text)
		end)
	end

	local close, minimize = self.Header.Close, self.Header.Minimize
	for _, b in ipairs({close, minimize}) do
		local base = b.BackgroundColor3
		local hover = (b == close) and DANGER or base:Lerp(Color3.new(1, 1, 1), 0.1)
		b.MouseEnter:Connect(function() tween(b, {BackgroundColor3 = hover, TextColor3 = TEXT}) end)
		b.MouseLeave:Connect(function() tween(b, {BackgroundColor3 = base, TextColor3 = DIM}) end)
	end
	close.MouseButton1Click:Connect(function() self:Toggle(false) end)
	minimize.MouseButton1Click:Connect(function() self:Minimize() end)

	self:_connect(UserInputService.InputBegan, function(i, processed)
		if not processed and i.KeyCode == self.ToggleKey then self:Toggle() end
	end)
end

-- Lib.Init(gui, config)   config (all optional): Title, Accent, ToggleKey, Size (Vector2), IconTint
function Lib.Init(gui, cfg)
	cfg = cfg or {}
	local self = setmetatable({}, Lib)
	self.Gui = gui
	self.Main = gui:WaitForChild("Main")
	self.Window = self.Main:WaitForChild("Window")
	self.Header = self.Window:WaitForChild("Header")
	self.Content = self.Window:WaitForChild("Content")
	self.TabsFrame = self.Main:WaitForChild("Tabs")
	self.Templates = gui:WaitForChild("Templates")
	self.Title = self.Header:FindFirstChild("Title", true)
	self.Subtitle = self.Header:FindFirstChild("Subtitle", true)

	self.Accent = self.Main:GetAttribute("Accent") or DEFAULT_ACCENT
	self.IconTint = self.Main:GetAttribute("IconTint") ~= false
	local key = self.Main:GetAttribute("ToggleKey") or "RightShift"
	self.ToggleKey = Enum.KeyCode[key] or Enum.KeyCode.RightShift
	self.Tabs, self.TabMap, self.Elements, self._conns, self.Minimized = {}, {}, {}, {}, false

	local hexes = {}
	for _, c in ipairs(self.TabsFrame:GetChildren()) do
		if c:GetAttribute("NeptuneType") == "Tab" then table.insert(hexes, c) end
	end
	table.sort(hexes, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	for _, h in ipairs(hexes) do self:_bindTab(h) end

	self:_bindWindow()

	-- apply config
	if cfg.ToggleKey then self:SetToggleKey(cfg.ToggleKey) end
	if cfg.IconTint ~= nil then self.IconTint = cfg.IconTint and true or false end
	if cfg.Size then self:SetSize(cfg.Size.X, cfg.Size.Y) end
	if cfg.Title then self:SetTitle(cfg.Title) end
	if cfg.Accent then self:SetAccent(cfg.Accent) end

	self:_fitWindow()
	self:SelectTab(self.Tabs[1])
	return self
end

return Lib

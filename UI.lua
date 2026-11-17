--[[
	=====================  NEPTUNE UI LIBRARY  =====================

	Standalone: the whole interface is created from code, nothing has to exist beforehand.

		local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/NeptuneScripts/NeptuneUi/refs/heads/main/UI.lua"))()

	The window is a fixed 650x450 with hexagon tabs around the left edge (6 tabs fit).
	See Example.lua for every feature in use.

	-------------------------------------------------------------
	LIBRARY
	-------------------------------------------------------------
	Library:CreateWindow({
		Title = "Neptune",                 -- header title
		Footer = "version: example",       -- small text bottom right (optional)
		Accent = Color3.fromRGB(95,215,152),
		ToggleKey = Enum.KeyCode.RightShift,
		IconTint = true,                   -- false keeps your icons' own colours
		NotifySide = "Right",              -- "Left" | "Right"
		LoadingScreen = true,              -- hide the window behind a loading screen until Window:FinishLoading()
		                                   -- (or a table: {Title=, Subtitle=, MinTime=1.2, Timeout=25})
	}) -> Window

	Library.Options / Library.Toggles      elements by their index (see below)
	Library.ToggleKeybind = Options.MenuKeybind   -- a keybind element that shows/hides the menu
	Library:Notify({Title=, Description=, Time=4, Color=})  or  Library:Notify("text", 4)
	Library:SetAccent(color3)  Library:SetNotifySide("Left"|"Right")
	Library:OnUnload(fn)  Library:Unload()  Library.Unloaded
	Library:SaveConfig(name) / LoadConfig(name) / ListConfigs()      (needs file functions, e.g. an executor)
	Library:ExportConfig() / ImportConfig(table) / ExportConfigJson() / ImportConfigJson(str)
	Library.ConfigIgnore.SomeIndex = true  -- leave an element out of configs

	WINDOW
	Window:AddTab(name, icon) -> Tab       icon can be:
	                                         "settings", "user", "zap" ...   a Lucide icon name (see lucide.dev), loaded the same way Obsidian does
	                                         123456 / "rbxassetid://123456"  a Roblox image (the running account needs permission for it)
	                                         { "settings", 123456 }          several options, tried in order until one loads
	                                         nil                             placeholder image
	                                       If nothing loads, the tab shows its first letter and a warning is printed.
	Library:GetIcon("name") -> icon table or nil, reason
	Window:SelectTab(nameOrTab)  Window:SetTitle(text)  Window:SetIconTint(bool)
	Window:Toggle([visible])  Window:Minimize([state])
	Window:SetLoading("text", 0-1)         update the loading screen's status / progress (optional, yields one frame)
	Window:FinishLoading()                 close the loading screen and show the window; waits for the minimum time and for tab icons

	TAB
	Tab:AddGroupbox({Name=, Side="Left"|"Right", Collapsed=false, DisableCollapsing=false}) -> Groupbox
	Tab:AddLeftGroupbox(name)  Tab:AddRightGroupbox(name)
	Tab:SetIcon(icon)  Tab:Rename(name)         (SetIcon takes the same values as AddTab's icon)

	GROUPBOX  (index is optional; with an index the element is reachable via Library.Toggles / Library.Options)
	Groupbox:AddToggle(idx, {Text=, Default=false, Callback=function(value), Visible=, Disabled=, Risky=})
	Groupbox:AddButton({Text=, Func=function(), DoubleClick=false}) or AddButton("Text", func)
	Groupbox:AddLabel(text, wrap)   or   AddLabel(idx, {Text=, DoesWrap=})
	Groupbox:AddDivider()
	Groupbox:AddSlider(idx, {Text=, Default=, Min=, Max=, Rounding=0, Suffix="", Compact=false,
	                          FormatDisplayValue=function(slider, value) -> string?, Callback=})
	Groupbox:AddInput(idx, {Text=, Default=, Placeholder=, Numeric=false, Finished=false, ClearTextOnFocus=false,
	                         MaxLength=, Callback=})
	Groupbox:AddDropdown(idx, {Text=, Values={...}, Default=<index|name>, Multi=false, Searchable=false,
	                            SpecialType="Player"|"Team", ExcludeLocalPlayer=false, MaxVisibleDropdownItems=6,
	                            FormatDisplayValue=function(value) -> string, Callback=})
	Groupbox:AddKeybind(idx, {Text=, Default="E"|Enum.KeyCode.E|"MB2", Mode="Toggle"|"Hold"|"Press"|"Always",
	                           Callback=function(state), ChangedCallback=function(key)})
	Groupbox:SetCollapsed(bool)

	ELEMENTS
	el.Value   el:SetValue(v)   el:OnChanged(function(value) end)   el:SetText(t)   el:SetVisible(b)
	el:SetDisabled(b)   el:Destroy()
	slider/dropdown extras: dropdown:SetValues({...})   keybind: el:GetState()  el:OnClick(function(state) end)
	multi dropdown: el.Value is a table { [name] = true }
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local Library = {
	Options = {},
	Toggles = {},
	Unloaded = false,
	Window = nil,
	ToggleKeybind = nil,
	ConfigFolder = "NeptuneUI",
	ConfigIgnore = {},
	Theme = {
		Accent = Color3.fromRGB(95, 215, 152),
		Background = Color3.fromRGB(11, 11, 12),
		Card = Color3.fromRGB(20, 20, 22),
		Inset = Color3.fromRGB(9, 9, 10),
		Button = Color3.fromRGB(30, 30, 33),
		SwitchOff = Color3.fromRGB(18, 18, 20),
		Track = Color3.fromRGB(40, 40, 44),
		Text = Color3.fromRGB(236, 236, 238),
		Dim = Color3.fromRGB(150, 150, 155),
		HexLine = Color3.fromRGB(60, 60, 64),
		HexFill = Color3.fromRGB(12, 12, 13),
		Danger = Color3.fromRGB(235, 80, 95),
	},
}
local Theme = Library.Theme

-- BuilderSans on current clients, Gotham if the enum item does not exist (older clients would otherwise error here)
local function enumItem(enumType, name, fallback)
	local ok, item = pcall(function()
		return enumType[name]
	end)
	if ok and item then
		return item
	end
	return fallback
end
local FONT = enumItem(Enum.Font, "BuilderSans", Enum.Font.Gotham)
local FONT_MEDIUM = enumItem(Enum.Font, "BuilderSansMedium", FONT) -- labels and the loading screen's small text
local FONT_BOLD = enumItem(Enum.Font, "BuilderSansBold", Enum.Font.GothamBold)
local PLACEHOLDER_ICON = "rbxasset://textures/ui/GuiImagePlaceholder.png"
local WHITE = Color3.new(1, 1, 1)

local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right
local CENTER = Enum.TextXAlignment.Center

local connections = {}
local accentHooks = {}
local unloadCallbacks = {}
local gui = nil
local notifyHost = nil
local notifySide = "Right"

----------------------------------------------------------------------- helpers

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local function tween(obj, props, t)
	TweenService:Create(obj, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	local r = radius
	if typeof(r) ~= "UDim" then
		r = UDim.new(0, r)
	end
	return new("UICorner", {CornerRadius = r}, parent)
end

local function hairline(parent, transparency)
	return new("UIStroke", {
		Name = "Hairline",
		Color = WHITE,
		Transparency = transparency or 0.9,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(parent, props)
	local p = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = FONT,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = LEFT,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return new("TextLabel", p, parent)
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

-- accepts 123456, "123456", "rbxassetid://123456", "rbxasset://..."; anything else gives nil
local function normalizeIcon(icon)
	if typeof(icon) == "number" then
		return "rbxassetid://" .. math.floor(icon)
	end
	if typeof(icon) == "string" then
		if icon:match("^%d+$") then
			return "rbxassetid://" .. icon
		end
		if icon:match("^rbxasset") then
			return icon
		end
	end
	return nil
end

-- the accent colour is applied through hooks so Library:SetAccent can recolour everything
local function onAccent(fn)
	table.insert(accentHooks, fn)
	pcall(fn, Theme.Accent)
end

function Library:SetAccent(color)
	Theme.Accent = color
	for _, fn in ipairs(accentHooks) do
		pcall(fn, color)
	end
end

-- places the UI can live, best first: gethui() container, CoreGui, PlayerGui
local function parentCandidates()
	local list = {}
	local cleanup = {}
	local function add(inst)
		if inst and not table.find(list, inst) then
			table.insert(list, inst)
		end
	end
	if typeof(gethui) == "function" then
		local ok, ui = pcall(gethui)
		if ok and typeof(ui) == "Instance" then
			table.insert(cleanup, ui)
			-- Some executors (e.g. Potassium) return RobloxGui, which is itself a ScreenGui.
			-- A ScreenGui parented inside another ScreenGui never renders, so use its parent (CoreGui) instead.
			if ui:IsA("LayerCollector") then
				add(ui.Parent)
			else
				add(ui)
			end
		end
	end
	local okCore, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if okCore and core then
		add(core)
	end
	local okPg, pg = pcall(function()
		return LocalPlayer:WaitForChild("PlayerGui", 5)
	end)
	if okPg and pg then
		add(pg)
	end
	return list, cleanup
end

local function ensureGui()
	if gui and gui.Parent then
		return gui
	end
	local candidates, cleanup = parentCandidates()
	for _, parent in ipairs(candidates) do
		table.insert(cleanup, parent)
	end
	-- remove copies left behind by earlier runs
	for _, parent in ipairs(cleanup) do
		pcall(function()
			local old = parent:FindFirstChild("NeptuneUI")
			if old then
				old:Destroy()
			end
		end)
	end
	gui = new("ScreenGui", {
		Name = "NeptuneUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
		Enabled = true,
	})
	-- use the first place that actually accepts the GUI (some executors silently refuse CoreGui / gethui)
	local placed = nil
	for _, parent in ipairs(candidates) do
		local ok = pcall(function()
			gui.Parent = parent
		end)
		if ok and gui.Parent == parent then
			placed = parent
			break
		end
	end
	if not placed then
		warn("[Neptune] could not place the UI anywhere (gethui / CoreGui / PlayerGui all refused it)")
	else
		print("[Neptune] UI created in " .. tostring(placed.Name))
	end
	return gui
end

-- hexagon = 3 rotated bands; an Outline layer plus a slightly smaller Fill layer makes the border
local function hexLayer(parent, name, color, scale, z)
	local group = new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale, scale),
		ZIndex = z,
	}, parent)
	local rotations = {30, 90, 150}
	for i = 1, 3 do
		local band = new("Frame", {
			Name = "Band" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5774, 0.866),
			Rotation = rotations[i],
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, group)
		corner(band, 2)
	end
	return group
end

local function tweenHex(layer, color)
	for _, band in ipairs(layer:GetChildren()) do
		if band:IsA("Frame") then
			tween(band, {BackgroundColor3 = color})
		end
	end
end

----------------------------------------------------------------------- tab icons (same approach as Obsidian)

-- Icons by name come from the Lucide set through an icon module (the same one Obsidian loads).
-- The module downloads its own sprite sheets, so it needs no Roblox asset permissions and no files from your repo.
local ICON_MODULE_URLS = {
	"https://raw.githubusercontent.com/notpoiu/Molto/refs/heads/main/source.lua",
	"https://raw.githubusercontent.com/notpoiu/lucide-roblox-direct/refs/heads/main/source.lua",
}
local iconModule = nil
local iconModuleState = "idle" -- idle | loading | done

local function getIconModule()
	if iconModuleState == "done" then
		return iconModule
	end
	if iconModuleState == "loading" then
		while iconModuleState == "loading" do
			task.wait(0.05)
		end
		return iconModule
	end
	iconModuleState = "loading"
	for index, url in ipairs(ICON_MODULE_URLS) do
		local ok, mod = pcall(function()
			return loadstring(game:HttpGet(url))()
		end)
		if ok and type(mod) == "table" and mod.GetAsset then
			if index == 1 and mod.SetProvider then
				pcall(mod.SetProvider, "lucide")
			end
			iconModule = mod
			break
		end
	end
	iconModuleState = "done"
	return iconModule
end

-- Library:GetIcon("settings") -> { Url, ImageRectOffset, ImageRectSize, ... } or nil, reason   (may yield the first time)
function Library:GetIcon(name)
	local mod = getIconModule()
	if not mod then
		return nil, "the icon module could not be loaded (needs HttpGet, loadstring and file functions, e.g. an executor)"
	end
	local ok, icon = pcall(mod.GetAsset, name)
	if ok and icon then
		return icon
	end
	return nil, "unknown icon name '" .. tostring(name) .. "' (names are from lucide.dev)"
end

-- true unless Roblox reports that a Roblox-hosted image failed to load (e.g. no permission for this account)
local function imageLoads(logo)
	local image = logo.Image
	if not tostring(image):match("^rbxassetid://") then
		return true
	end
	pcall(function()
		ContentProvider:PreloadAsync({logo})
	end)
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus(image)
	end)
	if ok and status == Enum.AssetFetchStatus.Failure then
		return false
	end
	return true
end

local function showImage(logo, url, rectOffset, rectSize)
	logo.Image = url
	logo.ImageRectOffset = rectOffset or Vector2.new(0, 0)
	logo.ImageRectSize = rectSize or Vector2.new(0, 0)
end

-- icon: nil (placeholder), a Lucide name ("settings"), an asset id / "rbxassetid://...", or a list of those
-- that are tried in order. If none of them loads, the tab shows its first letter instead.
local function applyIcon(tab, icon)
	tab._iconToken = (tab._iconToken or 0) + 1
	local token = tab._iconToken
	local logo, glyph = tab.Logo, tab.Glyph
	glyph.Visible = false
	logo.Visible = true

	local list = {}
	if type(icon) == "table" then
		list = icon
	elseif icon ~= nil then
		list = {icon}
	end
	if #list == 0 then
		showImage(logo, PLACEHOLDER_ICON)
		return
	end
	showImage(logo, "")

	local window = tab.Window

	local function resolve()
		local lastError = "no usable icon given"
		for _, candidate in ipairs(list) do
			if tab._iconToken ~= token or not logo.Parent then
				return
			end
			local asset = normalizeIcon(candidate)
			if asset then
				showImage(logo, asset)
				if imageLoads(logo) then
					return
				end
				lastError = "Roblox could not load " .. asset .. " (this account may not have permission for it)"
			elseif type(candidate) == "string" then
				local found, err = Library:GetIcon(candidate)
				if tab._iconToken ~= token or not logo.Parent then
					return
				end
				if found then
					showImage(logo, found.Url, found.ImageRectOffset, found.ImageRectSize)
					if imageLoads(logo) then
						return
					end
					lastError = "the icon sheet for '" .. candidate .. "' could not be loaded"
				else
					lastError = err
				end
			else
				lastError = "unsupported icon value: " .. tostring(candidate)
			end
		end
		if tab._iconToken ~= token or not logo.Parent then
			return
		end
		logo.Visible = false
		glyph.Visible = true
		warn("[Neptune] icon for tab '" .. tostring(tab.Name) .. "' did not load: " .. tostring(lastError))
	end

	-- counted, so the loading screen can wait for the tab icons
	task.spawn(function()
		window._pendingIcons = (window._pendingIcons or 0) + 1
		local ok, err = pcall(resolve)
		window._pendingIcons = window._pendingIcons - 1
		if not ok then
			warn("[Neptune] icon error for tab '" .. tostring(tab.Name) .. "': " .. tostring(err))
		end
	end)
end

----------------------------------------------------------------------- notifications

local function applyNotifySide()
	if not notifyHost then
		return
	end
	local list = notifyHost:FindFirstChild("List")
	if notifySide == "Left" then
		notifyHost.AnchorPoint = Vector2.new(0, 1)
		notifyHost.Position = UDim2.new(0, 20, 1, -20)
		if list then
			list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		end
	else
		notifyHost.AnchorPoint = Vector2.new(1, 1)
		notifyHost.Position = UDim2.new(1, -20, 1, -20)
		if list then
			list.HorizontalAlignment = Enum.HorizontalAlignment.Right
		end
	end
end

local function ensureNotifyHost()
	if notifyHost and notifyHost.Parent then
		return notifyHost
	end
	local g = ensureGui()
	notifyHost = new("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 400),
		ZIndex = 50,
	}, g)
	new("UIListLayout", {
		Name = "List",
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}, notifyHost)
	applyNotifySide()
	return notifyHost
end

function Library:SetNotifySide(side)
	notifySide = (string.lower(tostring(side)) == "left") and "Left" or "Right"
	applyNotifySide()
end

-- Library:Notify({Title=, Description=, Time=4, Color=})  or  Library:Notify("text", time)
function Library:Notify(cfg, duration)
	if type(cfg) == "string" then
		cfg = {Title = "Notification", Description = cfg, Time = duration}
	end
	cfg = cfg or {}
	local host = ensureNotifyHost()

	local toast = new("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Card,
		BorderSizePixel = 0,
		LayoutOrder = math.floor(os.clock() * 100),
	})
	corner(toast, 14)
	local stroke = hairline(toast, 0.88)
	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(3, 30),
		BackgroundColor3 = cfg.Color or Theme.Accent,
		BorderSizePixel = 0,
	}, toast)
	corner(bar, UDim.new(1, 0))

	local body = new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, toast)
	new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, body)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
	}, body)

	local titleLabel = label(body, {
		Name = "Title", Text = cfg.Title or "Notification", Font = FONT_BOLD, TextSize = 18, LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), TextWrapped = true,
	})
	local description = cfg.Description or cfg.Content or ""
	local descLabel = nil
	if description ~= "" then
		descLabel = label(body, {
			Name = "Description", Text = description, TextSize = 15, TextColor3 = Theme.Dim, LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), TextWrapped = true,
		})
	end

	-- fade in / out
	local fades = {}
	local function fade(obj, prop)
		table.insert(fades, {obj, prop, obj[prop]})
		obj[prop] = 1
	end
	fade(toast, "BackgroundTransparency")
	fade(stroke, "Transparency")
	fade(bar, "BackgroundTransparency")
	fade(titleLabel, "TextTransparency")
	if descLabel then
		fade(descLabel, "TextTransparency")
	end
	toast.Parent = host
	for _, f in ipairs(fades) do
		tween(f[1], {[f[2]] = f[3]}, 0.25)
	end
	task.delay(cfg.Time or cfg.Duration or 4, function()
		if not toast.Parent then
			return
		end
		for _, f in ipairs(fades) do
			tween(f[1], {[f[2]] = 1}, 0.25)
		end
		task.wait(0.3)
		toast:Destroy()
	end)
end

----------------------------------------------------------------------- elements (shared)

local function register(idx, e)
	if idx == nil then
		return
	end
	if e.Type == "Toggle" then
		Library.Toggles[idx] = e
	else
		Library.Options[idx] = e
	end
end

local function newElement(idx, kind)
	local e = {Type = kind, Idx = idx, Value = nil, Callback = nil, _listeners = {}, _disabled = false}
	function e:OnChanged(fn)
		table.insert(self._listeners, fn)
		return {
			Disconnect = function()
				local i = table.find(self._listeners, fn)
				if i then
					table.remove(self._listeners, i)
				end
			end,
		}
	end
	function e:_fire(...)
		for _, fn in ipairs(self._listeners) do
			task.spawn(fn, ...)
		end
		if self.Callback and self._callbackOnValue ~= false then
			task.spawn(self.Callback, ...)
		end
	end
	return e
end

-- hooks up Row / Title / Hit based helpers and registers the element under its index
local function finishElement(e, row, title, hit, cfg)
	e.Row = row
	e.TitleLabel = title
	function e:SetVisible(v)
		row:SetAttribute("UserHidden", not v)
		row.Visible = v
	end
	function e:SetText(t)
		if title then
			title.Text = t
		end
		row:SetAttribute("Search", string.lower(t))
	end
	function e:SetDisabled(d)
		self._disabled = d and true or false
		if hit then
			hit.Active = not d
		end
		if title then
			title.TextTransparency = d and 0.55 or 0
		end
	end
	function e:Destroy()
		if self.Idx ~= nil then
			if Library.Toggles[self.Idx] == self then
				Library.Toggles[self.Idx] = nil
			end
			if Library.Options[self.Idx] == self then
				Library.Options[self.Idx] = nil
			end
		end
		row:Destroy()
	end
	if cfg then
		if cfg.Visible == false then
			e:SetVisible(false)
		end
		if cfg.Disabled then
			e:SetDisabled(true)
		end
		if cfg.Risky and title then
			title.TextColor3 = Theme.Danger
		end
	end
	register(e.Idx, e)
end

-- Add* functions accept (idx, cfg) or just (cfg)
local function splitArgs(idx, cfg)
	if type(idx) == "table" and cfg == nil then
		return nil, idx
	end
	return idx, cfg or {}
end

local function hitButton(parent, props)
	local p = {
		Name = "Hit", BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1),
		ZIndex = 5, AutoButtonColor = false,
	}
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return new("TextButton", p, parent)
end

-- rows are transparent; hovering fades in a faint white tint
local function hoverFx(hit, row)
	row.BackgroundColor3 = WHITE
	hit.MouseEnter:Connect(function()
		tween(row, {BackgroundTransparency = 0.95})
	end)
	hit.MouseLeave:Connect(function()
		tween(row, {BackgroundTransparency = 1})
	end)
end

----------------------------------------------------------------------- groupbox (card)

local Groupbox = {}
Groupbox.__index = Groupbox

function Groupbox:_row(height, searchText, class, props)
	self._order = self._order + 1
	local window = self.Tab and self.Tab.Window
	if window then
		window._features = window._features + 1
		window:_featureAdded()
	end
	local p = {
		Name = "Row", Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = WHITE,
		BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = self._order,
	}
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	local row = new(class or "Frame", p, self.Body)
	corner(row, 10)
	row:SetAttribute("Search", string.lower(searchText or ""))
	return row
end

local function rowTitle(row, text, props)
	local p = {Name = "Title", Text = text or "", TextSize = 17, Position = UDim2.new(0, 4, 0, 0), Size = UDim2.new(1, -70, 1, 0)}
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return label(row, p)
end

function Groupbox:SetCollapsed(collapsed)
	if self._noCollapse then
		return
	end
	self._collapsed = collapsed and true or false
	self.Body.Visible = not self._collapsed
	tween(self.Chevron, {Rotation = self._collapsed and -90 or 0}, 0.15)
end

function Groupbox:AddToggle(idx, cfg)
	idx, cfg = splitArgs(idx, cfg)
	local e = newElement(idx, "Toggle")
	e.Callback = cfg.Callback
	local value = cfg.Default == true
	e.Value = value

	local row = self:_row(44, cfg.Text)
	local title = rowTitle(row, cfg.Text or "Toggle")
	local sw = new("Frame", {
		Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(50, 28), BackgroundColor3 = Theme.SwitchOff, BorderSizePixel = 0,
	}, row)
	corner(sw, UDim.new(1, 0))
	hairline(sw, 0.88)
	local knob = new("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(22, 22), BackgroundColor3 = WHITE, BorderSizePixel = 0,
	}, sw)
	corner(knob, UDim.new(1, 0))
	local hit = hitButton(row)
	hoverFx(hit, row)

	local function render(animate)
		local color = value and Theme.Accent or Theme.SwitchOff
		local pos = value and UDim2.new(1, -25, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
		if animate then
			tween(sw, {BackgroundColor3 = color})
			tween(knob, {Position = pos})
		else
			sw.BackgroundColor3 = color
			knob.Position = pos
		end
	end

	function e:SetValue(v)
		v = v and true or false
		local changed = v ~= value
		value = v
		self.Value = v
		render(true)
		if changed then
			self:_fire(v)
		end
	end
	hit.MouseButton1Click:Connect(function()
		if not e._disabled then
			e:SetValue(not value)
		end
	end)
	onAccent(function()
		render(false)
	end)
	render(false)
	finishElement(e, row, title, hit, cfg)
	return e
end
Groupbox.AddCheckbox = Groupbox.AddToggle

function Groupbox:AddButton(cfg, func)
	if type(cfg) == "string" then
		cfg = {Text = cfg, Func = func}
	end
	cfg = cfg or {}
	local e = newElement(nil, "Button")
	local row = self:_row(44, cfg.Text)
	local btn = new("TextButton", {
		Name = "Button", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Button, BorderSizePixel = 0,
		Text = cfg.Text or "Button", TextColor3 = Theme.Text, TextSize = 17, Font = FONT, AutoButtonColor = false,
	}, row)
	corner(btn, 12)
	hairline(btn, 0.9)

	local base = Theme.Button
	local hover = base:Lerp(WHITE, 0.07)
	local pendingConfirm = false
	btn.MouseEnter:Connect(function()
		tween(btn, {BackgroundColor3 = hover})
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, {BackgroundColor3 = base})
	end)
	btn.MouseButton1Down:Connect(function()
		tween(btn, {BackgroundColor3 = Theme.Accent}, 0.05)
	end)
	btn.MouseButton1Up:Connect(function()
		tween(btn, {BackgroundColor3 = hover}, 0.2)
	end)
	btn.MouseButton1Click:Connect(function()
		if e._disabled then
			return
		end
		if cfg.DoubleClick and not pendingConfirm then
			pendingConfirm = true
			local original = btn.Text
			btn.Text = "Click again to confirm"
			task.delay(1.5, function()
				pendingConfirm = false
				if btn.Parent then
					btn.Text = e._text or original
				end
			end)
			return
		end
		pendingConfirm = false
		btn.Text = e._text or cfg.Text or "Button"
		local fn = cfg.Func or cfg.Callback
		if fn then
			task.spawn(fn)
		end
		e:_fire()
	end)
	function e:SetText(t)
		self._text = t
		btn.Text = t
		row:SetAttribute("Search", string.lower(t))
	end
	finishElement(e, row, nil, btn, cfg)
	e.SetText = function(self, t)
		self._text = t
		btn.Text = t
		row:SetAttribute("Search", string.lower(t))
	end
	return e
end

-- AddLabel("text", wrap)  |  AddLabel("text", wrap, idx)  |  AddLabel(idx, {Text=, DoesWrap=})
function Groupbox:AddLabel(a, b, c)
	local idx, text, wrap = nil, "", false
	if type(b) == "table" then
		idx, text, wrap = a, b.Text or "", b.DoesWrap == true
	else
		text, wrap, idx = a, b == true, c
	end
	local e = newElement(idx, "Label")
	local row = self:_row(24, text, "TextLabel", {
		Text = text, TextSize = 15, TextColor3 = Theme.Dim, Font = FONT_MEDIUM, TextXAlignment = LEFT,
		TextWrapped = wrap, AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
	})
	new("UIPadding", {PaddingLeft = UDim.new(0, 4)}, row)
	e.Value = text
	function e:SetValue(t)
		self.Value = t
		row.Text = t
		row:SetAttribute("Search", string.lower(t))
	end
	finishElement(e, row, nil, nil, nil)
	e.SetText = e.SetValue
	return e
end

function Groupbox:AddDivider()
	local row = self:_row(9, "")
	new("Frame", {
		Name = "Line", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0,
	}, row)
	return row
end

function Groupbox:AddSlider(idx, cfg)
	idx, cfg = splitArgs(idx, cfg)
	local e = newElement(idx, "Slider")
	e.Callback = cfg.Callback
	local min = cfg.Min or 0
	local max = cfg.Max or 100
	local rounding = cfg.Rounding or 0
	local suffix = cfg.Suffix or ""
	local mult = 10 ^ rounding

	local function snap(v)
		v = math.clamp(v, min, max)
		return math.floor(v * mult + 0.5) / mult
	end
	local value = snap(cfg.Default or min)
	e.Value = value
	e.Min, e.Max = min, max

	local row = self:_row(62, cfg.Text)
	local title = rowTitle(row, cfg.Text or "Slider", {Position = UDim2.new(0, 4, 0, 6), Size = UDim2.new(1, -100, 0, 24)})
	title.Visible = cfg.Compact ~= true
	local valueLabel = label(row, {
		Name = "ValueLabel", TextSize = 16, TextColor3 = Theme.Dim, TextXAlignment = RIGHT,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 6), Size = UDim2.fromOffset(94, 24),
	})
	local track = new("Frame", {
		Name = "Track", Position = UDim2.new(0, 4, 0, 42), Size = UDim2.new(1, -8, 0, 8),
		BackgroundColor3 = Theme.Track, BorderSizePixel = 0,
	}, row)
	corner(track, UDim.new(1, 0))
	local fill = new("Frame", {Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0}, track)
	corner(fill, UDim.new(1, 0))
	local knob = new("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2,
	}, track)
	corner(knob, UDim.new(1, 0))
	local hit = hitButton(row, {Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 1, -30)})
	hoverFx(hit, row)

	local function display()
		if cfg.FormatDisplayValue then
			local ok, text = pcall(cfg.FormatDisplayValue, e, value)
			if ok and text then
				return tostring(text)
			end
		end
		return string.format("%." .. rounding .. "f", value) .. suffix
	end
	local function render()
		local a = (value - min) / math.max(max - min, 1e-9)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valueLabel.Text = display()
	end

	function e:SetValue(v)
		v = snap(tonumber(v) or min)
		local changed = v ~= value
		value = v
		self.Value = v
		render()
		if changed then
			self:_fire(v)
		end
	end

	local dragging = false
	local function fromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		e:SetValue(min + (max - min) * a)
	end
	hit.InputBegan:Connect(function(input)
		if isPress(input) and not e._disabled then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			fromX(input.Position.X)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if isPress(input) then
			dragging = false
		end
	end)
	onAccent(function(color)
		fill.BackgroundColor3 = color
	end)
	render()
	finishElement(e, row, title, hit, cfg)
	return e
end

function Groupbox:AddInput(idx, cfg)
	idx, cfg = splitArgs(idx, cfg)
	local e = newElement(idx, "Input")
	e.Callback = cfg.Callback
	e.Value = tostring(cfg.Default or "")

	local row = self:_row(70, cfg.Text)
	local title = rowTitle(row, cfg.Text or "Input", {Position = UDim2.new(0, 4, 0, 4), Size = UDim2.new(1, -8, 0, 22)})
	local box = new("TextBox", {
		Name = "Box", Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.Inset,
		BorderSizePixel = 0, Text = e.Value, PlaceholderText = cfg.Placeholder or "", PlaceholderColor3 = Theme.Dim,
		TextColor3 = Theme.Text, TextSize = 16, Font = FONT, TextXAlignment = LEFT, ClearTextOnFocus = cfg.ClearTextOnFocus == true,
	}, row)
	corner(box, 10)
	hairline(box, 0.9)
	new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, box)

	local ignore = false
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if ignore then
			return
		end
		local t = box.Text
		local fixed = t
		if cfg.Numeric then
			fixed = t:gsub("[^%d%.%-]", "")
		end
		if cfg.MaxLength and #fixed > cfg.MaxLength then
			fixed = fixed:sub(1, cfg.MaxLength)
		end
		if fixed ~= t then
			ignore = true
			box.Text = fixed
			ignore = false
		end
		e.Value = fixed
		if not cfg.Finished then
			e:_fire(fixed)
		end
	end)
	if cfg.Finished then
		box.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				e:_fire(box.Text)
			end
		end)
	end
	function e:SetValue(t)
		t = tostring(t)
		box.Text = t
		self.Value = box.Text
		if cfg.Finished then
			self:_fire(box.Text)
		end
	end
	finishElement(e, row, title, box, cfg)
	return e
end

function Groupbox:AddDropdown(idx, cfg)
	idx, cfg = splitArgs(idx, cfg)
	local e = newElement(idx, "Dropdown")
	e.Callback = cfg.Callback
	local ROW, GAP, HEAD = 34, 2, 72
	local maxVisible = cfg.MaxVisibleDropdownItems or 6
	local multi = cfg.Multi == true
	local searchable = cfg.Searchable == true

	local values = {}
	local single = nil
	local set = {}
	local buttons = {}
	local shownCount = 0
	local open = false

	local function loadValues()
		values = {}
		if cfg.SpecialType == "Player" then
			for _, p in ipairs(Players:GetPlayers()) do
				if not (cfg.ExcludeLocalPlayer and p == LocalPlayer) then
					table.insert(values, p.Name)
				end
			end
		elseif cfg.SpecialType == "Team" then
			for _, t in ipairs(game:GetService("Teams"):GetTeams()) do
				table.insert(values, t.Name)
			end
		else
			for _, v in ipairs(cfg.Values or {}) do
				table.insert(values, tostring(v))
			end
		end
		shownCount = #values
	end
	local function display(v)
		if cfg.FormatDisplayValue then
			local ok, r = pcall(cfg.FormatDisplayValue, v)
			if ok and r then
				return tostring(r)
			end
		end
		return tostring(v)
	end
	local function valueText()
		if multi then
			local names = {}
			for _, v in ipairs(values) do
				if set[v] then
					table.insert(names, display(v))
				end
			end
			if #names == 0 then
				return "None"
			end
			return table.concat(names, ", ")
		end
		if single then
			return display(single)
		end
		return "None"
	end

	loadValues()
	local default = cfg.Default
	if multi then
		e.Value = set
		if type(default) == "number" then
			if values[default] then
				set[values[default]] = true
			end
		elseif type(default) == "string" then
			set[default] = true
		elseif type(default) == "table" then
			for k, v in pairs(default) do
				if type(k) == "number" then
					set[tostring(v)] = true
				elseif v then
					set[k] = true
				end
			end
		end
	else
		if type(default) == "number" then
			single = values[default]
		elseif default ~= nil then
			single = tostring(default)
		end
		e.Value = single
	end

	local row = self:_row(HEAD, cfg.Text, "Frame", {ClipsDescendants = true})
	local title = rowTitle(row, cfg.Text or "Dropdown", {Position = UDim2.new(0, 4, 0, 4), Size = UDim2.new(1, -8, 0, 22)})
	local box = new("Frame", {
		Name = "Box", Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Inset, BorderSizePixel = 0,
	}, row)
	corner(box, 10)
	local boxStroke = hairline(box, 0.9)
	local valueLabel = label(box, {
		Name = "Value", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -48, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local arrow = label(box, {
		Name = "Arrow", Text = "▼", TextSize = 11, TextColor3 = Theme.Dim, TextXAlignment = CENTER,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(18, 18),
	})
	local hit = hitButton(row, {Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 40)})

	local list = new("ScrollingFrame", {
		Name = "List", Position = UDim2.new(0, 0, 0, HEAD + 4), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Theme.Inset,
		BorderSizePixel = 0, Visible = false, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.HexLine,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 3,
	}, row)
	corner(list, 10)
	hairline(list, 0.9)
	new("UIListLayout", {Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder}, list)
	new("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4)}, list)

	local searchBox = nil
	if searchable then
		searchBox = new("TextBox", {
			Name = "Search", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Card, BorderSizePixel = 0,
			Text = "", PlaceholderText = "Search...", PlaceholderColor3 = Theme.Dim, TextColor3 = Theme.Text, TextSize = 15,
			Font = FONT, TextXAlignment = LEFT, ClearTextOnFocus = false, ZIndex = 4,
		}, list)
		corner(searchBox, 8)
		new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, searchBox)
	end

	local function listHeight()
		local n = math.min(shownCount, maxVisible)
		local h = 8
		if n > 0 then
			h = h + n * (ROW + GAP) - GAP
		end
		if searchable then
			h = h + 30 + GAP
		end
		return h
	end
	local function applyHeights()
		local lh = listHeight()
		list.Size = UDim2.new(1, 0, 0, lh)
		tween(row, {Size = UDim2.new(1, 0, 0, HEAD + 4 + lh)}, 0.2)
	end

	local function refresh()
		for v, b in pairs(buttons) do
			local on
			if multi then
				on = set[v] == true
			else
				on = single == v
			end
			b.TextColor3 = on and Theme.Accent or Theme.Text
			b.Dot.Visible = on
			b.Dot.BackgroundColor3 = Theme.Accent
		end
		valueLabel.Text = valueText()
		if open then
			boxStroke.Color = Theme.Accent
		end
	end

	local function setOpen(o)
		if o and e._disabled then
			return
		end
		open = o
		if o then
			list.Visible = true
			applyHeights()
		else
			tween(row, {Size = UDim2.new(1, 0, 0, HEAD)}, 0.2)
			task.delay(0.22, function()
				if not open then
					list.Visible = false
				end
			end)
		end
		tween(arrow, {Rotation = o and 180 or 0}, 0.2)
		tween(boxStroke, {Color = o and Theme.Accent or WHITE, Transparency = o and 0.3 or 0.9}, 0.15)
		if o then
			-- scroll the page so the opened dropdown is fully visible
			task.delay(0.24, function()
				local sf = row:FindFirstAncestorOfClass("ScrollingFrame")
				if not (open and sf) then
					return
				end
				local overflow = (row.AbsolutePosition.Y + row.AbsoluteSize.Y) - (sf.AbsolutePosition.Y + sf.AbsoluteSize.Y)
				if overflow > 0 then
					tween(sf, {CanvasPosition = Vector2.new(0, sf.CanvasPosition.Y + overflow + 8)}, 0.2)
				end
			end)
		end
	end

	local function build()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		buttons = {}
		for i, v in ipairs(values) do
			local b = new("TextButton", {
				Name = v, LayoutOrder = i, Size = UDim2.new(1, 0, 0, ROW), BackgroundColor3 = WHITE, BackgroundTransparency = 1,
				BorderSizePixel = 0, AutoButtonColor = false, Text = display(v), TextSize = 16, Font = FONT, TextColor3 = Theme.Text,
				TextXAlignment = LEFT, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4,
			}, list)
			corner(b, 8)
			new("UIPadding", {PaddingLeft = UDim.new(0, 12)}, b)
			local dot = new("Frame", {
				Name = "Dot", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(8, 8),
				BorderSizePixel = 0, Visible = false, ZIndex = 5,
			}, b)
			corner(dot, UDim.new(1, 0))
			b.MouseEnter:Connect(function()
				tween(b, {BackgroundTransparency = 0.94}, 0.1)
			end)
			b.MouseLeave:Connect(function()
				tween(b, {BackgroundTransparency = 1}, 0.1)
			end)
			b.MouseButton1Click:Connect(function()
				if multi then
					if set[v] then
						set[v] = nil
					else
						set[v] = true
					end
					refresh()
					e:_fire(e.Value)
				else
					e:SetValue(v)
					setOpen(false)
				end
			end)
			buttons[v] = b
		end
		shownCount = #values
		refresh()
	end

	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = string.lower(searchBox.Text)
			local n = 0
			for v, b in pairs(buttons) do
				local hitSearch = q == "" or string.find(string.lower(v), q, 1, true) ~= nil
				b.Visible = hitSearch
				if hitSearch then
					n = n + 1
				end
			end
			shownCount = n
			if open then
				applyHeights()
			end
		end)
	end

	function e:SetValue(v)
		if multi then
			for k in pairs(set) do
				set[k] = nil
			end
			if type(v) == "string" then
				set[v] = true
			elseif type(v) == "table" then
				for k, val in pairs(v) do
					if type(k) == "number" then
						set[tostring(val)] = true
					elseif val then
						set[k] = true
					end
				end
			end
		else
			if type(v) == "number" then
				v = values[v]
			end
			single = v
			self.Value = single
		end
		refresh()
		self:_fire(self.Value)
	end

	function e:SetValues(newValues)
		cfg.Values = newValues
		loadValues()
		if multi then
			for k in pairs(set) do
				if not table.find(values, k) then
					set[k] = nil
				end
			end
		else
			if single and not table.find(values, single) then
				single = nil
				self.Value = nil
			end
		end
		build()
	end

	hoverFx(hit, row) -- (the row itself stays clear while closed)
	hit.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)
	-- close when clicking anywhere outside the dropdown
	connect(UserInputService.InputBegan, function(input)
		if not open or not isPress(input) then
			return
		end
		local m = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local p, s = row.AbsolutePosition, row.AbsoluteSize
		local function inside(x, y)
			return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
		end
		if not (inside(m.X, m.Y) or inside(m.X, m.Y - inset.Y)) then
			setOpen(false)
		end
	end)

	if cfg.SpecialType == "Player" then
		connect(Players.PlayerAdded, function()
			e:SetValues({})
		end)
		connect(Players.PlayerRemoving, function()
			task.defer(function()
				e:SetValues({})
			end)
		end)
	end

	build()
	finishElement(e, row, title, hit, cfg)
	return e
end

local MOUSE_KEYS = {
	MB1 = Enum.UserInputType.MouseButton1,
	MB2 = Enum.UserInputType.MouseButton2,
	MB3 = Enum.UserInputType.MouseButton3,
}

local function keyString(k)
	if typeof(k) == "EnumItem" then
		if k == Enum.UserInputType.MouseButton1 then
			return "MB1"
		elseif k == Enum.UserInputType.MouseButton2 then
			return "MB2"
		elseif k == Enum.UserInputType.MouseButton3 then
			return "MB3"
		end
		return k.Name
	end
	if k == nil then
		return "None"
	end
	return tostring(k)
end

local function inputMatches(input, key)
	if key == "None" then
		return false
	end
	local ut = MOUSE_KEYS[key]
	if ut then
		return input.UserInputType == ut
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == key
end

function Groupbox:AddKeybind(idx, cfg)
	idx, cfg = splitArgs(idx, cfg)
	local e = newElement(idx, "Keybind")
	e.Callback = cfg.Callback
	e._callbackOnValue = false -- Callback is for key presses, not for rebinding
	local key = keyString(cfg.Default or "None")
	local mode = cfg.Mode or "Toggle"
	local state = (mode == "Always")
	local listening = false
	local clickListeners = {}
	e.Value = key
	e.Mode = mode

	local row = self:_row(44, cfg.Text)
	local title = rowTitle(row, cfg.Text or "Keybind", {Size = UDim2.new(1, -130, 1, 0)})
	local btn = new("TextButton", {
		Name = "Hit", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(110, 32),
		BackgroundColor3 = Theme.Inset, BorderSizePixel = 0, Text = key, TextColor3 = Theme.Text, TextSize = 15, Font = FONT,
		AutoButtonColor = false, ZIndex = 5,
	}, row)
	corner(btn, 10)
	hairline(btn, 0.9)
	hoverFx(btn, row)

	local function render()
		btn.Text = listening and "..." or key
	end
	local function press()
		for _, fn in ipairs(clickListeners) do
			task.spawn(fn, state)
		end
		if e.Callback then
			if mode == "Press" then
				task.spawn(e.Callback)
			else
				task.spawn(e.Callback, state)
			end
		end
	end

	function e:GetState()
		return state
	end
	function e:OnClick(fn)
		table.insert(clickListeners, fn)
	end
	function e:SetValue(v)
		if type(v) == "table" then
			if v[1] ~= nil then
				key = keyString(v[1])
			end
			if v[2] ~= nil then
				mode = v[2]
				self.Mode = mode
				state = (mode == "Always")
			end
		else
			key = keyString(v)
		end
		self.Value = key
		render()
		self:_fire(key)
		if cfg.ChangedCallback then
			task.spawn(cfg.ChangedCallback, key)
		end
	end

	btn.MouseButton1Click:Connect(function()
		if e._disabled then
			return
		end
		listening = true
		render()
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Unknown then
					render()
				else
					e:SetValue(input.KeyCode.Name)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
				listening = false
				e:SetValue(keyString(input.UserInputType))
			end
			return
		end
		if processed or not inputMatches(input, key) then
			return
		end
		if mode == "Toggle" then
			state = not state
			press()
		elseif mode == "Hold" then
			state = true
			press()
		elseif mode == "Press" then
			press()
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if mode == "Hold" and state and inputMatches(input, key) then
			state = false
			press()
		end
	end)

	finishElement(e, row, title, btn, cfg)
	return e
end
Groupbox.AddKeyPicker = Groupbox.AddKeybind

----------------------------------------------------------------------- tab

local Tab = {}
Tab.__index = Tab

function Tab:AddGroupbox(cfg)
	if type(cfg) == "string" then
		cfg = {Name = cfg}
	end
	cfg = cfg or {}
	local side = string.lower(tostring(cfg.Side or ""))
	local column
	if side == "left" then
		column = self.Left
	elseif side == "right" then
		column = self.Right
	else
		if self._next == 2 then
			column = self.Right
			self._next = 1
		else
			column = self.Left
			self._next = 2
		end
	end

	local card = new("Frame", {
		Name = "Groupbox", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Card, BorderSizePixel = 0, LayoutOrder = #self.Groupboxes + 1,
	}, column)
	corner(card, 16)
	hairline(card, 0.92)
	new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, card)

	local head = new("Frame", {Name = "Header", Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, LayoutOrder = 0}, card)
	label(head, {
		Name = "Title", Text = cfg.Name or "Groupbox", Font = FONT_BOLD, TextSize = 19,
		Position = UDim2.new(0, 18, 0, 0), Size = UDim2.new(1, -60, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local chevron = label(head, {
		Name = "Chevron", Text = "▼", TextSize = 11, TextColor3 = Theme.Dim, TextXAlignment = CENTER,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(18, 18),
	})
	new("Frame", {
		Name = "Divider", Position = UDim2.new(0, 16, 1, -1), Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0,
	}, head)
	local headHit = new("TextButton", {Name = "Hit", BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5, AutoButtonColor = false}, head)

	local body = new("Frame", {
		Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1,
	}, card)
	-- space between the rows of a groupbox (buttons are full-row, so this is the gap you see between them)
	new("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, body)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10),
	}, body)

	local gb = setmetatable({Tab = self, Frame = card, Body = body, Chevron = chevron, _order = 0, _collapsed = false}, Groupbox)
	if cfg.DisableCollapsing then
		gb._noCollapse = true
		chevron.Visible = false
		headHit.Active = false
	else
		headHit.MouseButton1Click:Connect(function()
			gb:SetCollapsed(not gb._collapsed)
		end)
	end
	if cfg.Collapsed then
		gb:SetCollapsed(true)
	end
	table.insert(self.Groupboxes, gb)
	return gb
end

function Tab:AddLeftGroupbox(name)
	return self:AddGroupbox({Name = name, Side = "Left"})
end

function Tab:AddRightGroupbox(name)
	return self:AddGroupbox({Name = name, Side = "Right"})
end

function Tab:SetIcon(icon)
	applyIcon(self, icon)
end

function Tab:Rename(newName)
	local w = self.Window
	w.TabMap[self.Name] = nil
	self.Name = newName
	w.TabMap[newName] = self
	self.Hex.Name = "Tab_" .. newName
	self.Page.Name = "Page_" .. newName
	self.Glyph.Text = string.upper(string.sub(newName, 1, 1))
	if w.ActiveTab == self then
		w.Subtitle.Text = newName
	end
end

----------------------------------------------------------------------- window

local Window = {}
Window.__index = Window

local function tabPosition(i)
	local x = (i % 2 == 1) and 4 or 36
	local y = 66 + (i - 1) * 64
	return UDim2.new(0, x, 0, y)
end

function Window:_refreshTabs()
	for _, t in ipairs(self.Tabs) do
		local active = (t == self.ActiveTab)
		tweenHex(t.Outline, active and Theme.Accent or Theme.HexLine)
		tweenHex(t.Fill, active and Theme.HexFill:Lerp(Theme.Accent, 0.14) or Theme.HexFill)
		local logoColor = WHITE
		if self.IconTint then
			logoColor = active and Theme.Accent or Theme.Dim
		end
		tween(t.Logo, {ImageColor3 = logoColor}, 0.2)
		tween(t.Glyph, {TextColor3 = active and Theme.Accent or Theme.Dim}, 0.2)
	end
end

-- hide rows (and empty groupboxes) on a tab that don't match the search text
function Window:_filter(tab, query)
	if not tab then
		return
	end
	local q = string.lower(query or "")
	for _, gb in ipairs(tab.Groupboxes) do
		local any = false
		for _, row in ipairs(gb.Body:GetChildren()) do
			if row:IsA("GuiObject") then
				local s = row:GetAttribute("Search") or ""
				local match = q == "" or (s ~= "" and string.find(s, q, 1, true) ~= nil)
				local visible = match and not row:GetAttribute("UserHidden")
				row.Visible = visible
				if visible and q ~= "" then
					any = true
				end
			end
		end
		gb.Frame.Visible = (q == "") or any
	end
end

function Window:_showTip(tab)
	local tip = self._tip
	tip.Text.Text = tab.Name
	tip.Position = UDim2.new(0, 36 + 32 + 8, 0, tab.Hex.Position.Y.Offset)
	tip.Visible = true
end

function Window:SelectTab(t)
	if type(t) == "string" then
		t = self.TabMap[t]
	end
	if not t then
		return
	end
	local prev = self.ActiveTab
	self.ActiveTab = t
	if self._search.Text ~= "" then
		self:_filter(prev, "")
		self._search.Text = ""
	end
	self.Subtitle.Text = t.Name
	for _, o in ipairs(self.Tabs) do
		o.Page.Visible = (o == t)
	end
	self:_refreshTabs()
end

function Window:AddTab(name, icon)
	if self.TabMap[name] then
		return self.TabMap[name]
	end
	local idx = #self.Tabs + 1
	if idx > 6 then
		warn("[Neptune] only 6 hexagon tabs fit in the window")
	end

	local hex = new("Frame", {
		Name = "Tab_" .. name, AnchorPoint = Vector2.new(0.5, 0.5), Position = tabPosition(idx), Size = UDim2.fromOffset(64, 74),
		BackgroundTransparency = 1, LayoutOrder = idx,
	}, self._tabsFrame)
	new("UIAspectRatioConstraint", {AspectRatio = 0.866}, hex)
	local scale = new("UIScale", {Name = "Scale"}, hex)
	local outline = hexLayer(hex, "Outline", Theme.HexLine, 1, 1)
	local fill = hexLayer(hex, "Fill", Theme.HexFill, 0.935, 2)
	local logo = new("ImageLabel", {
		Name = "Logo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.364),
		BackgroundTransparency = 1, Image = "", ImageColor3 = Theme.Dim, ScaleType = Enum.ScaleType.Fit, ZIndex = 3,
	}, hex)
	-- shown instead of the logo when an icon could not be loaded
	local glyph = label(hex, {
		Name = "Glyph", Text = string.upper(string.sub(name, 1, 1)), Font = FONT_BOLD, TextSize = 26, TextColor3 = Theme.Dim,
		TextXAlignment = CENTER, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6), Visible = false, ZIndex = 3,
	})
	local hit = new("TextButton", {Name = "Hit", BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 4, AutoButtonColor = false}, hex)

	local page = new("ScrollingFrame", {
		Name = "Page_" .. name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.HexLine, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
	}, self._content)
	new("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6)}, page)
	local columns = new("Frame", {Name = "Columns", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, page)
	new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder}, columns)
	local function makeColumn(colName, order)
		local c = new("Frame", {
			Name = colName, Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order,
		}, columns)
		new("UIListLayout", {Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder}, c)
		return c
	end

	local tab = setmetatable({
		Window = self, Name = name, Hex = hex, Outline = outline, Fill = fill, Logo = logo, Glyph = glyph, Page = page,
		Left = makeColumn("Left", 1), Right = makeColumn("Right", 2), Groupboxes = {}, _next = 1,
	}, Tab)
	table.insert(self.Tabs, tab)
	self.TabMap[name] = tab
	applyIcon(tab, icon)

	hit.MouseEnter:Connect(function()
		tween(scale, {Scale = 1.1}, 0.15)
		if self.ActiveTab ~= tab then
			tweenHex(outline, Theme.HexLine:Lerp(WHITE, 0.35))
		end
		self:_showTip(tab)
	end)
	hit.MouseLeave:Connect(function()
		tween(scale, {Scale = 1}, 0.15)
		if self.ActiveTab ~= tab then
			tweenHex(outline, Theme.HexLine)
		end
		self._tip.Visible = false
	end)
	hit.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	if not self.ActiveTab then
		self:SelectTab(tab)
	else
		self:_refreshTabs()
	end
	return tab
end

function Window:SetTitle(text)
	self.TitleLabel.Text = text
end

function Window:SetIconTint(state)
	self.IconTint = state and true or false
	self:_refreshTabs()
end

function Window:Toggle(state)
	if self._loading then
		return
	end
	local main = self.Main
	if state == nil then
		state = not main.Visible
	end
	local pop = main:FindFirstChild("Pop")
	if state then
		if pop then
			pop.Scale = 0.92
		end
		main.Visible = true
		if pop then
			TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		end
	else
		if pop then
			local tw = TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Scale = 0.94})
			tw:Play()
			tw.Completed:Wait()
		end
		main.Visible = false
	end
end

function Window:Minimize(state)
	if state == nil then
		state = not self.Minimized
	end
	self.Minimized = state
	self._content.Visible = not state
	self._tabsFrame.Visible = not state
	tween(self._window, {Size = state and UDim2.new(1, 0, 0, 52) or UDim2.fromScale(1, 1)}, 0.2)
end

function Window:Destroy()
	Library:Unload()
end

----------------------------------------------------------------------- loading screen

function Window:_refreshLoadingText()
	local ld = self._loading
	if not ld or not ld.Card.Parent then
		return
	end
	local text = self._loadStatus or "Loading features..."
	if self._features > 0 then
		text = text .. "  ·  " .. self._features .. " features"
	end
	ld.Status.Text = text
end

-- called for every element that gets added while the loading screen is up
function Window:_featureAdded()
	local ld = self._loading
	if not ld then
		return
	end
	if not self._manualProgress then
		-- no explicit progress given: creep towards 100% as features appear
		local fraction = 1 - 1 / (1 + self._features / 20)
		ld.Fill.Size = UDim2.new(fraction, 0, 1, 0)
	end
	self:_refreshLoadingText()
end

-- Window:SetLoading("Building the Main tab...", 0.3)   text and progress (0 to 1) are both optional.
-- It also yields for one frame so the loading screen gets drawn between your steps.
function Window:SetLoading(text, fraction)
	local ld = self._loading
	if not ld then
		return
	end
	if text then
		self._loadStatus = text
	end
	if fraction then
		self._manualProgress = true
		tween(ld.Fill, {Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)}, 0.25)
	end
	self:_refreshLoadingText()
	task.wait()
end

-- Window:FinishLoading() hides the loading screen and shows the window. Call it after everything is added.
-- It waits for the minimum display time and for the tab icons to finish loading first.
function Window:FinishLoading()
	local ld = self._loading
	if not ld or ld.finishing then
		return
	end
	ld.finishing = true
	self._loadStatus = "Finishing up..."
	self:_refreshLoadingText()

	local iconDeadline = os.clock() + 12
	while ld.Card.Parent and ((os.clock() < self._loadingStart + self._loadingMin) or (self._pendingIcons > 0 and os.clock() < iconDeadline)) do
		task.wait(0.05)
	end
	if not ld.Card.Parent then
		self._loading = nil
		return
	end

	tween(ld.Fill, {Size = UDim2.new(1, 0, 1, 0)}, 0.2)
	task.wait(0.25)
	tween(ld.Card, {GroupTransparency = 1}, 0.25)
	task.wait(0.3)
	if ld.Spin then
		ld.Spin:Cancel()
	end
	ld.Card:Destroy()
	self._loading = nil
	self:Toggle(true)
end

function Window:_createLoadingScreen(g, opts, cfg)
	self.Main.Visible = false
	self._loadingStart = os.clock()
	self._loadingMin = opts.MinTime or 1.2
	self._loadStatus = opts.Subtitle or "Loading features..."

	local card = new("CanvasGroup", {
		Name = "LoadingScreen", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 214), BackgroundColor3 = Theme.Background, BorderSizePixel = 0,
		GroupTransparency = 1, ZIndex = 100,
	}, g)
	corner(card, 18)
	hairline(card, 0.88)

	-- a spinning hexagon, to match the tabs
	local spin = new("Frame", {
		Name = "Spinner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.fromOffset(52, 60), BackgroundTransparency = 1,
	}, card)
	local spinOutline = hexLayer(spin, "Outline", Theme.Accent, 1, 1)
	hexLayer(spin, "Fill", Theme.Background, 0.78, 2)
	local spinTween = TweenService:Create(
		spin,
		TweenInfo.new(1.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{Rotation = 360}
	)
	spinTween:Play()

	local title = label(card, {
		Name = "Title", Text = opts.Title or cfg.Title or "Neptune", Font = FONT_BOLD, TextSize = 24, TextColor3 = Theme.Accent,
		TextXAlignment = CENTER, Position = UDim2.new(0, 0, 0, 94), Size = UDim2.new(1, 0, 0, 30),
	})
	local status = label(card, {
		Name = "Status", Text = self._loadStatus, Font = FONT_MEDIUM, TextSize = 15, TextColor3 = Theme.Dim, TextXAlignment = CENTER,
		TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 20, 0, 128), Size = UDim2.new(1, -40, 0, 22),
	})
	local track = new("Frame", {
		Name = "Track", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 166), Size = UDim2.fromOffset(300, 6),
		BackgroundColor3 = Theme.Track, BorderSizePixel = 0,
	}, card)
	corner(track, UDim.new(1, 0))
	local fill = new("Frame", {Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0}, track)
	corner(fill, UDim.new(1, 0))

	self._loading = {Card = card, Fill = fill, Status = status, Spin = spinTween}
	tween(card, {GroupTransparency = 0}, 0.25)

	onAccent(function(color)
		if card.Parent then
			title.TextColor3 = color
			fill.BackgroundColor3 = color
			for _, band in ipairs(spinOutline:GetChildren()) do
				if band:IsA("Frame") then
					band.BackgroundColor3 = color
				end
			end
		end
	end)

	-- safety net: if FinishLoading is never called, show the window anyway
	task.delay(opts.Timeout or 25, function()
		if self._loading and not self._loading.finishing then
			warn("[Neptune] Window:FinishLoading() was not called, showing the window anyway")
			self:FinishLoading()
		end
	end)
end

function Library:CreateWindow(cfg)
	cfg = cfg or {}
	if self.Window then
		warn("[Neptune] a window already exists")
		return self.Window
	end
	local g = ensureGui()
	if cfg.NotifySide then
		self:SetNotifySide(cfg.NotifySide)
	end
	if cfg.Accent then
		Theme.Accent = cfg.Accent
	end

	local w = setmetatable({
		Tabs = {}, TabMap = {}, Minimized = false, IconTint = cfg.IconTint ~= false, _features = 0, _pendingIcons = 0,
		ToggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift,
	}, Window)
	self.Window = w

	-- root: fixed 650x450
	local main = new("Frame", {
		Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(650, 450), BackgroundTransparency = 1,
	}, g)
	new("UIScale", {Name = "Pop"}, main)
	local win = new("Frame", {Name = "Window", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BorderSizePixel = 0}, main)
	corner(win, 18)
	hairline(win, 0.88)
	w.Main, w._window = main, win

	-- header
	local header = new("Frame", {Name = "Header", Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1}, win)
	local crumb = new("Frame", {
		Name = "Breadcrumb", Position = UDim2.new(0, 86, 0, 0), Size = UDim2.new(1, -310, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true,
	}, header)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
	}, crumb)
	local titleLabel = label(crumb, {
		Name = "Title", Text = cfg.Title or "Neptune", Font = FONT_BOLD, TextSize = 22, TextColor3 = Theme.Accent,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	new("UISizeConstraint", {MaxSize = Vector2.new(200, math.huge)}, titleLabel)
	label(crumb, {
		Name = "Sep", Text = "›", TextSize = 24, TextColor3 = Theme.Dim, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, -2), LayoutOrder = 2,
	})
	local subtitle = label(crumb, {
		Name = "Subtitle", Text = "", Font = FONT_BOLD, TextSize = 22, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 3,
	})
	w.TitleLabel, w.Subtitle = titleLabel, subtitle
	onAccent(function(color)
		if titleLabel.Parent then
			titleLabel.TextColor3 = color
		end
	end)

	new("Frame", {
		Name = "Divider", Position = UDim2.new(0, 82, 1, 0), Size = UDim2.new(1, -98, 0, 1),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0,
	}, header)

	local search = new("TextBox", {
		Name = "Search", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(190, 32),
		BackgroundColor3 = Theme.Card, BorderSizePixel = 0, Text = "", PlaceholderText = "Search...", PlaceholderColor3 = Theme.Dim,
		TextColor3 = Theme.Text, TextSize = 16, Font = FONT, TextXAlignment = LEFT, ClearTextOnFocus = false,
	}, header)
	corner(search, UDim.new(1, 0))
	hairline(search, 0.9)
	new("UIPadding", {PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 12)}, search)
	w._search = search
	search:GetPropertyChangedSignal("Text"):Connect(function()
		w:_filter(w.ActiveTab, search.Text)
	end)

	-- content area + footer
	local bottom = cfg.Footer and 92 or 76
	local content = new("Frame", {
		Name = "Content", BackgroundTransparency = 1, Position = UDim2.new(0, 82, 0, 62), Size = UDim2.new(1, -96, 1, -bottom), ClipsDescendants = true,
	}, win)
	w._content = content
	if cfg.Footer then
		label(win, {
			Name = "Footer", Text = cfg.Footer, TextSize = 13, TextColor3 = Theme.Dim, TextXAlignment = RIGHT,
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -8), Size = UDim2.fromOffset(300, 16),
		})
	end

	-- hexagon tabs + tooltip
	local tabsFrame = new("Frame", {Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3}, main)
	w._tabsFrame = tabsFrame
	local tip = new("Frame", {
		Name = "Tooltip", AnchorPoint = Vector2.new(0, 0.5), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(),
		BackgroundColor3 = Theme.Card, BorderSizePixel = 0, Visible = false, ZIndex = 10,
	}, tabsFrame)
	corner(tip, 6)
	hairline(tip, 0.88)
	new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6)}, tip)
	label(tip, {Name = "Text", Text = "", TextSize = 16, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), ZIndex = 11})
	w._tip = tip

	onAccent(function()
		w:_refreshTabs()
	end)

	-- drag the window by its header
	local dragging, dragStart, startPos = false, nil, nil
	header.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if isPress(input) then
			dragging = false
		end
	end)

	-- show / hide key
	connect(UserInputService.InputBegan, function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local tk = Library.ToggleKeybind
		local name = (tk and tk.Value) or w.ToggleKey.Name
		if input.KeyCode.Name == name then
			w:Toggle()
		end
	end)

	if cfg.LoadingScreen then
		w:_createLoadingScreen(g, type(cfg.LoadingScreen) == "table" and cfg.LoadingScreen or {}, cfg)
	end

	return w
end

----------------------------------------------------------------------- config

function Library:ExportConfig()
	local data = {}
	for idx, e in pairs(self.Toggles) do
		if not self.ConfigIgnore[idx] then
			data[idx] = e.Value
		end
	end
	for idx, e in pairs(self.Options) do
		if not self.ConfigIgnore[idx] and e.Type ~= "Label" and e.Type ~= "Button" then
			if e.Type == "Dropdown" and type(e.Value) == "table" then
				local copy = {}
				for k, v in pairs(e.Value) do
					copy[k] = v
				end
				data[idx] = copy
			else
				data[idx] = e.Value
			end
		end
	end
	return data
end

function Library:ImportConfig(data)
	for idx, value in pairs(data) do
		if not self.ConfigIgnore[idx] then
			local e = self.Toggles[idx] or self.Options[idx]
			if e and e.SetValue and e.Type ~= "Label" then
				e:SetValue(value)
			end
		end
	end
end

function Library:ExportConfigJson()
	return HttpService:JSONEncode(self:ExportConfig())
end

function Library:ImportConfigJson(str)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	if ok and type(data) == "table" then
		self:ImportConfig(data)
		return true
	end
	return false
end

local function fsAvailable()
	return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
		and typeof(isfolder) == "function" and typeof(makefolder) == "function"
end

local function configDir()
	return Library.ConfigFolder .. "/configs"
end

local function ensureConfigDir()
	if not isfolder(Library.ConfigFolder) then
		makefolder(Library.ConfigFolder)
	end
	if not isfolder(configDir()) then
		makefolder(configDir())
	end
end

function Library:SaveConfig(name)
	if not fsAvailable() then
		return false, "file functions are not available here"
	end
	if type(name) ~= "string" or name:gsub("%s", "") == "" then
		return false, "give the config a name"
	end
	ensureConfigDir()
	writefile(configDir() .. "/" .. name .. ".json", self:ExportConfigJson())
	return true
end

function Library:LoadConfig(name)
	if not fsAvailable() then
		return false, "file functions are not available here"
	end
	local path = configDir() .. "/" .. tostring(name) .. ".json"
	if not isfile(path) then
		return false, "config not found"
	end
	local ok = self:ImportConfigJson(readfile(path))
	if not ok then
		return false, "config file is invalid"
	end
	return true
end

function Library:ListConfigs()
	local out = {}
	if fsAvailable() and typeof(listfiles) == "function" then
		ensureConfigDir()
		for _, path in ipairs(listfiles(configDir())) do
			local n = path:match("([^/\\]+)%.json$")
			if n then
				table.insert(out, n)
			end
		end
	end
	return out
end

----------------------------------------------------------------------- unload

function Library:OnUnload(fn)
	table.insert(unloadCallbacks, fn)
end

function Library:Unload()
	if self.Unloaded then
		return
	end
	self.Unloaded = true
	for _, fn in ipairs(unloadCallbacks) do
		pcall(fn)
	end
	for _, c in ipairs(connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
	end
	gui = nil
	notifyHost = nil
	self.Window = nil
	if typeof(getgenv) == "function" then
		local env = getgenv()
		if env.NeptuneLibrary == self then
			env.NeptuneLibrary = nil
		end
	end
end

-- running the script again replaces the previous copy instead of stacking windows
if typeof(getgenv) == "function" then
	local env = getgenv()
	if env.NeptuneLibrary and env.NeptuneLibrary ~= Library then
		pcall(function()
			env.NeptuneLibrary:Unload()
		end)
	end
	env.NeptuneLibrary = Library
end

return Library

-- SlightlyBloxyUI.lua
-- Lightweight, Rayfield-compatible (drop-in) UI for Roblox
-- API parity goal: Window/Tab/Section + Elements + Notify + Config save/load
-- License: MIT (adjust as you like)

--[[
USAGE (drop-in):

local Rayfield = require(SlightlyBloxyUI) -- or loadstring(...)
local Window = Rayfield:CreateWindow({
  Name = "Example",
  LoadingTitle = "SlightlyBloxyUI",
  LoadingSubtitle = "Lightweight",
  ShowText = "UI",
  Theme = "Default",
  ConfigurationSaving = { Enabled = true, FolderName = "MyHub", FileName = "Config" },
})

local Tab = Window:CreateTab("Main", 0)
local Section = Tab:CreateSection("Controls")

Tab:CreateButton({ Name = "Hello", Callback = function() print("hi") end })
local tog = Tab:CreateToggle({ Name = "God Mode", CurrentValue = false, Callback = function(v) print("god:", v) end })
local sld = Tab:CreateSlider({ Name = "WalkSpeed", Range = {8, 32}, Increment = 1, CurrentValue = 16, Suffix = "ws", Callback = function(v) print(v) end })

Rayfield:Notify({ Title = "Ready", Content = "SlightlyBloxyUI loaded.", Duration = 3 })
]]

local SlightlyBloxyUI = {}
SlightlyBloxyUI.__index = SlightlyBloxyUI

local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function Signal()
	local bind = Instance.new("BindableEvent")
	return {
		Connect = function(_, fn) return bind.Event:Connect(fn) end,
		Fire = function(_, ...) bind:Fire(...) end,
		Destroy = function(_) bind:Destroy() end,
	}
end

local function create(class, props, children)
	local inst = Instance.new(class)
	for k,v in pairs(props or {}) do inst[k] = v end
	for _,ch in ipairs(children or {}) do ch.Parent = inst end
	return inst
end

local THEME_PRESETS = {
	Default = {
		bg = Color3.fromRGB(18,18,20),
		panel = Color3.fromRGB(28,28,32),
		accent = Color3.fromRGB(90,120,255),
		text = Color3.fromRGB(235,235,240),
		muted = Color3.fromRGB(160,160,170),
	}
}

-- config IO (Studio compatible; uses readfile/writefile if available)
local function canIO()
	return (typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfolder) == "function" and typeof(makefolder) == "function")
end

local function safeWrite(path, data)
	local ok, err
	if canIO() then
		ok, err = pcall(function() writefile(path, data) end)
	else
		ok, err = pcall(function()
			-- Studio fallback: store in a ScreenGui attribute (volatile)
			if SlightlyBloxyUI._Gui then
				SlightlyBloxyUI._Gui:SetAttribute("CFG_"..path, data)
			end
		end)
	end
	return ok, err
end

local function safeRead(path)
	if canIO() then
		local ok, res = pcall(function() return readfile(path) end)
		if ok then return res end
	else
		if SlightlyBloxyUI._Gui then
			return SlightlyBloxyUI._Gui:GetAttribute("CFG_"..path)
		end
	end
	return nil
end

-- Root construction
function SlightlyBloxyUI:CreateWindow(opts)
	opts = opts or {}
	local themeName = opts.Theme or "Default"
	local theme = THEME_PRESETS[themeName] or THEME_PRESETS.Default

	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local rootGui = create("ScreenGui", { Name = "SlightlyBloxyUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	rootGui.Parent = playerGui or game:GetService("CoreGui")
	SlightlyBloxyUI._Gui = rootGui

	-- Topbar + container
	local container = create("Frame", {
		BackgroundColor3 = theme.bg,
		Size = UDim2.new(0, 560, 0, 360),
		Position = UDim2.new(0, 40, 0, 40),
		BorderSizePixel = 0,
		Active = true,
		Draggable = true
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		create("UIStroke", { Color = theme.panel, Thickness = 1 }),
	})
	container.Parent = rootGui

	local titlebar = create("Frame", {
		BackgroundColor3 = theme.panel,
		Size = UDim2.new(1,0,0,32),
		BorderSizePixel = 0,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 10) }),
	})
	titlebar.Parent = container

	local title = create("TextLabel", {
		Text = tostring(opts.Name or "Window"),
		Font = Enum.Font.GothamSemibold,
		TextSize = 16,
		TextColor3 = theme.text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1,-10,1,0),
		Position = UDim2.new(0,10,0,0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	title.Parent = titlebar

	local body = create("Frame", {
		BackgroundColor3 = theme.bg,
		Size = UDim2.new(1, -12, 1, -44),
		Position = UDim2.new(0,6,0,38),
		BorderSizePixel = 0,
	})
	body.Parent = container

	local leftTabs = create("Frame", {
		BackgroundColor3 = theme.panel,
		Size = UDim2.new(0, 140, 1, 0),
		BorderSizePixel = 0,
	})
	leftTabs.Parent = body

	local tabsLayout = create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder })
	tabsLayout.Parent = leftTabs

	local rightPane = create("Frame", {
		BackgroundColor3 = theme.bg,
		Size = UDim2.new(1, -150, 1, 0),
		Position = UDim2.new(0, 150, 0, 0),
		BorderSizePixel = 0,
	})
	rightPane.Parent = body

	local tabContainer = create("Folder", { Name = "Tabs" })
	tabContainer.Parent = rightPane

	local currentTabFrame: Frame

	local window = {}

	local function switchTo(tabFrame)
		for _, f in ipairs(tabContainer:GetChildren()) do
			if f:IsA("Frame") then f.Visible = (f == tabFrame) end
		end
		currentTabFrame = tabFrame
	end

	function window:CreateTab(name, icon)
		local btn = create("TextButton", {
			Text = tostring(name),
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextColor3 = theme.text,
			BackgroundColor3 = theme.panel,
			AutoButtonColor = true,
			Size = UDim2.new(1, -12, 0, 28),
		})
		btn.Parent = leftTabs

		local tabFrame = create("Frame", {
			Name = "Tab_"..name,
			BackgroundTransparency = 1,
			Size = UDim2.new(1,0,1,0),
			Visible = false,
		})
		tabFrame.Parent = tabContainer

		local scroller = create("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -10, 1, -10),
			Position = UDim2.new(0,5,0,5),
			CanvasSize = UDim2.new(0,0,0,0),
			ScrollBarImageTransparency = 0.6
		})
		scroller.Parent = tabFrame
		create("UIListLayout", { Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller })

		btn.MouseButton1Click:Connect(function()
			switchTo(tabFrame)
		end)

		local tab = {}

		function tab:CreateSection(secName)
			local section = create("Frame", {
				BackgroundColor3 = theme.panel,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 36),
			})
			section.Parent = scroller
			create("UICorner", { CornerRadius = UDim.new(0,8), Parent = section })
			local lbl = create("TextLabel", {
				Text = tostring(secName or "Section"),
				Font = Enum.Font.GothamSemibold,
				TextSize = 14,
				TextColor3 = theme.text,
				BackgroundTransparency = 1,
				Size = UDim2.new(1,-10,1,0),
				Position = UDim2.new(0,10,0,0),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			lbl.Parent = section
			return section
		end

		local function rowBase(name, height)
			local frame = create("Frame", { BackgroundColor3 = theme.panel, Size = UDim2.new(1,-8,0,height or 38), BorderSizePixel = 0 })
			create("UICorner", { CornerRadius = UDim.new(0,8), Parent = frame })
			local label = create("TextLabel", { Text = tostring(name or ""), Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = theme.text, BackgroundTransparency = 1, Size = UDim2.new(1,-12,1,0), Position = UDim2.new(0,12,0,0), TextXAlignment = Enum.TextXAlignment.Left })
			label.Parent = frame
			return frame, label
		end

		function tab:CreateLabel(text)
			local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1,-8,0,24) })
			row.Parent = scroller
			local lbl = create("TextLabel", { Text = tostring(text or ""), Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = theme.muted, BackgroundTransparency = 1, Size = UDim2.new(1,-8,1,0), Position = UDim2.new(0,8,0,0), TextXAlignment = Enum.TextXAlignment.Left })
			lbl.Parent = row
			return { Set = function(_, t) lbl.Text = t end }
		end

		function tab:CreateParagraph(cfg)
			cfg = cfg or {}
			local row, _ = rowBase(cfg.Title or "Paragraph", 64)
			row.Parent = scroller
			local content = create("TextLabel", { Text = tostring(cfg.Content or ""), Font = Enum.Font.Gotham, TextWrapped = true, TextSize = 13, TextColor3 = theme.muted, BackgroundTransparency = 1, Size = UDim2.new(1,-12,1,-20), Position = UDim2.new(0,12,0,20), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
			content.Parent = row
			return { Set = function(_, txt) content.Text = txt end }
		end

		function tab:CreateButton(cfg)
			cfg = cfg or {}
			local row, label = rowBase(cfg.Name or "Button")
			row.Parent = scroller
			local btn = create("TextButton", { Text = cfg.Interact or "Run", Size = UDim2.new(0,80,0,28), Position = UDim2.new(1,-92,0.5,-14), AnchorPoint = Vector2.new(0,0), BackgroundColor3 = theme.accent, TextColor3 = Color3.new(1,1,1), Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = true })
			create("UICorner", { CornerRadius = UDim.new(0,6), Parent = btn })
			btn.Parent = row
			btn.MouseButton1Click:Connect(function()
				if typeof(cfg.Callback) == "function" then cfg.Callback() end
			end)
			return {
				Set = function(_, name) label.Text = name end,
				SetInteract = function(_, t) btn.Text = t end,
			}
		end

		function tab:CreateToggle(cfg)
			cfg = cfg or {}
			local state = not not cfg.CurrentValue
			local row, label = rowBase(cfg.Name or "Toggle")
			row.Parent = scroller
			local knob = create("TextButton", { Text = state and "ON" or "OFF", Size = UDim2.new(0,56,0,24), Position = UDim2.new(1,-68,0.5,-12), BackgroundColor3 = state and theme.accent or theme.panel, TextColor3 = theme.text, Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = true })
			create("UICorner", { CornerRadius = UDim.new(0,6), Parent = knob })
			knob.Parent = row
			local sig = Signal()
			local function set(v)
				state = not not v
				knob.Text = state and "ON" or "OFF"
				knob.BackgroundColor3 = state and theme.accent or theme.panel
				if typeof(cfg.Callback) == "function" then cfg.Callback(state) end
				sig:Fire(state)
			end
			knob.MouseButton1Click:Connect(function() set(not state) end)
			return {
				CurrentValue = function() return state end,
				Set = function(_, v) set(v) end,
				OnChanged = sig,
			}
		end

		function tab:CreateSlider(cfg)
			cfg = cfg or {}
			local r0, r1 = unpack(cfg.Range or {0,100})
			local inc = cfg.Increment or 1
			local val = math.clamp(cfg.CurrentValue or r0, r0, r1)
			local row, label = rowBase((cfg.Name or "Slider") .. (cfg.Suffix and (" ["..cfg.Suffix.."]") or ""), 56)
			row.Parent = scroller
			local bar = create("Frame", { BackgroundColor3 = theme.panel, Size = UDim2.new(1,-160,0,6), Position = UDim2.new(0,12,0,34), BorderSizePixel = 0 })
			create("UICorner", { CornerRadius = UDim.new(0,3), Parent = bar })
			bar.Parent = row
			local fill = create("Frame", { BackgroundColor3 = theme.accent, Size = UDim2.new((val-r0)/(r1-r0),0,1,0), BorderSizePixel = 0 })
			create("UICorner", { CornerRadius = UDim.new(0,3), Parent = fill })
			fill.Parent = bar
			local valueLbl = create("TextLabel", { Text = tostring(val), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = theme.text, BackgroundTransparency = 1, Size = UDim2.new(0,60,0,20), Position = UDim2.new(1,-70,0,24), TextXAlignment = Enum.TextXAlignment.Right })
			valueLbl.Parent = row
			local dragging = false
			local function applyFromX(x)
				local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
				local raw = r0 + rel * (r1 - r0)
				local snapped = math.floor((raw + inc*0.5) / inc) * inc
				val = math.clamp(snapped, r0, r1)
				fill.Size = UDim2.new((val-r0)/(r1-r0),0,1,0)
				valueLbl.Text = tostring(val)
				if typeof(cfg.Callback) == "function" then cfg.Callback(val) end
			end
			bar.InputBegan:Connect(function(io)
				if io.UserInputType.Name == "MouseButton1" or io.UserInputType.Name == "Touch" then
					dragging = true; applyFromX(io.Position.X)
				end
			end)
			bar.InputEnded:Connect(function(io)
				if io.UserInputType.Name == "MouseButton1" or io.UserInputType.Name == "Touch" then dragging = false end
			end)
			RunService.RenderStepped:Connect(function()
				if dragging then applyFromX(game:GetService("UserInputService").GetMouseLocation(game:GetService("UserInputService")).X) end
			end)
			return {
				Set = function(_, v) applyFromX(bar.AbsolutePosition.X + (math.clamp(v, r0, r1)-r0)/(r1-r0)*bar.AbsoluteSize.X) end,
				CurrentValue = function() return val end,
			}
		end

		function tab:CreateDropdown(cfg)
			cfg = cfg or {}; cfg.Options = cfg.Options or {}
			local sel = cfg.CurrentOption or cfg.Options[1]
			local row, label = rowBase(cfg.Name or "Dropdown")
			row.Parent = scroller
			local btn = create("TextButton", { Text = sel and tostring(sel) or "Select", Size = UDim2.new(0,140,0,24), Position = UDim2.new(1,-152,0.5,-12), BackgroundColor3 = theme.panel, TextColor3 = theme.text, Font = Enum.Font.Gotham, TextSize = 12, AutoButtonColor = true })
			create("UICorner", { CornerRadius = UDim.new(0,6), Parent = btn })
			btn.Parent = row
			local open = false
			local list
			local function set(v)
				sel = v; btn.Text = tostring(v)
				if typeof(cfg.Callback) == "function" then cfg.Callback(v) end
			end
			btn.MouseButton1Click:Connect(function()
				open = not open
				if open then
					if list then list:Destroy() end
					list = create("Frame", { BackgroundColor3 = theme.panel, Size = UDim2.new(0,140,0, math.min(140, (#cfg.Options)*24 + 8)), Position = UDim2.new(1,-152,0, 36), BorderSizePixel = 0 })
					create("UICorner", { CornerRadius = UDim.new(0,6), Parent = list })
					list.Parent = row
					local lay = create("UIListLayout", { Padding = UDim.new(0,4), SortOrder = Enum.SortOrder.LayoutOrder })
					lay.Parent = list
					for _,opt in ipairs(cfg.Options) do
						local o = create("TextButton", { Text = tostring(opt), BackgroundColor3 = theme.bg, TextColor3 = theme.text, Font = Enum.Font.Gotham, TextSize = 12, Size = UDim2.new(1,-8,0,24) })
						create("UICorner", { CornerRadius = UDim.new(0,4), Parent = o })
						o.Parent = list
						o.MouseButton1Click:Connect(function()
							set(opt)
							open = false
							if list then list:Destroy() end
						end)
					end
				else
					if list then list:Destroy() end
				end
			end)
			return {
				Set = function(_, v) set(v) end,
				AddOption = function(_, v) table.insert(cfg.Options, v) end,
				RemoveOption = function(_, v)
					for i,x in ipairs(cfg.Options) do if x==v then table.remove(cfg.Options, i) break end end
				end
			}
		end

		function tab:CreateInput(cfg)
			cfg = cfg or {}
			local text = cfg.CurrentValue or ""
			local row, label = rowBase(cfg.Name or "Input")
			row.Parent = scroller
			local box = create("TextBox", { PlaceholderText = cfg.PlaceholderText or "", Text = text, Size = UDim2.new(0,200,0,24), Position = UDim2.new(1,-212,0.5,-12), BackgroundColor3 = theme.panel, TextColor3 = theme.text, Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false })
			create("UICorner", { CornerRadius = UDim.new(0,6), Parent = box })
			box.Parent = row
			box.FocusLost:Connect(function()
				text = box.Text
				if typeof(cfg.Callback) == "function" then cfg.Callback(text) end
			end)
			return { Set = function(_, v) text=v; box.Text=v end, Get = function() return text end }
		end

		function tab:CreateKeybind(cfg)
			cfg = cfg or {}
			local key = cfg.CurrentKeybind or Enum.KeyCode.RightShift
			local row, label = rowBase(cfg.Name or "Keybind")
			row.Parent = scroller
			local btn = create("TextButton", { Text = key.Name, Size = UDim2.new(0,120,0,24), Position = UDim2.new(1,-132,0.5,-12), BackgroundColor3 = theme.panel, TextColor3 = theme.text, Font = Enum.Font.Gotham, TextSize = 12 })
			create("UICorner", { CornerRadius = UDim.new(0,6), Parent = btn })
			btn.Parent = row
			local capturing = false
			btn.MouseButton1Click:Connect(function()
				capturing = true
				btn.Text = "Press key..."
			end)
			game:GetService("UserInputService").InputBegan:Connect(function(input, gpe)
				if gpe then return end
				if capturing and input.KeyCode ~= Enum.KeyCode.Unknown then
					key = input.KeyCode
					btn.Text = key.Name
					capturing = false
					if typeof(cfg.Callback) == "function" then cfg.Callback(key) end
				elseif input.KeyCode == key then
					if typeof(cfg.Pressed) == "function" then cfg.Pressed() end
				end
			end)
			return { Set = function(_, kc) key = kc; btn.Text = kc.Name end, Get = function() return key end }
		end

		function tab:CreateColorPicker(cfg)
			cfg = cfg or {}
			local col = cfg.CurrentColor or Color3.new(1,1,1)
			local row, label = rowBase(cfg.Name or "Color")
			row.Parent = scroller
			local swatch = create("TextButton", { Text = " ", Size = UDim2.new(0,40,0,24), Position = UDim2.new(1,-52,0.5,-12), BackgroundColor3 = col })
			create("UICorner", { CornerRadius = UDim.new(0,6), Parent = swatch })
			swatch.Parent = row
			swatch.MouseButton1Click:Connect(function()
				-- ultra simple hue cycle picker
				local h,s,v = Color3.toHSV(col)
				h = (h + 0.1) % 1
				col = Color3.fromHSV(h,s,v)
				swatch.BackgroundColor3 = col
				if typeof(cfg.Callback) == "function" then cfg.Callback(col) end
			end)
			return { Set = function(_, c) col=c; swatch.BackgroundColor3=c end, Get = function() return col end }
		end

		-- helpers to align with Rayfield expectations
		tab.CreateParagraph = tab.CreateParagraph
		tab.CreateLabel = tab.CreateLabel

		return tab
	end

	function window:Destroy()
		if rootGui then rootGui:Destroy() end
	end

	-- Config Save/Load (basic):
	local cfg = opts.ConfigurationSaving or { Enabled = false }
	function SlightlyBloxyUI:SaveConfiguration()
		if not cfg.Enabled then return end
		local folder = (cfg.FolderName or "SlightlyBloxyUI"); local file = (cfg.FileName or "Config")..".json"
		local path = folder.."/"..file
		if canIO() and not isfolder(folder) then makefolder(folder) end
		local data = { Theme = themeName }
		local ok, err = safeWrite(path, HttpService:JSONEncode(data))
		if not ok then warn("SaveConfiguration failed:", err) end
	end

	function SlightlyBloxyUI:LoadConfiguration()
		if not cfg.Enabled then return end
		local folder = (cfg.FolderName or "SlightlyBloxyUI"); local file = (cfg.FileName or "Config")..".json"
		local path = folder.."/"..file
		local json = safeRead(path)
		if not json then return end
		local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
		if ok and data and data.Theme then
			-- in this lightweight build theme swap is minimal
		end
	end

	-- Public Rayfield-like methods
	function SlightlyBloxyUI:CreateWindowProxy() return window end

	-- return window object like Rayfield
	return window
end

function SlightlyBloxyUI:Notify(cfg)
	cfg = cfg or {}
	-- best-effort using Roblox SetCore (works in most executors/studio)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = tostring(cfg.Title or "Notification"),
			Text = tostring(cfg.Content or ""),
			Duration = tonumber(cfg.Duration or 3)
		})
	end)
end

function SlightlyBloxyUI:Destroy()
	if SlightlyBloxyUI._Gui then SlightlyBloxyUI._Gui:Destroy() SlightlyBloxyUI._Gui=nil end
end

return setmetatable({}, SlightlyBloxyUI)

-- Toolkit/ui/framework.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local Players, UserInputService, Workspace, Lighting, HttpService, TextService = S.Players, S.UserInputService, S.Workspace, S.Lighting, S.HttpService, S.TextService
local LocalPlayer, Config, FONT, FONT_BOLD, logError, Toolkit = S.LocalPlayer, S.Config, S.FONT, S.FONT_BOLD, S.logError, S.Toolkit
local connections, rootMaid, anim, new, GuiRoot, copyToClipboard = S.connections, S.rootMaid, S.anim, S.new, S.GuiRoot, S.copyToClipboard
local ModuleList, Selected, Bind, Controls, listenModules, setModule = S.ModuleList, S.Selected, S.Bind, S.Controls, S.listenModules, S.setModule
local getSelectedPlayer, FFlags, ScriptProfiles = S.getSelectedPlayer, S.FFlags, S.ScriptProfiles

-- ======================================================================================
-- F. UI framework
-- ======================================================================================

local function buildUi()
	local T, A, L = Config.Theme, Config.Anim, Config.Layout
	local WIDTH = L.CardWidth * 2 + L.Gap
	local HEADER = L.CardHeader
	local ROW_GAP, PAD_X, PAD_TOP, PAD_BOTTOM = 6, 14, 10, 12

	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local fit = math.min(1, (viewport.X - 24) / WIDTH)
	local maxHeight = math.clamp(math.floor((viewport.Y - 36) / fit) - L.HeaderBar - 20, 160, L.MaxPanelHeight)

	local function corner(parent, radius)
		return new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
	end
	local function stroke(parent, color, transparency)
		return new("UIStroke", {
			Color = color, Thickness = 1, Transparency = transparency or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, parent)
	end
	local function text(parent, props)
		local merged = {
			BackgroundTransparency = 1, Font = FONT, TextSize = 14, TextColor3 = T.Title,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "",
		}
		for key, value in pairs(props) do
			merged[key] = value
		end
		return new("TextLabel", merged, parent)
	end
	local function isPointer(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	-- Screen, backdrop glass, blur ------------------------------------------------------
	local screen = rootMaid:Add(new("ScreenGui", {
		Name = "ToolkitUi", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
	}, GuiRoot))
	local backdrop = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Backdrop, BackgroundTransparency = 1,
		BorderSizePixel = 0, Active = true,
	}, screen)
	local blur = rootMaid:Add(new("BlurEffect", { Size = 0 }, Lighting))
	-- Modal button: lets the mouse move freely while the menu is open (first person / shift lock)
	new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Modal = true }, screen)

	local root = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(WIDTH, 0), BackgroundTransparency = 1,
	}, screen)
	local rootScale = new("UIScale", { Scale = fit }, root)

	-- Global drag manager (sliders, color bars, window) ------------------------------------
	local activeDrag
	local dragSaves = false -- slider / color drags save when released; moving the window does not
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if
			activeDrag
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			activeDrag(input.Position)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then
			local saveNow = activeDrag ~= nil and dragSaves
			activeDrag = nil
			if saveNow then
				Toolkit.RequestSave() -- one write on release, never while dragging
			end
		end
	end))

	-- Header pill ------------------------------------------------------------------------
	local header = new("Frame", {
		Size = UDim2.new(1, 0, 0, L.HeaderBar), BackgroundColor3 = T.Header, BorderSizePixel = 0,
	}, root)
	corner(header, 14)
	local headerStroke = stroke(header, T.Outline, 0.4)

	local TAB_NAMES = { "Combat", "Move", "Visual", "Utility", "FFlags", "Profiles" }
	local SEARCH_W = 44
	local cellCount = #TAB_NAMES + 1 -- + Unload
	local cellW = (WIDTH - SEARCH_W) / cellCount
	local tabIndex = {}
	local headerTexts = {}

	local activePill = new("Frame", {
		BackgroundColor3 = T.Pill, BorderSizePixel = 0, ZIndex = 1,
		Size = UDim2.fromOffset(cellW - 8, L.HeaderBar - 10), Position = UDim2.fromOffset(4, 5),
	}, header)
	corner(activePill, 12)

	-- page state shared by tab switching and search
	local pages, cards = {}, {}
	local activeTab
	local pillTarget = 0
	local tabAlpha, modalAlpha = 1, 0

	local content = new("Frame", {
		Position = UDim2.fromOffset(0, L.HeaderBar + 8), Size = UDim2.fromOffset(WIDTH, 0),
		BackgroundTransparency = 1, ClipsDescendants = true,
	}, root)

	local function applyPageAlpha()
		local page = pages[activeTab]
		if page and page.isGroup then
			page.group.GroupTransparency = 1 - tabAlpha * modalAlpha
		end
	end

	local pillFollower = anim.newFollower(0, A.FollowFast, function(x)
		activePill.Position = UDim2.fromOffset(x + 4, 5)
		local page = pages[activeTab]
		if page and tabIndex[activeTab] then
			-- page slides in by the remaining pill distance and fades in as the pill arrives
			local remaining = x - pillTarget
			page.group.Position = UDim2.fromOffset(remaining * A.PageSlide, 0)
			tabAlpha = 1 - math.clamp(math.abs(remaining) / 160, 0, 1)
			applyPageAlpha()
		end
	end, 0.1)

	-- Pages ------------------------------------------------------------------------------
	local contentFollower = anim.newFollower(0, A.FollowCard, function(h)
		content.Size = UDim2.fromOffset(WIDTH, math.floor(h + 0.5))
	end, 0.5)

	local function measurePage(page)
		local height = 0
		for _, column in ipairs(page.columns) do
			local columnHeight, count = 0, 0
			for _, child in ipairs(column:GetChildren()) do
				if child:IsA("Frame") then
					columnHeight += child.Size.Y.Offset
					count += 1
				end
			end
			if count > 1 then
				columnHeight += (count - 1) * L.Gap
			end
			height = math.max(height, columnHeight)
		end
		return height
	end

	local function updateContentTarget()
		local page = pages[activeTab]
		if not page then
			return
		end
		local height = measurePage(page)
		page.scroll.CanvasSize = UDim2.fromOffset(0, height)
		contentFollower.Set(math.min(maxHeight, height))
	end

	local function createPage(name, wide)
		local group = new(Config.UseCanvasGroup and "CanvasGroup" or "Frame", {
			Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false,
		}, content)
		local scroll = new("ScrollingFrame", {
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
			ScrollBarThickness = 2, ScrollBarImageColor3 = T.Outline, ScrollingDirection = Enum.ScrollingDirection.Y,
		}, group)
		local columns = {}
		local columnWidth = wide and WIDTH or (WIDTH - L.Gap) / 2
		for index = 1, wide and 1 or 2 do
			columns[index] = new("Frame", {
				BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y,
				Position = UDim2.fromOffset((index - 1) * (columnWidth + L.Gap), 0), Size = UDim2.fromOffset(columnWidth, 0),
			}, scroll)
			new("UIListLayout", { Padding = UDim.new(0, L.Gap), SortOrder = Enum.SortOrder.LayoutOrder }, columns[index])
		end
		pages[name] = {
			name = name, group = group, scroll = scroll, columns = columns, count = 0,
			isGroup = Config.UseCanvasGroup, columnWidth = columnWidth,
		}
	end

	for index, name in ipairs(TAB_NAMES) do
		tabIndex[name] = index
		createPage(name, name == "FFlags" or name == "Profiles")
	end
	createPage("Search", false)

	local function selectTab(name, instant)
		if activeTab == name and not instant then
			return
		end
		local old = pages[activeTab]
		if old then
			old.group.Visible = false
			old.group.Position = UDim2.fromOffset(0, 0)
		end
		activeTab = name
		pages[name].group.Visible = true
		local index = tabIndex[name]
		activePill.Visible = index ~= nil
		if index then
			pillTarget = (index - 1) * cellW
			pillFollower.Set(pillTarget, instant)
		else
			tabAlpha = 1
			applyPageAlpha()
		end
		updateContentTarget()
	end

	-- Switch ---------------------------------------------------------------------------
	local function buildSwitch(parent, position, anchor, initial, onChange)
		local W, H = 36, 20
		local pill = new("TextButton", {
			Text = "", AutoButtonColor = false, AnchorPoint = anchor, Position = position,
			Size = UDim2.fromOffset(W, H), BackgroundColor3 = T.SwitchOff, BorderSizePixel = 0,
		}, parent)
		corner(pill, 10)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = T.Knob, BorderSizePixel = 0,
		}, pill)
		corner(knob, 7)
		local progress, value, handle = 0, false, nil
		local function render(p)
			progress = p
			pill.BackgroundColor3 = T.SwitchOff:Lerp(T.Accent, p)
			knob.Position = UDim2.fromOffset(3 + (W - 17) * p, H / 2)
		end
		local api = {}
		-- 0.10 s sine in/out, restarted from the current progress so rapid clicks never jump
		function api.Set(newValue, instant)
			newValue = newValue and true or false
			value = newValue
			if handle then
				handle.cancelled = true
			end
			local from, to = progress, newValue and 1 or 0
			if instant then
				render(to)
				return
			end
			handle = anim.run(A.SwitchTime, anim.sineInOut, function(e)
				render(from + (to - from) * e)
			end)
		end
		pill.Activated:Connect(function()
			onChange(not value)
		end)
		api.Set(initial, true)
		return api
	end

	-- Row builders for card bodies ------------------------------------------------------
	local refreshers = {}

	local function makeUi(inner, innerWidth, module)
		local ui = {}
		local y = 0
		local function addRow(height)
			local row = new("Frame", {
				BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height),
			}, inner)
			y += height + ROW_GAP
			return row
		end
		function ui.Height()
			if y == 0 then
				return 0
			end
			return y - ROW_GAP + PAD_TOP + PAD_BOTTOM
		end
		function ui.Row(height)
			return addRow(height)
		end
		local function rowLabel(row, str, width)
			return text(row, { Size = UDim2.new(width or 0.5, 0, 1, 0), TextSize = 13, RichText = true, Text = str })
		end
		local function register(labelText, control)
			if module then
				Controls[module.id .. "." .. labelText] = control
			end
		end

		function ui.Toggle(labelText, key)
			local cfg = module.cfg
			local row = addRow(24)
			rowLabel(row, labelText)
			local switch
			switch = buildSwitch(row, UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5), cfg[key], function(value)
				cfg[key] = value
				switch.Set(value)
				Toolkit.RequestSave()
			end)
			register(labelText, {
				get = function() return cfg[key] end,
				set = function(value)
					if type(value) == "boolean" then
						cfg[key] = value
						switch.Set(value, true)
					end
				end,
			})
		end

		function ui.Slider(labelText, key, min, max, step)
			local cfg = module.cfg
			local decimals = 0
			if step < 1 then
				decimals = math.ceil(-math.log10(step) - 1e-9)
			end
			local row = addRow(28)
			local title = rowLabel(row, "", 0.45)
			local hit = new("TextButton", {
				Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.52, 0, 1, 0),
			}, row)
			local track = new("Frame", {
				BackgroundColor3 = T.SwitchOff, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 3),
			}, hit)
			corner(track, 2)
			local fill = new("Frame", { BackgroundColor3 = T.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, track)
			corner(fill, 2)
			local knob = new("Frame", {
				BackgroundColor3 = T.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(10, 10),
			}, track)
			corner(knob, 5)

			local function snap(value)
				value = math.clamp(value, min, max)
				value = min + math.floor((value - min) / step + 0.5) * step
				return tonumber(string.format("%." .. decimals .. "f", math.clamp(value, min, max)))
			end
			local function render(value)
				local alpha = (value - min) / (max - min)
				fill.Size = UDim2.fromScale(alpha, 1)
				knob.Position = UDim2.fromScale(alpha, 0.5)
				title.Text = string.format(
					'%s  <font color="#999999">%s</font>', labelText, string.format("%." .. decimals .. "f", value)
				)
			end
			local function commit(value)
				value = snap(value)
				cfg[key] = value
				render(value)
			end
			local function fromX(x)
				local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
				commit(min + alpha * (max - min))
			end
			hit.InputBegan:Connect(function(input)
				if isPointer(input) then
					fromX(input.Position.X)
					activeDrag = function(position)
						fromX(position.X)
					end
					dragSaves = true
				end
			end)
			commit(cfg[key])
			register(labelText, {
				get = function() return cfg[key] end,
				set = function(value)
					if type(value) == "number" and value == value then
						commit(value)
					end
				end,
			})
		end

		function ui.Cycle(labelText, getOptions, getValue, setValue)
			local row = addRow(26)
			rowLabel(row, labelText, 0.4)
			local button = new("TextButton", {
				AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.new(0.58, 0, 0, 22), BackgroundColor3 = T.Input, Font = FONT, Text = "",
				TextColor3 = T.Title, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
			}, row)
			corner(button, 11)
			stroke(button, T.Outline)
			local api = {}
			function api.Refresh()
				button.Text = tostring(getValue() or "(none)")
			end
			button.Activated:Connect(function()
				local options = getOptions()
				if #options == 0 then
					api.Refresh()
					return
				end
				local current = getValue()
				local index = current and table.find(options, current) or 0
				setValue(options[index % #options + 1])
				Toolkit.RefreshControls()
				Toolkit.RequestSave()
			end)
			api.Refresh()
			table.insert(refreshers, api.Refresh)
			return api
		end

		function ui.Choice(labelText, key, options)
			local cfg = module.cfg
			local api = ui.Cycle(labelText, function() return options end, function() return cfg[key] end, function(value)
				cfg[key] = value
			end)
			register(labelText, {
				get = function() return cfg[key] end,
				set = function(value)
					if table.find(options, value) then
						cfg[key] = value
						api.Refresh()
					end
				end,
			})
		end

		function ui.Picker(labelText)
			return ui.Cycle(labelText, function()
				local names = {}
				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= LocalPlayer then
						table.insert(names, player.Name)
					end
				end
				table.sort(names, function(a, b)
					return string.lower(a) < string.lower(b)
				end)
				return names
			end, function()
				local player = getSelectedPlayer()
				return player and player.Name
			end, function(value)
				Selected.Target = value
			end)
		end

		function ui.Color(labelText, key)
			local cfg = module.cfg
			local row = addRow(26)
			rowLabel(row, labelText, 0.4)
			local bar = new("TextButton", {
				Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.new(0.58, 0, 0, 16), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			}, row)
			corner(bar, 8)
			local keypoints = {}
			for i = 0, 6 do
				table.insert(keypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.85, 1)))
			end
			new("UIGradient", { Color = ColorSequence.new(keypoints) }, bar)
			local marker = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
				Position = UDim2.fromScale(math.clamp(cfg[key], 0, 1), 0.5), Size = UDim2.fromOffset(4, 22), ZIndex = 2,
			}, bar)
			corner(marker, 2)
			stroke(marker, Color3.new(0, 0, 0))
			local function setHue(hue)
				hue = math.clamp(hue, 0, 1)
				cfg[key] = hue
				marker.Position = UDim2.fromScale(hue, 0.5)
			end
			local function fromX(x)
				setHue((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1))
			end
			bar.InputBegan:Connect(function(input)
				if isPointer(input) then
					fromX(input.Position.X)
					activeDrag = function(position)
						fromX(position.X)
					end
					dragSaves = true
				end
			end)
			register(labelText, {
				get = function() return cfg[key] end,
				set = function(value)
					if type(value) == "number" and value == value then
						setHue(value)
					end
				end,
			})
		end

		function ui.Text(labelText, key, placeholder)
			local cfg = module.cfg
			local row = addRow(28)
			rowLabel(row, labelText, 0.35)
			local box = new("TextBox", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.62, 0, 1, 0),
				BackgroundColor3 = T.Input, BorderSizePixel = 0, ClearTextOnFocus = false, Font = FONT,
				PlaceholderText = placeholder or "", PlaceholderColor3 = T.Desc, Text = tostring(cfg[key] or ""),
				TextColor3 = T.Title, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, row)
			corner(box, 10)
			stroke(box, T.Outline)
			new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
			box.FocusLost:Connect(function()
				cfg[key] = box.Text
				Toolkit.RequestSave()
			end)
			register(labelText, {
				get = function() return cfg[key] end,
				set = function(value)
					if type(value) == "string" then
						cfg[key] = value
						box.Text = value
					end
				end,
			})
		end

		function ui.Button(labelText, callback)
			local row = addRow(28)
			local button = new("TextButton", {
				Text = labelText, AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Input,
				BorderSizePixel = 0, Font = FONT, TextColor3 = T.Title, TextSize = 13,
			}, row)
			corner(button, 8)
			stroke(button, T.Outline)
			local hover = anim.newFollower(0, A.FollowFast, function(v)
				button.BackgroundColor3 = T.Input:Lerp(T.Pill, v)
			end, 0.01)
			button.MouseEnter:Connect(function() hover.Set(1) end)
			button.MouseLeave:Connect(function() hover.Set(0) end)
			button.Activated:Connect(function()
				button.BackgroundColor3 = T.Accent
				task.spawn(function()
					local ok, err = pcall(callback)
					if not ok then
						logError("button " .. labelText, err)
					end
				end)
			end)
			return button
		end

		function ui.Note(str)
			local size = TextService:GetTextSize(str, 11, FONT, Vector2.new(math.max(innerWidth, 50), 1000))
			local row = addRow(math.max(14, size.Y + 2))
			text(row, {
				Size = UDim2.fromScale(1, 1), TextSize = 11, TextColor3 = T.Desc, TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top, Text = str,
			})
		end

		function ui.Input(placeholder, onSubmit, withPlus)
			local row = addRow(28)
			local box = new("TextBox", {
				Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Input, BorderSizePixel = 0, ClearTextOnFocus = false,
				Font = FONT, PlaceholderText = placeholder, PlaceholderColor3 = T.Desc, Text = "",
				TextColor3 = T.Title, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
			}, row)
			corner(box, 8)
			stroke(box, T.Outline)
			new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, withPlus and 30 or 10) }, box)
			if withPlus then
				local plus = new("TextButton", {
					Text = "+", AutoButtonColor = false, BackgroundTransparency = 1, Font = FONT_BOLD, TextSize = 16,
					TextColor3 = T.Title, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
					Size = UDim2.new(0, 28, 1, 0),
				}, row)
				plus.Activated:Connect(function()
					onSubmit(box.Text)
				end)
			end
			box.FocusLost:Connect(function(enterPressed)
				if enterPressed then
					onSubmit(box.Text)
				end
			end)
			return box
		end

		function ui.LabeledInput(labelText, placeholder)
			local row = addRow(28)
			rowLabel(row, labelText, 0.35)
			local box = new("TextBox", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.62, 0, 1, 0),
				BackgroundColor3 = T.Input, BorderSizePixel = 0, ClearTextOnFocus = false, Font = FONT,
				PlaceholderText = placeholder, PlaceholderColor3 = T.Desc, Text = "", TextColor3 = T.Title,
				TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			}, row)
			corner(box, 10)
			stroke(box, T.Outline)
			new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
			return box
		end

		return ui
	end

	-- Card ---------------------------------------------------------------------------------
	local function refreshBinds()
		for _, m in ipairs(ModuleList) do
			local record = cards[m.id]
			if record and record.badge then
				if Bind.listening == m.id then
					record.badge.Text = "..."
					record.badge.TextColor3 = T.Accent
				elseif m.bind then
					record.badge.Text = m.bind.Name
					record.badge.TextColor3 = T.Accent
				else
					record.badge.Text = "NONE"
					record.badge.TextColor3 = T.Desc
				end
			end
		end
	end

	local function buildCard(page, column, spec)
		local record = { page = page, home = column, order = spec.order or 0 }
		local expanded = spec.alwaysOpen or false
		local bodyHeight = 0
		local innerWidth = page.columnWidth - PAD_X * 2

		local frame = new("Frame", {
			Name = spec.id, BackgroundColor3 = T.Card, BorderSizePixel = 0, ClipsDescendants = true,
			LayoutOrder = record.order, Size = UDim2.new(1, 0, 0, HEADER),
		}, column)
		corner(frame, 10)
		stroke(frame, T.Outline, 0.2)
		record.frame = frame

		-- card height follows its target with the card decay rate (about 0.3 s, no tween objects)
		local heightFollower = anim.newFollower(HEADER, A.FollowCard, function(h)
			frame.Size = UDim2.new(1, 0, 0, math.floor(h + 0.5))
			updateContentTarget()
		end, 0.5)

		local titleRow = new("Frame", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(PAD_X, 8), Size = UDim2.new(1, -80, 0, 18),
		}, frame)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
		}, titleRow)
		text(titleRow, {
			LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18),
			Font = FONT_BOLD, TextSize = 15, Text = spec.title,
		})
		if spec.onBadge then
			record.badge = new("TextButton", {
				AutoButtonColor = false, AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.Badge,
				BorderSizePixel = 0, Font = FONT_BOLD, LayoutOrder = 2, Size = UDim2.fromOffset(0, 16),
				Text = "NONE", TextColor3 = T.Desc, TextSize = 10,
			}, titleRow)
			corner(record.badge, 4)
			new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, record.badge)
			record.badge.Activated:Connect(spec.onBadge)
		end

		local icon = new("TextButton", {
			Text = expanded and "-" or "+", AutoButtonColor = false, BackgroundColor3 = T.Badge, BorderSizePixel = 0,
			Font = FONT_BOLD, TextSize = 14, TextColor3 = T.Title, Position = UDim2.fromOffset(PAD_X, 29),
			Size = UDim2.fromOffset(16, 16), Visible = spec.build ~= nil,
		}, frame)
		corner(icon, 4)
		local description = text(frame, {
			Position = UDim2.fromOffset(PAD_X + 24, 29), Size = UDim2.new(1, -(PAD_X * 2 + 24), 0, 16),
			TextSize = 12, TextColor3 = T.Desc, TextTruncate = Enum.TextTruncate.AtEnd, Text = spec.desc or "",
		})
		if not spec.build then
			description.Position = UDim2.fromOffset(PAD_X, 29)
			description.Size = UDim2.new(1, -PAD_X * 2, 0, 16)
		end
		-- description brightens on hover (decay follower, not a tween)
		local hover = anim.newFollower(0, A.FollowFast, function(v)
			description.TextColor3 = T.Desc:Lerp(T.DescHover, v)
		end, 0.01)
		frame.MouseEnter:Connect(function() hover.Set(1) end)
		frame.MouseLeave:Connect(function() hover.Set(0) end)

		if spec.switch then
			record.switch = buildSwitch(frame, UDim2.new(1, -PAD_X, 0, 10), Vector2.new(1, 0), spec.switch.initial, spec.switch.onChange)
		end

		local body
		local function setupBody()
			if body then
				body:Destroy()
			end
			body = new("Frame", {
				BackgroundTransparency = 1, Position = UDim2.fromOffset(0, HEADER), Size = UDim2.new(1, 0, 0, 0),
			}, frame)
			new("Frame", {
				BackgroundColor3 = T.Outline, BackgroundTransparency = 0.4, BorderSizePixel = 0,
				Position = UDim2.fromOffset(PAD_X, 0), Size = UDim2.new(1, -PAD_X * 2, 0, 1),
			}, body)
			local inner = new("Frame", {
				BackgroundTransparency = 1, Position = UDim2.fromOffset(PAD_X, PAD_TOP), Size = UDim2.new(1, -PAD_X * 2, 0, 0),
			}, body)
			local ui = makeUi(inner, innerWidth, spec.module)
			spec.build(ui)
			bodyHeight = ui.Height()
			body.Size = UDim2.new(1, 0, 0, bodyHeight)
		end

		function record.Refresh()
			heightFollower.Set(expanded and HEADER + bodyHeight or HEADER)
		end
		function record.Rebuild()
			setupBody()
			record.Refresh()
		end

		if spec.build then
			setupBody()
			if not spec.alwaysOpen then
				local function toggleBody()
					expanded = not expanded
					icon.Text = expanded and "-" or "+"
					record.Refresh()
				end
				icon.Activated:Connect(toggleBody)
				-- Right click anywhere on the header opens / closes the settings, not just on the + icon.
				-- The overlay is not Active, so left clicks still reach the switch, the badge and the icon below it.
				local headerHit = new("Frame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = 20,
					Size = UDim2.new(1, 0, 0, HEADER),
				}, frame)
				headerHit.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton2 then
						toggleBody()
					end
				end)
			end
		end
		heightFollower.Set(expanded and HEADER + bodyHeight or HEADER, true)
		return record
	end

	-- Module cards --------------------------------------------------------------------------
	for _, m in ipairs(ModuleList) do
		local page = pages[m.tab]
		page.count += 1
		local column = page.columns[(page.count - 1) % #page.columns + 1]
		local bindable = (not m.noToggle) or m.primary ~= nil
		cards[m.id] = buildCard(page, column, {
			id = m.id, title = m.title, desc = m.desc, order = page.count, module = m,
			build = m.settings,
			switch = (not m.noToggle) and {
				initial = m.enabled,
				onChange = function(value)
					setModule(m.id, value, true)
				end,
			} or nil,
			onBadge = bindable and function()
				Bind.listening = (Bind.listening ~= m.id) and m.id or nil
				refreshBinds()
			end or nil,
		})
	end
	refreshBinds()

	-- Profile panels (FFlags / Profiles tabs) -------------------------------------------------
	local function buildPanel(pageName, opts)
		local page = pages[pageName]
		local record, nameBox, pasteBox
		local function done(message)
			if message then
				opts.status = message
			end
			record.Rebuild()
		end
		record = buildCard(page, page.columns[1], {
			id = opts.id, title = opts.title, desc = opts.desc, order = 1, alwaysOpen = true,
			build = function(ui)
				nameBox = ui.Input("Type name", function(value)
					done(opts.create(value))
				end, true)

				local store = opts.store
				for _, name in ipairs(store.order) do
					local row = ui.Row(26)
					local isActive = store.active == name
					local pick = new("TextButton", {
						Text = name, AutoButtonColor = false, BackgroundTransparency = 1, Font = FONT_BOLD, TextSize = 14,
						TextColor3 = isActive and T.Accent or T.Title, TextXAlignment = Enum.TextXAlignment.Left,
						Size = UDim2.new(0.6, 0, 1, 0),
					}, row)
					pick.Activated:Connect(function()
						done(opts.activate(name))
					end)
					if name ~= "default" then
						local function small(label, offset, callback)
							local button = new("TextButton", {
								Text = label, AutoButtonColor = false, BackgroundTransparency = 1, Font = FONT, TextSize = 12,
								TextColor3 = T.Desc, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, offset, 0, 0),
								Size = UDim2.new(0, 56, 1, 0),
							}, row)
							button.MouseEnter:Connect(function() button.TextColor3 = T.Title end)
							button.MouseLeave:Connect(function() button.TextColor3 = T.Desc end)
							button.Activated:Connect(callback)
						end
						small("Delete", 0, function()
							done(opts.delete(name))
						end)
						small("Rename", -58, function()
							done(opts.rename(name, nameBox and nameBox.Text or ""))
						end)
					end
				end

				pasteBox = ui.LabeledInput(opts.pasteLabel, opts.pastePlaceholder)
				ui.Button(opts.pasteButton, function()
					done(opts.paste(pasteBox.Text))
				end)
				ui.Button(opts.exportButton, function()
					local json = opts.export()
					local copied = copyToClipboard(json)
					pasteBox.Text = json
					opts.status = copied and "exported and copied to clipboard" or "exported into the box above (copy it from there)"
					-- keep the exported text visible: only update the status line
					record.Refresh()
				end)
				if opts.extra then
					opts.extra(ui, done)
				end
				if opts.resetButton then
					ui.Button(opts.resetButton, function()
						done(opts.reset())
					end)
				end
				if opts.status and opts.status ~= "" then
					ui.Note(opts.status)
				end
			end,
		})
		return record
	end

	buildPanel("FFlags", {
		id = "FFlags", title = "FFlags", desc = "Sets of Roblox fast flags you can switch between.",
		store = FFlags.store, status = FFlags.status,
		create = function(value)
			local name, err = FFlags.store:Create(value)
			return name and ("created " .. name .. " (click it to apply)") or err
		end,
		activate = function(name)
			return FFlags.Activate(name)
		end,
		rename = function(old, newName)
			local name, err = FFlags.store:Rename(old, newName)
			return name and ("renamed to " .. name) or err
		end,
		delete = function(name)
			local wasActive = FFlags.store.active == name
			local ok, err = FFlags.store:Delete(name)
			if not ok then
				return err
			end
			return wasActive and FFlags.Activate("default") or ("deleted " .. name)
		end,
		pasteLabel = "Add FFlags", pastePlaceholder = "Paste flags to add",
		pasteButton = "Add pasted FFlags",
		paste = function(value)
			return FFlags.AddPasted(value)
		end,
		exportButton = "Export FFlags",
		export = function()
			return FFlags.store:Export(FFlags.store.active)
		end,
		resetButton = "Reset to default profile",
		reset = function()
			return FFlags.Reset()
		end,
	})

	buildPanel("Profiles", {
		id = "Profiles", title = "Profiles", desc = "Saved script settings and keybinds.",
		store = ScriptProfiles.store, status = "",
		create = function(value)
			local name, err = ScriptProfiles.store:Create(value, ScriptProfiles.Snapshot())
			if not name then
				return err
			end
			ScriptProfiles.store:SetActive(name)
			return "created " .. name .. " from the current settings"
		end,
		activate = function(name)
			ScriptProfiles.store:SetActive(name)
			ScriptProfiles.Apply(ScriptProfiles.store:Get(name))
			return "loaded " .. name
		end,
		rename = function(old, newName)
			local name, err = ScriptProfiles.store:Rename(old, newName)
			return name and ("renamed to " .. name) or err
		end,
		delete = function(name)
			local ok, err = ScriptProfiles.store:Delete(name)
			return ok and ("deleted " .. name) or err
		end,
		pasteLabel = "Import profile", pastePlaceholder = "Paste an exported profile",
		pasteButton = "Import pasted profile",
		paste = function(value)
			local okJson, decoded = pcall(function()
				return HttpService:JSONDecode(value)
			end)
			if not okJson or type(decoded) ~= "table" then
				return "that is not valid JSON"
			end
			local base, index, name = "imported", 1, nil
			repeat
				name = index == 1 and base or (base .. " " .. index)
				index += 1
			until not ScriptProfiles.store:Get(name)
			ScriptProfiles.store:Create(name, decoded)
			return "imported as " .. name .. " (click it to load)"
		end,
		exportButton = "Export profile",
		export = function()
			return HttpService:JSONEncode(ScriptProfiles.Snapshot())
		end,
		extra = function(ui, done)
			ui.Button("Save current settings into active profile", function()
				local active = ScriptProfiles.store.active
				ScriptProfiles.store:Save(active, ScriptProfiles.Snapshot())
				done("saved settings into " .. active)
			end)
		end,
	})

	-- Header buttons ---------------------------------------------------------------------------
	local function beginWindowDrag(input)
		if not isPointer(input) then
			return
		end
		local startPosition, startOffset = input.Position, root.Position
		dragSaves = false
		activeDrag = function(position)
			local delta = position - startPosition
			root.Position = UDim2.new(startOffset.X.Scale, startOffset.X.Offset + delta.X, startOffset.Y.Scale, startOffset.Y.Offset + delta.Y)
		end
	end
	header.InputBegan:Connect(beginWindowDrag)

	local tabButtons = {}
	for index, name in ipairs(TAB_NAMES) do
		local button = new("TextButton", {
			Text = name, AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = 2, Font = FONT, TextSize = 15,
			TextColor3 = T.Title, Position = UDim2.fromOffset((index - 1) * cellW, 0), Size = UDim2.fromOffset(cellW, L.HeaderBar),
		}, header)
		button.Activated:Connect(function()
			selectTab(name)
		end)
		button.InputBegan:Connect(beginWindowDrag)
		table.insert(tabButtons, button)
		table.insert(headerTexts, button)
	end

	local unloadButton = new("TextButton", {
		Text = "Unload", AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = 2, Font = FONT, TextSize = 15,
		TextColor3 = T.Danger, Position = UDim2.fromOffset(#TAB_NAMES * cellW, 0), Size = UDim2.fromOffset(cellW, L.HeaderBar),
	}, header)
	table.insert(tabButtons, unloadButton)
	table.insert(headerTexts, unloadButton)
	local unloadArmed = false
	unloadButton.Activated:Connect(function()
		if unloadArmed then
			Toolkit.Unload()
			return
		end
		unloadArmed = true
		unloadButton.Text = "Sure?"
		task.delay(3, function()
			if unloadArmed and unloadButton.Parent then
				unloadArmed = false
				unloadButton.Text = "Unload"
			end
		end)
	end)

	-- Search: matching cards are moved into the Search page, and returned home when cleared ----
	local searchButton = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = 2,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(SEARCH_W, L.HeaderBar),
	}, header)
	local lens = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -2, 0.5, -2), Size = UDim2.fromOffset(11, 11),
		BackgroundTransparency = 1,
	}, searchButton)
	corner(lens, 6)
	local lensStroke = new("UIStroke", { Color = T.Title, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, lens)
	local handle = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 5, 0.5, 5), Size = UDim2.fromOffset(6, 1.5),
		Rotation = 45, BackgroundColor3 = T.Title, BorderSizePixel = 0,
	}, searchButton)

	local searchBox = new("TextBox", {
		Visible = false, BackgroundTransparency = 1, ClearTextOnFocus = false, Font = FONT, TextSize = 14,
		PlaceholderText = "Search modules", PlaceholderColor3 = T.Desc, TextColor3 = T.Title, Text = "",
		TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -(SEARCH_W + 24), 1, 0), ZIndex = 3,
	}, header)

	local previousTab = TAB_NAMES[1]
	local function applySearch(query)
		query = string.lower(query)
		for _, record in pairs(cards) do
			record.frame.Parent = record.home
			record.frame.LayoutOrder = record.order
		end
		if query == "" then
			selectTab(previousTab)
			return
		end
		if activeTab ~= "Search" then
			previousTab = activeTab
		end
		local page, count = pages.Search, 0
		for _, m in ipairs(ModuleList) do
			local record = cards[m.id]
			if record and (string.find(string.lower(m.title), query, 1, true) or string.find(string.lower(m.desc or ""), query, 1, true)) then
				count += 1
				record.frame.Parent = page.columns[(count - 1) % 2 + 1]
				record.frame.LayoutOrder = count
			end
		end
		selectTab("Search")
		updateContentTarget()
	end

	local searching = false
	local function setSearching(value)
		searching = value
		searchBox.Visible = value
		activePill.Visible = (not value) and tabIndex[activeTab] ~= nil
		for _, button in ipairs(tabButtons) do
			button.Visible = not value
		end
		if value then
			searchBox:CaptureFocus()
		else
			searchBox.Text = ""
			applySearch("")
		end
	end
	searchButton.Activated:Connect(function()
		setSearching(not searching)
	end)
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		if searching then
			applySearch(searchBox.Text)
		end
	end)

	-- Modal open / close: scale 0.96 -> 1, glass + blur fade, header slide, 0.30 s quint out -------
	local menuOpen = false
	local modalTimer
	local function applyModal()
		rootScale.Scale = fit * (0.96 + 0.04 * modalAlpha)
		backdrop.BackgroundTransparency = 1 - (1 - T.BackdropTransparency) * modalAlpha
		blur.Size = T.BlurSize * modalAlpha
		header.BackgroundTransparency = 1 - modalAlpha
		headerStroke.Transparency = 1 - 0.6 * modalAlpha
		root.Position = UDim2.new(root.Position.X.Scale, root.Position.X.Offset, 0, 12 - (1 - modalAlpha) * 10)
		for _, label in ipairs(headerTexts) do
			label.TextTransparency = 1 - modalAlpha
		end
		lensStroke.Transparency = 1 - modalAlpha
		handle.BackgroundTransparency = 1 - modalAlpha
		applyPageAlpha()
	end
	local function setMenu(open)
		menuOpen = open
		Toolkit.MenuOpen = open
		if not open and Toolkit.FlushSave then
			Toolkit.FlushSave() -- closing the menu is a calm moment to write the profile
		end
		if modalTimer then
			modalTimer.cancelled = true
		end
		local from, to = modalAlpha, open and 1 or 0
		if open then
			screen.Enabled = true
		end
		modalTimer = anim.run(A.ModalTime, anim.quintOut, function(e)
			modalAlpha = from + (to - from) * e
			applyModal()
		end, function()
			if not open then
				screen.Enabled = false
			end
		end)
	end

	-- Public hooks -------------------------------------------------------------------------------
	function Toolkit.ToggleMenu()
		setMenu(not menuOpen)
	end
	function Toolkit.RefreshBinds()
		refreshBinds()
	end
	function Toolkit.RefreshControls()
		for _, refresh in ipairs(refreshers) do
			pcall(refresh)
		end
	end
	rootMaid:Add(listenModules(function(m)
		local record = cards[m.id]
		if record and record.switch then
			record.switch.Set(m.enabled)
		end
	end))

	selectTab(TAB_NAMES[1], true)
	applyModal()
	setMenu(true)
end

-- shared with the chunks that load after this one
S.buildUi = buildUi

-- Toolkit/modules/visual.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local Players, UserInputService, RunService, Workspace, Lighting, Stats = S.Players, S.UserInputService, S.RunService, S.Workspace, S.Lighting, S.Stats
local LocalPlayer, Config, FONT, FONT_BOLD, logError, Toolkit = S.LocalPlayer, S.Config, S.FONT, S.FONT_BOLD, S.logError, S.Toolkit
local anim, new, GuiRoot, notify, getHumanoid, getRoot = S.anim, S.new, S.GuiRoot, S.notify, S.getHumanoid, S.getRoot
local finite, Modules, ModuleList, DEEP_RED, TargetGuiState, listenModules = S.finite, S.Modules, S.ModuleList, S.DEEP_RED, S.TargetGuiState, S.listenModules
local AimState, listenAim, defineModule, setModule, trackPlayers = S.AimState, S.listenAim, S.defineModule, S.setModule, S.trackPlayers

-- ---------------------------------------------------------------------------------------
-- C3. Visual
-- ---------------------------------------------------------------------------------------

-- Widget helpers (Target Info, Keystrokes, Clock) -------------------------------------------
local function widgetGui(maid, name, order)
	return maid:Add(new("ScreenGui", {
		Name = name, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = order or 1100,
	}, GuiRoot))
end

local function makeGlass(parent, size, transparency, grouped)
	local class = (grouped and Config.UseCanvasGroup) and "CanvasGroup" or "Frame"
	local frame = new(class, {
		Size = size, BackgroundColor3 = Config.Theme.Header, BackgroundTransparency = transparency or 0.25, BorderSizePixel = 0,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
	new("UIStroke", {
		Color = Color3.fromRGB(255, 255, 255), Transparency = 0.85, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, frame)
	return frame
end

-- Drag a widget with the mouse. Its position lives in m.cfg.PosX / PosY as screen fractions, and the profile is
-- saved once when the drag ends (never while the mouse is moving).
local function makeDraggable(maid, frame, m)
	local function viewportSize()
		local camera = Workspace.CurrentCamera
		return camera and camera.ViewportSize or Vector2.new(1280, 720)
	end
	local function isPointer(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	local viewport = viewportSize()
	frame.Position = UDim2.fromOffset(math.floor(m.cfg.PosX * viewport.X), math.floor(m.cfg.PosY * viewport.Y))
	frame.Active = true

	local dragging, startMouse, startPosition = false, nil, nil
	maid:Add(frame.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging, startMouse, startPosition = true, input.Position, frame.AbsolutePosition
		end
	end))
	maid:Add(UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local size = viewportSize()
			local x = math.clamp(startPosition.X + input.Position.X - startMouse.X, 0, math.max(size.X - frame.AbsoluteSize.X, 0))
			local y = math.clamp(startPosition.Y + input.Position.Y - startMouse.Y, 0, math.max(size.Y - frame.AbsoluteSize.Y, 0))
			frame.Position = UDim2.fromOffset(x, y)
			m.cfg.PosX, m.cfg.PosY = x / size.X, y / size.Y
		end
	end))
	maid:Add(UserInputService.InputEnded:Connect(function(input)
		if dragging and isPointer(input) then
			dragging = false
			if Toolkit.RequestSave then
				Toolkit.RequestSave()
			end
		end
	end))
end

-- Player ESP helpers -------------------------------------------------------------------------
local function teamColorOf(player, hue)
	if player.Team ~= nil then
		return player.TeamColor.Color
	end
	return Color3.fromHSV(math.clamp(hue, 0, 1), 0.85, 1)
end

-- the nearest `limit` other players (distance to your character), so Highlights stay under Roblox's cap
local function nearestPlayers(limit)
	local root, camera = getRoot(), Workspace.CurrentCamera
	local origin = root and root.Position or (camera and camera.CFrame.Position)
	local list = {}
	if not origin then
		return list
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local part = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if part then
				table.insert(list, { player = player, distance = (part.Position - origin).Magnitude })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.distance < b.distance
	end)
	for index = #list, limit + 1, -1 do
		list[index] = nil
	end
	return list
end

defineModule({
	id = "PlayerEsp", tab = "Visual", title = "Player ESP",
	desc = "Outlines other players through walls, in team colors.",
	defaults = { UseTeamColor = true, Hue = 0.07, FillTransparency = 0.6, TeamCheck = false },
	settings = function(ui)
		ui.Toggle("Team colors", "UseTeamColor")
		ui.Color("Fallback color", "Hue")
		ui.Slider("Fill transparency", "FillTransparency", 0, 1, 0.05)
		ui.Toggle("Hide teammates", "TeamCheck")
		ui.Note("Only the " .. Config.EspMaxPlayers .. " nearest players get an outline (Roblox draws about 31 at once). The player POV Aim has locked turns deep red.")
	end,
	onEnable = function(m, maid)
		local folder = maid:Add(new("Folder", { Name = "TkEsp" }, GuiRoot))
		local highlights = {} -- player -> Highlight

		local function drop(player)
			local highlight = highlights[player]
			if highlight then
				highlight:Destroy()
				highlights[player] = nil
			end
		end
		local function paint()
			for player, highlight in pairs(highlights) do
				local locked = AimState.player == player
				local color = DEEP_RED
				if not locked then
					color = m.cfg.UseTeamColor and teamColorOf(player, m.cfg.Hue) or Color3.fromHSV(math.clamp(m.cfg.Hue, 0, 1), 0.85, 1)
				end
				highlight.FillColor = color
				highlight.OutlineColor = color
				highlight.FillTransparency = locked and 0.35 or m.cfg.FillTransparency
				highlight.OutlineTransparency = 0
			end
		end
		local function refresh()
			local keep = {}
			for _, entry in ipairs(nearestPlayers(Config.EspMaxPlayers)) do
				local player = entry.player
				local hidden = m.cfg.TeamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team
				if not hidden then
					keep[player] = true
					local highlight = highlights[player]
					if not highlight then
						highlight = new("Highlight", { DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, folder)
						highlights[player] = highlight
					end
					highlight.Adornee = player.Character
				end
			end
			for player in pairs(highlights) do
				if not keep[player] then
					drop(player)
				end
			end
			paint()
		end

		maid:Add(listenAim(paint)) -- lock colour appears / disappears in the same frame the lock changes
		maid:Add(Players.PlayerRemoving:Connect(drop))
		local clock = 0
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			clock += dt
			if clock >= 0.2 then
				clock = 0
				refresh()
			end
		end))
		refresh()
	end,
})

defineModule({
	id = "NameTags", tab = "Visual", title = "Name Tags",
	desc = "Shows clear name tags above other players.",
	defaults = {
		Scale = 1, DistanceCheck = false, MaxDistance = 1000, Health = true, Distance = true,
		DisplayName = true, TeamCheck = false, UseTeamColor = true, Hue = 0.07,
	},
	settings = function(ui)
		ui.Slider("Scale", "Scale", 0.5, 2, 0.1)
		ui.Toggle("Distance check", "DistanceCheck")
		ui.Slider("Max distance", "MaxDistance", 50, 2000, 50)
		ui.Toggle("Health bar", "Health")
		ui.Toggle("Show distance", "Distance")
		ui.Toggle("Use display name", "DisplayName")
		ui.Toggle("Hide teammates", "TeamCheck")
		ui.Toggle("Team colors", "UseTeamColor")
		ui.Color("Fallback color", "Hue")
	end,
	onEnable = function(m, maid)
		local folder = maid:Add(new("Folder", { Name = "TkTags" }, GuiRoot))
		local entries = {}
		trackPlayers(maid, function(player)
			local billboard = new("BillboardGui", {
				AlwaysOnTop = true, Size = UDim2.fromOffset(180, 44), StudsOffset = Vector3.new(0, 2.8, 0), Enabled = false,
			})
			local scale = new("UIScale", { Scale = 1 }, billboard)
			local label = new("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), Font = FONT, TextSize = 13,
				TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, Text = "",
			}, billboard)
			local track = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(84, 5),
				BackgroundColor3 = Color3.fromRGB(22, 22, 22), BackgroundTransparency = 0.2, BorderSizePixel = 0,
			}, billboard)
			new("UICorner", { CornerRadius = UDim.new(0, 3) }, track)
			local bar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 200, 100), BorderSizePixel = 0 }, track)
			new("UICorner", { CornerRadius = UDim.new(0, 3) }, bar)
			billboard.Parent = folder
			entries[player] = { billboard = billboard, scale = scale, label = label, track = track, bar = bar }
		end, function(player)
			if entries[player] then
				entries[player].billboard:Destroy()
				entries[player] = nil
			end
		end)

		local function update()
			local camera, root = Workspace.CurrentCamera, getRoot()
			local origin = root and root.Position or (camera and camera.CFrame.Position)
			if not origin then
				return
			end
			local cfg = m.cfg
			for player, entry in pairs(entries) do
				local character = player.Character
				local head = character and character:FindFirstChild("Head")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local visible = head ~= nil and humanoid ~= nil and humanoid.Health > 0
				local distance = 0
				if visible then
					distance = (head.Position - origin).Magnitude
					if cfg.DistanceCheck and distance > cfg.MaxDistance then
						visible = false
					end
					if cfg.TeamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team then
						visible = false
					end
					-- the Target Info card already shows the locked player: no duplicate tag
					if TargetGuiState.visible and AimState.player == player then
						visible = false
					end
				end
				entry.billboard.Enabled = visible
				if visible then
					local color = DEEP_RED
					if AimState.player ~= player then
						color = cfg.UseTeamColor and teamColorOf(player, cfg.Hue) or Color3.fromHSV(math.clamp(cfg.Hue, 0, 1), 0.85, 1)
					end
					entry.billboard.Adornee = head
					entry.scale.Scale = cfg.Scale
					entry.label.TextColor3 = color
					local lines = { cfg.DisplayName and player.DisplayName or player.Name }
					if cfg.Distance then
						table.insert(lines, string.format("%.0fm", finite(distance, 0)))
					end
					entry.label.Text = table.concat(lines, "\n")
					entry.track.Visible = cfg.Health
					local fraction = math.clamp(finite(humanoid.Health, 0) / math.max(finite(humanoid.MaxHealth, 100), 1), 0, 1)
					entry.bar.Size = UDim2.fromScale(fraction, 1)
					entry.bar.BackgroundColor3 = Color3.fromRGB(220, 70, 70):Lerp(Color3.fromRGB(90, 200, 100), fraction)
				end
			end
		end
		maid:Add(listenAim(update))
		local clock = 0
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			clock += dt
			if clock >= 0.1 then
				clock = 0
				update()
			end
		end))
	end,
})

defineModule({
	id = "TargetInfo", tab = "Visual", title = "Target Info",
	desc = "Shows who you are fighting and their health.",
	defaults = { Show = 35, PosX = 0.56, PosY = 0.56 },
	persist = { "PosX", "PosY" },
	settings = function(ui)
		ui.Slider("Show within (studs)", "Show", 10, 120, 1)
		ui.Button("Preview for 5 seconds", function()
			Modules.TargetInfo.previewUntil = os.clock() + 5
		end)
		ui.Note("The card shows for the player POV Aim has locked. It hides again only when that player is more than 3 studs beyond the distance above, so it never flickers at the border. Drag it to move it.")
	end,
	onEnable = function(m, maid)
		local T = Config.Theme
		local gui = widgetGui(maid, "TkTargetInfo", 1100)
		local card = makeGlass(gui, UDim2.fromOffset(230, 58), 0.2, true)
		card.Visible = false
		local nameLabel = new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -100, 0, 18),
			Font = FONT_BOLD, TextSize = 14, TextColor3 = T.Title, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
		}, card)
		local distanceLabel = new("TextLabel", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7),
			Size = UDim2.fromOffset(84, 18), Font = FONT, TextSize = 12, TextColor3 = T.Desc,
			TextXAlignment = Enum.TextXAlignment.Right, Text = "",
		}, card)
		local track = new("Frame", {
			Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 10),
			BackgroundColor3 = Color3.fromRGB(38, 38, 38), BorderSizePixel = 0,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 5) }, track)
		-- ghost bar sits behind the main bar: the main bar drops at once, the pale red trail follows slowly
		local ghostBar = new("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 140, 140),
			BackgroundTransparency = 0.35, BorderSizePixel = 0,
		}, track)
		new("UICorner", { CornerRadius = UDim.new(0, 5) }, ghostBar)
		local mainBar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 200, 100), BorderSizePixel = 0, ZIndex = 2 }, track)
		new("UICorner", { CornerRadius = UDim.new(0, 5) }, mainBar)

		local ghost = anim.newFollower(1, 2.5, function(value)
			ghostBar.Size = UDim2.fromScale(value, 1)
		end, 0.002)
		local alpha = anim.newFollower(0, Config.Anim.FollowFast, function(a)
			card.Visible = a > 0.01
			if card:IsA("CanvasGroup") then
				card.GroupTransparency = 1 - a
			else
				card.BackgroundTransparency = 1 - 0.8 * a
			end
		end, 0.01)
		makeDraggable(maid, card, m)

		local shown, lastKey = false, nil
		maid:Add(function()
			TargetGuiState.visible = false
		end)
		maid:Add(RunService.Heartbeat:Connect(function()
			local preview = os.clock() < (m.previewUntil or 0)
			local player, part = AimState.player, AimState.part
			local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local root = getRoot()
			local show, fraction, name, distance = false, 1, "", 0
			if preview then
				show, fraction, name, distance = true, 0.62, "Preview", 12.5
			elseif player and humanoid and part and root and humanoid.Health > 0 then
				distance = (part.Position - root.Position).Magnitude
				-- hysteresis: appears at <= Show, disappears only beyond Show + 3
				show = distance <= m.cfg.Show + (shown and 3 or 0)
				fraction = math.clamp(finite(humanoid.Health, 0) / math.max(finite(humanoid.MaxHealth, 100), 1), 0, 1)
				name = player.DisplayName
			end
			if show ~= shown then
				shown = show
				alpha.Set(show and 1 or 0)
			end
			TargetGuiState.visible = shown and not preview
			if not show then
				return
			end
			local key = preview and "preview" or player
			if key ~= lastKey then
				lastKey = key
				ghost.Set(fraction, true)
			end
			nameLabel.Text = name
			distanceLabel.Text = string.format("%.1f studs", finite(distance, 0))
			mainBar.Size = UDim2.fromScale(fraction, 1)
			mainBar.BackgroundColor3 = Color3.fromRGB(220, 70, 70):Lerp(Color3.fromRGB(90, 200, 100), fraction)
			if fraction >= ghost.target then
				ghost.Set(fraction, true) -- healing: the trail never lags behind
			else
				ghost.Set(fraction)
			end
		end))
	end,
})

defineModule({
	id = "Crosshair", tab = "Visual", title = "Crosshair",
	desc = "Custom crosshair, turns deep red when POV Aim locks on.",
	defaults = { Style = "Plus", Size = 10, Thickness = 2, Gap = 3, UseAccent = false, HideCursor = true },
	settings = function(ui)
		ui.Choice("Style", "Style", { "Plus", "Dot" })
		ui.Slider("Size", "Size", 3, 30, 1)
		ui.Slider("Thickness", "Thickness", 1, 5, 1)
		ui.Slider("Gap", "Gap", 0, 12, 1)
		ui.Toggle("Accent color", "UseAccent")
		ui.Toggle("Hide mouse cursor", "HideCursor")
		ui.Note("The cursor is hidden in first person and while the mouse is locked, never while this menu is open. Crosshairs drawn by the game itself cannot be hidden from here.")
	end,
	onEnable = function(m, maid)
		local gui = widgetGui(maid, "TkCrosshair", 950)
		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1,
		}, gui)
		local parts, signature = {}, nil

		local function paint()
			local color = Config.Theme.Title
			if m.cfg.UseAccent then
				color = Config.Theme.Accent
			end
			if AimState.player then
				color = DEEP_RED -- POV Aim has a target
			end
			for _, part in ipairs(parts) do
				part.BackgroundColor3 = color
			end
		end
		local function build()
			for _, part in ipairs(parts) do
				part:Destroy()
			end
			table.clear(parts)
			local cfg = m.cfg
			local function piece(x, y, width, height)
				local frame = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(width, height), BorderSizePixel = 0,
				}, holder)
				table.insert(parts, frame)
				return frame
			end
			if cfg.Style == "Dot" then
				local dot = piece(0, 0, cfg.Size * 0.5, cfg.Size * 0.5)
				new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			else
				local offset = cfg.Gap + cfg.Size / 2
				piece(0, -offset, cfg.Thickness, cfg.Size)
				piece(0, offset, cfg.Thickness, cfg.Size)
				piece(-offset, 0, cfg.Size, cfg.Thickness)
				piece(offset, 0, cfg.Size, cfg.Thickness)
			end
			paint()
		end

		maid:Add(listenAim(paint))
		local savedIcon = UserInputService.MouseIconEnabled
		maid:Add(function()
			UserInputService.MouseIconEnabled = savedIcon
		end)
		maid:Add(RunService.RenderStepped:Connect(function()
			local cfg = m.cfg
			local current = table.concat({ cfg.Style, cfg.Size, cfg.Thickness, cfg.Gap, tostring(cfg.UseAccent) }, "|")
			if current ~= signature then
				signature = current
				build() -- rebuilt only when a setting changed
			end
			if cfg.HideCursor and not Toolkit.MenuOpen then
				local camera = Workspace.CurrentCamera
				local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
				local firstPerson = camera and head and (camera.CFrame.Position - head.Position).Magnitude < 1.5
				UserInputService.MouseIconEnabled = not (firstPerson or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter)
			else
				UserInputService.MouseIconEnabled = savedIcon
			end
		end))
	end,
})

defineModule({
	id = "Keystrokes", tab = "Visual", title = "Keystrokes",
	desc = "Shows your movement keys on screen as you press them.",
	defaults = { PosX = 0.04, PosY = 0.55 },
	persist = { "PosX", "PosY" },
	settings = function(ui)
		ui.Note("Drag the card to move it. The position is saved with your profile.")
	end,
	onEnable = function(m, maid)
		local T = Config.Theme
		local gui = widgetGui(maid, "TkKeys", 1100)
		local card = makeGlass(gui, UDim2.fromOffset(150, 166), 0.3, false)
		local keys = {}
		local function key(label, x, y, width, height, matches)
			local frame = new("Frame", {
				Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
				BackgroundColor3 = T.Badge, BorderSizePixel = 0,
			}, card)
			new("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
			new("TextLabel", {
				BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FONT_BOLD, TextSize = 13,
				TextColor3 = T.Title, Text = label,
			}, frame)
			local follower = anim.newFollower(0, Config.Anim.FollowFast, function(v)
				frame.BackgroundColor3 = T.Badge:Lerp(T.Accent, v)
			end, 0.01)
			table.insert(keys, { follower = follower, matches = matches })
		end
		local function keyboard(code)
			return function(input)
				return input.KeyCode == code
			end
		end
		local function mouse(button)
			return function(input)
				return input.UserInputType == button
			end
		end
		key("W", 55, 10, 40, 40, keyboard(Enum.KeyCode.W))
		key("A", 10, 55, 40, 40, keyboard(Enum.KeyCode.A))
		key("S", 55, 55, 40, 40, keyboard(Enum.KeyCode.S))
		key("D", 100, 55, 40, 40, keyboard(Enum.KeyCode.D))
		key("LMB", 10, 100, 62, 26, mouse(Enum.UserInputType.MouseButton1))
		key("RMB", 78, 100, 62, 26, mouse(Enum.UserInputType.MouseButton2))
		key("SPACE", 10, 132, 130, 24, keyboard(Enum.KeyCode.Space))

		maid:Add(UserInputService.InputBegan:Connect(function(input)
			for _, entry in ipairs(keys) do
				if entry.matches(input) then
					entry.follower.Set(1)
				end
			end
		end))
		maid:Add(UserInputService.InputEnded:Connect(function(input)
			for _, entry in ipairs(keys) do
				if entry.matches(input) then
					entry.follower.Set(0)
				end
			end
		end))
		makeDraggable(maid, card, m)
	end,
})

defineModule({
	id = "ModList", tab = "Visual", title = "Mod Overlay",
	desc = "Displays a list of all active mods.",
	defaults = { Hue = 0.07 },
	settings = function(ui)
		ui.Color("Gradient color", "Hue")
	end,
	onEnable = function(m, maid)
		local gui = widgetGui(maid, "TkModList", 900)
		local list = new("Frame", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14),
			AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1,
		}, gui)
		new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}, list)
		local function rebuild()
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("TextLabel") then
					child:Destroy()
				end
			end
			local names = {}
			for _, other in ipairs(ModuleList) do
				if other.enabled and other.id ~= "ModList" then
					table.insert(names, other.title)
				end
			end
			-- longest first, like the usual array list
			table.sort(names, function(a, b)
				if #a ~= #b then
					return #a > #b
				end
				return a < b
			end)
			local hue = math.clamp(m.cfg.Hue, 0, 1)
			for index, name in ipairs(names) do
				local label = new("TextLabel", {
					BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = index,
					Font = FONT_BOLD, TextSize = 15, Text = name, TextColor3 = Color3.new(1, 1, 1),
					TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.6,
				}, list)
				new("UIGradient", {
					Color = ColorSequence.new(Color3.fromHSV(hue, 0.85, 1), Color3.fromHSV((hue + 0.08) % 1, 0.75, 1)),
				}, label)
			end
		end
		maid:Add(listenModules(rebuild))
		rebuild()
	end,
})

defineModule({
	id = "MotionBlur", tab = "Visual", title = "Motion Blur",
	desc = "Blurs the screen on fast turns and at high speed.",
	defaults = { Strength = 14, TurnSensitivity = 1, SpeedThreshold = 45 },
	settings = function(ui)
		ui.Slider("Max strength", "Strength", 2, 30, 1)
		ui.Slider("Turn sensitivity", "TurnSensitivity", 0.2, 3, 0.1)
		ui.Slider("Speed threshold", "SpeedThreshold", 20, 200, 5)
	end,
	onEnable = function(m, maid)
		local blur = maid:Add(new("BlurEffect", { Name = "TkMotionBlur", Size = 0 }, Lighting))
		local previousLook, current = nil, 0
		maid:Add(RunService.RenderStepped:Connect(function(dt)
			local camera = Workspace.CurrentCamera
			if not camera or dt <= 0 then
				return
			end
			local cfg = m.cfg
			local look = camera.CFrame.LookVector
			local turn = 0 -- degrees per second the camera is turning
			if previousLook then
				turn = math.deg(math.acos(math.clamp(previousLook:Dot(look), -1, 1))) / dt
			end
			previousLook = look
			local root = getRoot()
			local speed = root and finite(root.AssemblyLinearVelocity.Magnitude, 0) or 0
			local goal = math.clamp(turn / 360 * cfg.TurnSensitivity, 0, 1) * cfg.Strength
				+ math.clamp((speed - cfg.SpeedThreshold) / 60, 0, 1) * cfg.Strength * 0.6
			current = anim.follow(current, math.min(goal, cfg.Strength), 12, dt)
			blur.Size = current
		end))
	end,
})

defineModule({
	id = "Cape", tab = "Visual", title = "Cape",
	desc = "Gives your character a cape that sways as you move.",
	defaults = { Hue = 0, Length = 3 },
	settings = function(ui)
		ui.Slider("Length", "Length", 2, 5, 0.5)
		ui.Color("Color", "Hue")
	end,
	onEnable = function(m, maid)
		local character = LocalPlayer.Character
		local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
		if not torso then
			return false
		end
		-- the cape is a chain of hinged segments, so a phase-shifted sine can ripple down it
		local count = 5
		local segment = m.cfg.Length / count
		local parts, welds, hinges = {}, {}, {}
		local previous = torso
		for index = 1, count do
			local part = maid:Add(new("Part", {
				Name = "TkCape", Size = Vector3.new(torso.Size.X * 0.9, segment, 0.1), Massless = true,
				CanCollide = false, CanTouch = false, CanQuery = false, Material = Enum.Material.Fabric,
			}, character))
			local hinge = index == 1 and CFrame.new(0, torso.Size.Y / 2 - 0.15, torso.Size.Z / 2 + 0.06)
				or CFrame.new(0, -segment / 2, 0)
			welds[index] = new("Weld", { Part0 = previous, Part1 = part, C0 = hinge, C1 = CFrame.new(0, segment / 2, 0) }, part)
			hinges[index], parts[index] = hinge, part
			previous = part
		end
		local lastHue
		maid:Add(RunService.RenderStepped:Connect(function()
			local root = getRoot()
			local speed = root and finite(root.AssemblyLinearVelocity.Magnitude, 0) or 0
			local factor = math.clamp(speed / 50, 0, 1) -- faster = the cape flares out further
			local now = os.clock()
			for index, weld in ipairs(welds) do
				local flare = (math.rad(6) + factor * math.rad(55)) / count
				local wave = math.sin(now * 7 - index * 0.9) * factor * math.rad(7) + math.sin(now * 1.5 - index * 0.5) * math.rad(1.5)
				weld.C0 = hinges[index] * CFrame.Angles(-(flare + wave), 0, 0)
			end
			if m.cfg.Hue ~= lastHue then
				lastHue = m.cfg.Hue
				local color = Color3.fromHSV(math.clamp(lastHue, 0, 1), 0.8, 0.6)
				for _, part in ipairs(parts) do
					part.Color = color
				end
			end
		end))
	end,
})

defineModule({
	id = "ChinaHat", tab = "Visual", title = "China Hat",
	desc = "Puts a china hat on your head.",
	defaults = { Hue = 0.1, Radius = 1.4, Flip = false },
	settings = function(ui)
		ui.Slider("Radius", "Radius", 0.8, 3, 0.1)
		ui.Color("Color", "Hue")
		ui.Toggle("Flip cone", "Flip")
	end,
	onEnable = function(m, maid)
		local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
		if not head then
			return false
		end
		local cone = maid:Add(new("ConeHandleAdornment", {
			Adornee = head, Height = 0.7, ZIndex = 1, AlwaysOnTop = false, Transparency = 0.1,
		}, head))
		maid:Add(RunService.RenderStepped:Connect(function()
			cone.Radius = m.cfg.Radius
			cone.Color3 = Color3.fromHSV(math.clamp(m.cfg.Hue, 0, 1), 0.7, 1)
			-- if the point faces down on your setup, use "Flip cone"
			cone.CFrame = CFrame.new(0, head.Size.Y / 2 + 0.35, 0) * CFrame.Angles(m.cfg.Flip and math.pi / 2 or -math.pi / 2, 0, 0)
		end))
	end,
})

defineModule({
	id = "Clock", tab = "Visual", title = "Clock",
	desc = "Shows your local time on screen.",
	defaults = { PosX = 0.46, PosY = 0.02 },
	persist = { "PosX", "PosY" },
	settings = function(ui)
		ui.Note("Drag the clock to move it. The position is saved with your profile.")
	end,
	onEnable = function(m, maid)
		local gui = widgetGui(maid, "TkClock", 1100)
		local card = makeGlass(gui, UDim2.fromOffset(110, 32), 0.25, false)
		local label = new("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FONT_BOLD, TextSize = 15,
			TextColor3 = Config.Theme.Title, Text = os.date("%H:%M:%S"),
		}, card)
		makeDraggable(maid, card, m)
		local clock = 0
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			clock += dt
			if clock >= 0.25 then
				clock = 0
				label.Text = os.date("%H:%M:%S")
			end
		end))
	end,
})

-- Disguise. Humanoid:ApplyDescription is refused on the client for a replicated character ("can only be called by
-- the backend server"), so the look is rebuilt piece by piece on your own character, locally: clothing, accessories,
-- face and skin colors. R15 body part meshes are not copied. Everything is put back when the module is disabled.
defineModule({
	id = "Disguise", tab = "Visual", title = "Disguise",
	desc = "Wears another avatar on your screen.",
	defaults = { Username = "" },
	settings = function(ui)
		ui.Text("Username", "Username", "Roblox username or user id")
		ui.Note("Client-side only. Copies clothing, accessories, face and skin colors; body part meshes are not copied. Needs game:GetObjects from your executor.")
	end,
	onEnable = function(m, maid)
		local query = tostring(m.cfg.Username or "")
		local character, humanoid = LocalPlayer.Character, getHumanoid()
		if query == "" or not character or not humanoid then
			notify("Disguise: type a username first")
			return false
		end
		local alive = true
		local undo = {}
		local function runUndo()
			for index = #undo, 1, -1 do
				pcall(undo[index])
			end
			table.clear(undo)
		end
		m.runUndo = runUndo
		maid:Add(function()
			alive = false
		end)

		task.spawn(function()
			local ok, err = pcall(function()
				local userId = tonumber(query) or Players:GetUserIdFromNameAsync(query)
				local info = Players:GetCharacterAppearanceInfoAsync(userId)
				if not alive then
					return
				end

				-- take the current clothing and accessories off; the undo list puts them back
				for _, child in ipairs(character:GetChildren()) do
					if child:IsA("Accoutrement") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
						local parent = child.Parent
						child.Parent = nil
						table.insert(undo, function()
							child.Parent = parent
						end)
					end
				end

				-- skin colors
				local colors = character:FindFirstChildOfClass("BodyColors")
				if colors and type(info.bodyColors) == "table" then
					local source = info.bodyColors
					local slots = {
						{ "HeadColor", source.headColorId }, { "TorsoColor", source.torsoColorId },
						{ "LeftArmColor", source.leftArmColorId }, { "RightArmColor", source.rightArmColorId },
						{ "LeftLegColor", source.leftLegColorId }, { "RightLegColor", source.rightLegColorId },
					}
					for _, slot in ipairs(slots) do
						local property, id = slot[1], slot[2]
						if type(id) == "number" then
							local old = colors[property]
							colors[property] = BrickColor.new(id)
							table.insert(undo, function()
								colors[property] = old
							end)
						end
					end
				end

				-- clothing, face, accessories: asset type ids 2 T-Shirt, 8 Hat, 11 Shirt, 12 Pants, 18 Face (+ any "...Accessory")
				for _, asset in ipairs(info.assets or {}) do
					if not alive then
						break
					end
					local kind = type(asset.assetType) == "table" and asset.assetType or {}
					local wanted = kind.id == 2 or kind.id == 8 or kind.id == 11 or kind.id == 12 or kind.id == 18
						or string.find(tostring(kind.name), "Accessory") ~= nil
					if wanted then
						local loaded, objects = pcall(function()
							return game:GetObjects("rbxassetid://" .. asset.id)
						end)
						local object = loaded and type(objects) == "table" and objects[1] or nil
						if object then
							if object:IsA("Accoutrement") then
								if not pcall(function()
									humanoid:AddAccessory(object)
								end) then
									object.Parent = character
								end
								table.insert(undo, function()
									object:Destroy()
								end)
							elseif object:IsA("Shirt") or object:IsA("Pants") or object:IsA("ShirtGraphic") then
								object.Parent = character
								table.insert(undo, function()
									object:Destroy()
								end)
							elseif object:IsA("Decal") then
								local head = character:FindFirstChild("Head")
								local face = head and head:FindFirstChild("face")
								if face and face:IsA("Decal") then
									local old = face.Texture
									face.Texture = object.Texture
									table.insert(undo, function()
										face.Texture = old
									end)
								end
								object:Destroy()
							else
								object:Destroy()
							end
						end
					end
				end
				if not alive then
					runUndo() -- disabled while it was still loading
				end
			end)
			if not ok and alive then
				logError("Disguise", err)
				-- the engine prefixes errors with a script path; show only the readable tail
				local message = string.match(tostring(err), ":%d+: (.+)$") or tostring(err)
				notify("Disguise failed: " .. message)
				setModule("Disguise", false, true)
			end
		end)
	end,
	onDisable = function(m)
		if m.runUndo then
			m.runUndo()
		end
		m.runUndo = nil
	end,
})

defineModule({
	id = "GamingChair", tab = "Visual", title = "Gaming Chair",
	desc = "Sit in the best gaming chair known to mankind.",
	onEnable = function(_, maid)
		local humanoid, root = getHumanoid(), getRoot()
		if not humanoid or not root then
			return false
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { LocalPlayer.Character }
		local ground = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
		local floorPoint = Vector3.new(root.Position.X, ground and ground.Position.Y or (root.Position.Y - 3), root.Position.Z)
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local base = flat.Magnitude > 0.01 and CFrame.lookAt(floorPoint, floorPoint + flat) or CFrame.new(floorPoint)

		local dark, accent = Color3.fromRGB(28, 28, 32), Config.Theme.Accent
		local model = maid:Add(new("Model", { Name = "TkChair" }, Workspace))
		local function piece(size, offset, color, solid)
			return new("Part", {
				Size = size, CFrame = base * offset, Color = color, Anchored = true, CanCollide = solid or false,
				Material = Enum.Material.SmoothPlastic, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
			}, model)
		end
		piece(Vector3.new(2.4, 0.2, 0.3), CFrame.new(0, 0.1, 0), dark)
		piece(Vector3.new(0.3, 0.2, 2.4), CFrame.new(0, 0.1, 0), dark)
		piece(Vector3.new(0.4, 1.2, 0.4), CFrame.new(0, 0.8, 0), dark)
		local seat = new("Seat", {
			Size = Vector3.new(2.2, 0.5, 2.2), CFrame = base * CFrame.new(0, 1.65, 0), Color = dark, Anchored = true,
			Material = Enum.Material.SmoothPlastic,
		}, model)
		piece(Vector3.new(2.2, 3, 0.4), CFrame.new(0, 3.4, 1.0), dark, true)
		piece(Vector3.new(0.3, 2.6, 0.05), CFrame.new(-0.6, 3.4, 0.78), accent)
		piece(Vector3.new(0.3, 2.6, 0.05), CFrame.new(0.6, 3.4, 0.78), accent)
		piece(Vector3.new(1.2, 0.7, 0.35), CFrame.new(0, 5.25, 1.1), dark)
		piece(Vector3.new(0.3, 0.2, 1.6), CFrame.new(-1.25, 2.5, 0.1), dark)
		piece(Vector3.new(0.3, 0.2, 1.6), CFrame.new(1.25, 2.5, 0.1), dark)

		root.CFrame = seat.CFrame * CFrame.new(0, 2.4, 0)
		task.defer(function()
			if not pcall(function()
				seat:Sit(humanoid)
			end) then
				humanoid.Sit = true
			end
		end)
	end,
})

defineModule({
	id = "FOV", tab = "Visual", title = "FOV",
	desc = "Changes how wide your camera can see.",
	defaults = { Value = 90 },
	settings = function(ui)
		ui.Slider("Field of view", "Value", 30, 120, 1)
	end,
	onEnable = function(m, maid)
		local camera = Workspace.CurrentCamera
		m.saved = camera and camera.FieldOfView
		maid:Add(RunService.RenderStepped:Connect(function()
			local current = Workspace.CurrentCamera
			if current then
				current.FieldOfView = m.cfg.Value
			end
		end))
	end,
	onDisable = function(m)
		local camera = Workspace.CurrentCamera
		if camera and m.saved then
			camera.FieldOfView = m.saved
		end
		m.saved = nil
	end,
})

defineModule({
	id = "Fullbright", tab = "Visual", title = "Fullbright",
	desc = "Lights up the world so dark areas are easy to see.",
	onEnable = function(m, maid)
		m.saved = {
			Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
			GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		}
		maid:Add(RunService.Heartbeat:Connect(function()
			Lighting.Brightness = 2
			Lighting.ClockTime = 14
			Lighting.FogEnd = 1e5
			Lighting.GlobalShadows = false
			Lighting.Ambient = Color3.fromRGB(178, 178, 178)
			Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
		end))
	end,
	onDisable = function(m)
		for property, value in pairs(m.saved or {}) do
			Lighting[property] = value
		end
		m.saved = nil
	end,
})

defineModule({
	id = "ZoomUnlocker", tab = "Visual", title = "Zoom Unlocker",
	desc = "Lets you zoom your camera further out.",
	defaults = { MaxZoom = 1000 },
	settings = function(ui)
		ui.Slider("Max zoom", "MaxZoom", 128, 5000, 64)
	end,
	onEnable = function(m, maid)
		m.saved = LocalPlayer.CameraMaxZoomDistance
		maid:Add(RunService.Heartbeat:Connect(function()
			LocalPlayer.CameraMaxZoomDistance = m.cfg.MaxZoom
		end))
	end,
	onDisable = function(m)
		if m.saved then
			LocalPlayer.CameraMaxZoomDistance = m.saved
		end
		m.saved = nil
	end,
})

defineModule({
	id = "TimeChanger", tab = "Visual", title = "Time Changer",
	desc = "Sets the time of day to the hour you choose.",
	defaults = { Hour = 14 },
	settings = function(ui)
		ui.Slider("Hour", "Hour", 0, 24, 0.5)
	end,
	onEnable = function(m, maid)
		m.saved = Lighting.ClockTime
		maid:Add(RunService.Heartbeat:Connect(function()
			Lighting.ClockTime = m.cfg.Hour
		end))
	end,
	onDisable = function(m)
		if m.saved then
			Lighting.ClockTime = m.saved
		end
		m.saved = nil
	end,
})

defineModule({
	id = "StatsHud", tab = "Visual", title = "Stats HUD",
	desc = "Shows FPS, ping, speed and memory on screen.",
	defaults = { ShowFps = true, ShowPing = true, ShowSpeed = true, ShowMemory = false },
	settings = function(ui)
		ui.Toggle("FPS", "ShowFps")
		ui.Toggle("Ping", "ShowPing")
		ui.Toggle("Speed (studs/s)", "ShowSpeed")
		ui.Toggle("Memory", "ShowMemory")
	end,
	onEnable = function(m, maid)
		local gui = maid:Add(new("ScreenGui", {
			Name = "TkHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 900,
		}, GuiRoot))
		local frame = new("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Config.Theme.Card, BackgroundTransparency = 0.3, BorderSizePixel = 0,
		}, gui)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
		new("UIPadding", {
			PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		}, frame)
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, frame)
		local labels = {}
		for index, name in ipairs({ "fps", "ping", "speed", "memory" }) do
			labels[name] = new("TextLabel", {
				BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = index,
				Font = FONT, TextSize = 13, TextColor3 = Config.Theme.Title, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
			}, frame)
		end
		local frames, clock = 0, 0
		maid:Add(RunService.RenderStepped:Connect(function(dt)
			frames += 1
			clock += dt
			if clock < 0.25 then
				return
			end
			local cfg = m.cfg
			labels.fps.Visible = cfg.ShowFps
			labels.fps.Text = string.format("FPS  %.0f", frames / clock)
			frames, clock = 0, 0

			labels.ping.Visible = cfg.ShowPing
			if cfg.ShowPing then
				local ok, ping = pcall(function()
					return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
				end)
				labels.ping.Text = ok and string.format("Ping  %.0f ms", finite(ping, 0)) or "Ping  n/a"
			end

			labels.speed.Visible = cfg.ShowSpeed
			if cfg.ShowSpeed then
				local root = getRoot()
				labels.speed.Text = string.format("Speed  %.1f", root and finite(root.AssemblyLinearVelocity.Magnitude, 0) or 0)
			end

			labels.memory.Visible = cfg.ShowMemory
			if cfg.ShowMemory then
				labels.memory.Text = string.format("Memory  %.0f MB", finite(Stats:GetTotalMemoryUsageMb(), 0))
			end
		end))
	end,
})

-- shared with the chunks that load after this one
S.widgetGui = widgetGui
S.makeGlass = makeGlass
S.makeDraggable = makeDraggable
S.teamColorOf = teamColorOf
S.nearestPlayers = nearestPlayers

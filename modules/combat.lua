-- Toolkit/modules/combat.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local Players, UserInputService, RunService, Workspace, SoundService, LocalPlayer = S.Players, S.UserInputService, S.RunService, S.Workspace, S.SoundService, S.LocalPlayer
local Env, Config, new, notify, getRoot, typingInChat = S.Env, S.Config, S.new, S.notify, S.getRoot, S.typingInChat
local Friends, AimState, setAimTarget, defineModule = S.Friends, S.AimState, S.setAimTarget, S.defineModule

-- ---------------------------------------------------------------------------------------
-- C1. POV Aim
-- ---------------------------------------------------------------------------------------

local function isVisible(camera, part, targetCharacter)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	local origin = camera.CFrame.Position
	local result = Workspace:Raycast(origin, part.Position - origin, params)
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

-- Picks the best target:
--   1. only targets really inside the view (angle from camera look vector, plus on-screen test),
--      so anything behind you or outside the screen is skipped and the search continues;
--   2. nearest to the local player wins; when two distances are within TieDistance the lower health wins.
-- The tie rule is not a strict ordering, but one linear scan with a small tolerance is stable enough here.
local function povPickTarget(cfg)
	local camera = Workspace.CurrentCamera
	local root = getRoot()
	if not camera or not root then
		return nil
	end
	local camPosition = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local cosLimit = math.cos(math.rad(math.clamp(cfg.PovAngle, 1, 180)))

	local bestPart, bestDistance, bestHealth
	for _, player in ipairs(Players:GetPlayers()) do
		local skip = player == LocalPlayer
			or (cfg.IgnoreFriends and Friends[player.UserId])
			or (cfg.TeamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team)
		if not skip then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local part = character and (character:FindFirstChild(cfg.TargetPart) or character:FindFirstChild("HumanoidRootPart"))
			if humanoid and part and humanoid.Health > 0 then
				local distance = (part.Position - root.Position).Magnitude
				if distance <= cfg.MaxDistance then
					local inView = true
					if cfg.PovCheck then
						local toTarget = part.Position - camPosition
						inView = toTarget.Magnitude > 0 and look:Dot(toTarget.Unit) >= cosLimit
					end
					if inView and cfg.OnScreenOnly then
						local _, onScreen = camera:WorldToViewportPoint(part.Position)
						inView = onScreen
					end
					if inView and cfg.WallCheck then
						inView = isVisible(camera, part, character)
					end
					if inView then
						local better = bestPart == nil
						if not better then
							if distance < bestDistance - cfg.TieDistance then
								better = true
							elseif math.abs(distance - bestDistance) <= cfg.TieDistance and humanoid.Health < bestHealth then
								better = true
							end
						end
						if better then
							bestPart, bestDistance, bestHealth = part, distance, humanoid.Health
						end
					end
				end
			end
		end
	end
	return bestPart
end

defineModule({
	id = "Aim", tab = "Combat", title = "POV Aim", key = Enum.KeyCode.V,
	desc = "Auto-aims at the nearest target inside your view.",
	defaults = {
		PovCheck = true, PovAngle = 70, OnScreenOnly = true, MaxDistance = 300, TeamCheck = true,
		WallCheck = false, IgnoreFriends = true, TargetPart = "Head", Smoothing = 18, TieDistance = 0.5,
		RequireRmb = false,
	},
	settings = function(ui)
		ui.Toggle("POV check", "PovCheck")
		ui.Slider("POV angle", "PovAngle", 10, 180, 5)
		ui.Toggle("On-screen only", "OnScreenOnly")
		ui.Slider("Max distance", "MaxDistance", 20, 1000, 10)
		ui.Toggle("Team check", "TeamCheck")
		ui.Toggle("Wall check", "WallCheck")
		ui.Toggle("Ignore friends", "IgnoreFriends")
		ui.Choice("Target part", "TargetPart", { "Head", "HumanoidRootPart", "UpperTorso", "Torso" })
		ui.Slider("Smoothing", "Smoothing", 1, 60, 1)
		ui.Slider("Tie distance", "TieDistance", 0, 5, 0.25)
		ui.Toggle("Hold right mouse", "RequireRmb")
	end,
	onEnable = function(m, maid)
		local target, clock = nil, 0
		local name = "ToolkitPovAim"
		-- Two loops on purpose: the expensive part (view-cone test, wall raycasts) runs at 20 Hz in Heartbeat,
		-- only the cheap camera interpolation runs on every rendered frame.
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			clock += dt
			if clock < Config.AimScanInterval then
				return
			end
			clock = 0
			target = povPickTarget(m.cfg)
			setAimTarget(target)
		end))
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt)
			if not target then
				return
			end
			local humanoid = target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
			if not target.Parent or not humanoid or humanoid.Health <= 0 then
				target = nil
				setAimTarget(nil) -- dead or gone: ESP and crosshair drop the lock in this very frame
				return
			end
			local cfg = m.cfg
			if typingInChat() then
				return
			end
			if cfg.RequireRmb and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				return
			end
			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end
			-- exponential smoothing: same feel at any frame rate
			local alpha = 1 - math.exp(-cfg.Smoothing * dt)
			local origin = camera.CFrame.Position
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(origin, target.Position), alpha)
		end)
		maid:Add(function()
			RunService:UnbindFromRenderStep(name)
			setAimTarget(nil)
		end)
	end,
})

-- ---------------------------------------------------------------------------------------
-- C1b. Combat extras: Hitboxes, TriggerBot, Hit Sound
-- ---------------------------------------------------------------------------------------

local function isOpponent(player, cfg)
	if player == LocalPlayer then
		return false
	end
	if cfg.IgnoreFriends and Friends[player.UserId] then
		return false
	end
	if cfg.TeamCheck and player.Team ~= nil and player.Team == LocalPlayer.Team then
		return false
	end
	return true
end

-- What the crosshair (screen centre) points at. Returns the player and the part that was hit.
local crosshairParams = RaycastParams.new()
crosshairParams.FilterType = Enum.RaycastFilterType.Exclude
local function crosshairTarget(maxDistance)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	crosshairParams.FilterDescendantsInstances = { LocalPlayer.Character }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * maxDistance, crosshairParams)
	if not result then
		return nil
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	return player, result.Instance
end

local lastAttack = 0
local clickWarned = false
-- Clicks for you: the equipped Tool is activated directly; without a tool, mouse1click or VirtualInputManager.
local function performClick()
	lastAttack = os.clock()
	local character = LocalPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool then
		tool:Activate()
		return true
	end
	if Env.mouse1click then
		return pcall(Env.mouse1click)
	end
	local ok = pcall(function()
		local input = game:GetService("VirtualInputManager")
		local mouse = UserInputService:GetMouseLocation()
		input:SendMouseButtonEvent(mouse.X, mouse.Y, 0, true, game, 0)
		input:SendMouseButtonEvent(mouse.X, mouse.Y, 0, false, game, 0)
	end)
	if not ok and not clickWarned then
		clickWarned = true
		notify("TriggerBot: no tool equipped and no way to click here")
	end
	return ok
end

local function customAsset(path)
	if not Env.getcustomasset then
		return nil
	end
	local ok, asset = pcall(Env.getcustomasset, path)
	return ok and asset or nil
end

local function normalizeSoundId(value)
	value = tostring(value or "")
	if string.find(value, "^rbxasset") then
		return value
	end
	local digits = string.match(value, "%d+")
	return digits and ("rbxassetid://" .. digits) or nil
end

defineModule({
	id = "Hitboxes", tab = "Combat", title = "Hitboxes",
	desc = "Makes other players easier to hit.",
	defaults = { Expand = 4, PartName = "HumanoidRootPart", MaxDistance = 40, TeamCheck = true, IgnoreFriends = true, ShowBox = false },
	settings = function(ui)
		ui.Slider("Expand (studs)", "Expand", 1, 12, 0.5)
		ui.Choice("Part", "PartName", { "HumanoidRootPart", "Head" })
		ui.Slider("Max distance", "MaxDistance", 10, 150, 5)
		ui.Toggle("Team check", "TeamCheck")
		ui.Toggle("Ignore friends", "IgnoreFriends")
		ui.Toggle("Show box", "ShowBox")
		ui.Note("Part sizes you change on other players only exist on your own client, so this helps in games that test hits on the client.")
	end,
	onEnable = function(m, maid)
		local active -- { player, part, size, transparency, canCollide } for the nearest opponent
		local function restore()
			local entry = active
			active = nil
			if entry and entry.part.Parent then
				entry.part.Size = entry.size
				entry.part.Transparency = entry.transparency
				entry.part.CanCollide = entry.canCollide
			end
		end
		maid:Add(restore)

		-- pick the nearest opponent ten times a second
		local clock = 0
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			clock += dt
			if clock < 0.1 then
				return
			end
			clock = 0
			local root, cfg = getRoot(), m.cfg
			if not root then
				restore()
				return
			end
			local bestPlayer, bestPart, bestDistance
			for _, player in ipairs(Players:GetPlayers()) do
				if isOpponent(player, cfg) then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local part = character and character:FindFirstChild(cfg.PartName)
					if humanoid and part and humanoid.Health > 0 then
						local distance = (part.Position - root.Position).Magnitude
						if distance <= cfg.MaxDistance and (not bestDistance or distance < bestDistance) then
							bestPlayer, bestPart, bestDistance = player, part, distance
						end
					end
				end
			end
			if active and active.part ~= bestPart then
				restore() -- the nearest opponent changed (or nobody is in range): old one gets its size back
			end
			if bestPart and not active then
				active = {
					player = bestPlayer, part = bestPart, size = bestPart.Size,
					transparency = bestPart.Transparency, canCollide = bestPart.CanCollide,
				}
			end
		end))

		-- enforced on every physics step: some games reset CanCollide / Size, and a dead target must be restored at once
		maid:Add(RunService.Stepped:Connect(function()
			local entry = active
			if not entry then
				return
			end
			local character = entry.player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not entry.part.Parent or not humanoid or humanoid.Health <= 0 then
				restore()
				return
			end
			local expand = m.cfg.Expand
			local goal = entry.size + Vector3.new(expand, expand, expand)
			if entry.part.Size ~= goal then
				entry.part.Size = goal
			end
			entry.part.CanCollide = false
			entry.part.Transparency = m.cfg.ShowBox and 0.7 or entry.transparency
		end))
	end,
})

defineModule({
	id = "TriggerBot", tab = "Combat", title = "TriggerBot",
	desc = "Clicks for you when your crosshair is on an opponent.",
	defaults = { CPS = 8, MaxDistance = 25, TeamCheck = true, IgnoreFriends = true, OnlyWhenLocked = false },
	settings = function(ui)
		ui.Slider("Clicks per second", "CPS", 1, 20, 1)
		ui.Slider("Max distance", "MaxDistance", 5, 200, 5)
		ui.Toggle("Team check", "TeamCheck")
		ui.Toggle("Ignore friends", "IgnoreFriends")
		ui.Toggle("Only when POV Aim locked", "OnlyWhenLocked")
		ui.Note("Hits are tested with a ray from the screen centre, so an enlarged Hitbox counts as a hit.")
	end,
	onEnable = function(m, maid)
		local timer = 0
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			timer += dt
			local cfg = m.cfg
			if timer < 1 / cfg.CPS or typingInChat() then
				return
			end
			local player = crosshairTarget(cfg.MaxDistance)
			if not player or not isOpponent(player, cfg) then
				return
			end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return
			end
			if cfg.OnlyWhenLocked and AimState.player ~= player then
				return
			end
			timer = 0
			performClick()
		end))
	end,
})

defineModule({
	id = "HitSound", tab = "Combat", title = "Hit Sound",
	desc = "Plays a sound when you land a hit.",
	defaults = { Source = "Sound ID", SoundId = "", Volume = 1, Range = 25 },
	settings = function(ui)
		ui.Choice("Source", "Source", { "Sound ID", "File" })
		ui.Text("Sound ID", "SoundId", "Roblox sound id")
		ui.Slider("Volume", "Volume", 0.1, 3, 0.1)
		ui.Slider("Range", "Range", 5, 100, 5)
		ui.Note("File mode plays " .. Config.Folder .. "/sounds/hit.mp3. A hit counts when an opponent in range loses health while your crosshair, your POV Aim lock or a recent click was on them. Re-enable after changing the source.")
	end,
	onEnable = function(m, maid)
		local soundId
		if m.cfg.Source == "File" then
			soundId = customAsset(Config.Folder .. "/sounds/hit.mp3")
		end
		soundId = soundId or normalizeSoundId(m.cfg.SoundId)
		if not soundId then
			notify("Hit Sound: type a Sound ID or put hit.mp3 in " .. Config.Folder .. "/sounds")
			return false
		end
		local sound = maid:Add(new("Sound", { SoundId = soundId, Volume = m.cfg.Volume }, SoundService))
		local lastHealth, clock = {}, 0
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			clock += dt
			if clock < 0.05 then
				return
			end
			clock = 0
			local root = getRoot()
			if not root then
				return
			end
			local crossPlayer = crosshairTarget(m.cfg.Range)
			local recentClick = os.clock() - lastAttack <= 0.6
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player ~= LocalPlayer and player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local health, before = humanoid.Health, lastHealth[player]
					lastHealth[player] = health
					local part = character:FindFirstChild("HumanoidRootPart")
					if before and health < before and part and (part.Position - root.Position).Magnitude <= m.cfg.Range then
						if AimState.player == player or crossPlayer == player or recentClick then
							sound.Volume = m.cfg.Volume
							sound.TimePosition = 0
							sound:Play()
						end
					end
				end
			end
		end))
		maid:Add(UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				lastAttack = os.clock()
			end
		end))
	end,
})

-- shared with the chunks that load after this one
S.isVisible = isVisible
S.povPickTarget = povPickTarget
S.isOpponent = isOpponent
S.crosshairParams = crosshairParams
S.crosshairTarget = crosshairTarget
S.lastAttack = lastAttack
S.clickWarned = clickWarned
S.performClick = performClick
S.customAsset = customAsset
S.normalizeSoundId = normalizeSoundId

-- Toolkit/modules/move.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local UserInputService, RunService, Workspace, LocalPlayer, Config, Maid = S.UserInputService, S.RunService, S.Workspace, S.LocalPlayer, S.Config, S.Maid
local anim, getHumanoid, getRoot, typingInChat, Modules, defineModule = S.anim, S.getHumanoid, S.getRoot, S.typingInChat, S.Modules, S.defineModule
local teleportTo, teleportToSelected, teleportToNextPlayer = S.teleportTo, S.teleportToSelected, S.teleportToNextPlayer

-- ---------------------------------------------------------------------------------------
-- C2. Movement
-- ---------------------------------------------------------------------------------------

defineModule({
	id = "Speed", tab = "Move", title = "Speed", key = Enum.KeyCode.Z,
	desc = "Makes you move faster than normal.",
	defaults = { Value = 60 },
	settings = function(ui)
		ui.Slider("Walk speed", "Value", 16, 200, 1)
	end,
	onEnable = function(m, maid)
		maid:Add(RunService.Heartbeat:Connect(function()
			local humanoid = getHumanoid()
			if not humanoid then
				return
			end
			if m.humanoid ~= humanoid then
				m.humanoid, m.saved = humanoid, humanoid.WalkSpeed
			end
			humanoid.WalkSpeed = m.cfg.Value
		end))
	end,
	onDisable = function(m)
		if m.humanoid and m.humanoid.Parent and m.saved then
			m.humanoid.WalkSpeed = m.saved
		end
		m.humanoid, m.saved = nil, nil
	end,
})

defineModule({
	id = "HighJump", tab = "Move", title = "High Jump", key = Enum.KeyCode.C,
	desc = "Lets you jump much higher than normal.",
	defaults = { Power = 100, Height = 20 },
	settings = function(ui)
		ui.Slider("Jump power", "Power", 50, 300, 1)
		ui.Slider("Jump height", "Height", 5, 100, 1)
	end,
	onEnable = function(m, maid)
		maid:Add(RunService.Heartbeat:Connect(function()
			local humanoid = getHumanoid()
			if not humanoid then
				return
			end
			if m.humanoid ~= humanoid then
				m.humanoid = humanoid
				m.saved = { usePower = humanoid.UseJumpPower, power = humanoid.JumpPower, height = humanoid.JumpHeight }
			end
			if humanoid.UseJumpPower then
				humanoid.JumpPower = m.cfg.Power
			else
				humanoid.JumpHeight = m.cfg.Height
			end
		end))
	end,
	onDisable = function(m)
		local humanoid, saved = m.humanoid, m.saved
		if humanoid and humanoid.Parent and saved then
			if saved.usePower then
				humanoid.JumpPower = saved.power
			else
				humanoid.JumpHeight = saved.height
			end
		end
		m.humanoid, m.saved = nil, nil
	end,
})

defineModule({
	id = "InfiniteJump", tab = "Move", title = "Infinite Jump", key = Enum.KeyCode.X,
	desc = "Jump again without touching the ground.",
	onEnable = function(_, maid)
		maid:Add(UserInputService.JumpRequest:Connect(function()
			local humanoid = getHumanoid()
			if humanoid then
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end))
	end,
})

defineModule({
	id = "Fly", tab = "Move", title = "Fly", key = Enum.KeyCode.F,
	desc = "Lets you fly around freely.",
	defaults = { Speed = 80, Pose = "Swim" },
	settings = function(ui)
		ui.Slider("Fly speed", "Speed", 10, 300, 1)
		ui.Choice("Pose", "Pose", { "Swim", "Freefall" })
	end,
	onEnable = function(m, maid)
		local humanoid, root = getHumanoid(), getRoot()
		if not humanoid or not root then
			return false
		end
		local autoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false -- the body orientation is set below, the humanoid must not fight it
		local pitch, roll = 0, 0
		maid:Add(function()
			local h, r = getHumanoid(), getRoot()
			if h then
				h.AutoRotate = autoRotate
				h:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			if r then
				r.AssemblyLinearVelocity = Vector3.zero
				-- stand upright again (the tilt follower dies with this connection)
				local look = r.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 0.01 then
					r.CFrame = CFrame.lookAt(r.Position, r.Position + flat)
				end
			end
		end)
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			local camera, r, h = Workspace.CurrentCamera, getRoot(), getHumanoid()
			if not camera or not r or not h or h.Health <= 0 then
				return
			end
			-- no PlatformStand: a swim / freefall pose keeps the character animated instead of frozen
			h:ChangeState(m.cfg.Pose == "Freefall" and Enum.HumanoidStateType.Freefall or Enum.HumanoidStateType.Swimming)

			local cf = camera.CFrame
			local forward, back, left, right = false, false, false, false
			local direction = Vector3.zero
			if not typingInChat() then
				forward = UserInputService:IsKeyDown(Enum.KeyCode.W)
				back = UserInputService:IsKeyDown(Enum.KeyCode.S)
				left = UserInputService:IsKeyDown(Enum.KeyCode.A)
				right = UserInputService:IsKeyDown(Enum.KeyCode.D)
				if forward then direction += cf.LookVector end
				if back then direction -= cf.LookVector end
				if right then direction += cf.RightVector end
				if left then direction -= cf.RightVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
				if UserInputService:IsKeyDown(Config.FlyDownKey) then direction -= Vector3.yAxis end
			end

			local now = os.clock()
			local idle = direction.Magnitude < 0.01
			-- idle = hover: a slow vertical bob instead of standing still
			r.AssemblyLinearVelocity = idle and Vector3.new(0, math.sin(now * 2.2) * 0.8, 0) or direction.Unit * m.cfg.Speed
			r.AssemblyAngularVelocity = Vector3.zero

			-- dynamic body tilt: lean forward on W, bank on A/D, gentle sway while hovering.
			-- Negative pitch leans the head forward; follow() eases in and back to upright when the key is released.
			local tilt = Config.Flight
			local pitchTarget = forward and -math.rad(tilt.PitchDeg) or (back and math.rad(15) or 0)
			local rollTarget = math.rad(tilt.RollDeg) * ((left and 1 or 0) - (right and 1 or 0))
			if idle then
				pitchTarget += math.sin(now * 1.1) * math.rad(3)
				rollTarget += math.sin(now * 1.6) * math.rad(4)
			end
			pitch = anim.follow(pitch, pitchTarget, tilt.TiltRate, dt)
			roll = anim.follow(roll, rollTarget, tilt.TiltRate, dt)

			local look = cf.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				r.CFrame = CFrame.lookAt(r.Position, r.Position + flat) * CFrame.Angles(pitch, 0, roll)
			end
		end))
	end,
})

defineModule({
	id = "Phase", tab = "Move", title = "Phase",
	desc = "Lets you walk through walls.",
	onEnable = function(m, maid)
		m.touched = {}
		maid:Add(RunService.Stepped:Connect(function()
			local character = LocalPlayer.Character
			if not character then
				return
			end
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					m.touched[part] = true
					part.CanCollide = false
				end
			end
		end))
	end,
	onDisable = function(m)
		for part in pairs(m.touched or {}) do
			if part.Parent then
				part.CanCollide = true
			end
		end
		m.touched = nil
	end,
})

defineModule({
	id = "Spider", tab = "Move", title = "Spider",
	desc = "Lets you climb straight up walls.",
	defaults = { Speed = 30 },
	settings = function(ui)
		ui.Slider("Climb speed", "Speed", 10, 80, 1)
	end,
	onEnable = function(m, maid)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		maid:Add(RunService.Heartbeat:Connect(function()
			local humanoid, root = getHumanoid(), getRoot()
			if not humanoid or not root or humanoid.MoveDirection.Magnitude < 0.1 then
				return
			end
			params.FilterDescendantsInstances = { LocalPlayer.Character }
			-- a short ray in the move direction: if a wall is right there, push upward
			if Workspace:Raycast(root.Position, humanoid.MoveDirection.Unit * 2.5, params) then
				local velocity = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(velocity.X, m.cfg.Speed, velocity.Z)
			end
		end))
	end,
})

defineModule({
	id = "Gravity", tab = "Move", title = "Gravity",
	desc = "Lowers gravity so you fall more slowly.",
	defaults = { Value = 60 },
	settings = function(ui)
		ui.Slider("Gravity", "Value", 0, 196, 2)
	end,
	onEnable = function(m, maid)
		m.saved = Workspace.Gravity
		maid:Add(RunService.Heartbeat:Connect(function()
			Workspace.Gravity = m.cfg.Value
		end))
	end,
	onDisable = function(m)
		if m.saved then
			Workspace.Gravity = m.saved
		end
		m.saved = nil
	end,
})

defineModule({
	id = "AntiFall", tab = "Move", title = "Anti Fall",
	desc = "Catches you before you fall into the void.",
	defaults = { Margin = 60 },
	settings = function(ui)
		ui.Slider("Margin (studs)", "Margin", 20, 300, 10)
	end,
	onEnable = function(m, maid)
		local lastSafe
		maid:Add(RunService.Heartbeat:Connect(function()
			local humanoid, root = getHumanoid(), getRoot()
			if not humanoid or not root then
				return
			end
			-- trigger a little above the engine's own destroy height
			local limit = Workspace.FallenPartsDestroyHeight + m.cfg.Margin
			if root.Position.Y > limit + 5 and humanoid.FloorMaterial ~= Enum.Material.Air then
				lastSafe = root.Position
			elseif root.Position.Y <= limit and lastSafe then
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = CFrame.new(lastSafe + Vector3.new(0, 4, 0))
			end
		end))
	end,
})

-- Shared ledge controller: one downward raycast per frame serves both Safe Walk and Ledge Jump.
-- Priority: Ledge Jump wins. When it fires, Safe Walk does not stop the character at the edge.
-- Both sleep completely while Fly is on, while airborne, and while the jump key is held (Safe Walk).
local Ledge = { users = 0, maid = nil, bypassUntil = 0, lastJump = 0 }
local ledgeParams = RaycastParams.new()
ledgeParams.FilterType = Enum.RaycastFilterType.Exclude

local function edgeAhead(humanoid, root, direction, dt)
	local velocity = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	-- look only a hair ahead (scaled by speed), so the jump happens at the last moment before the feet leave the block
	local lookAhead = math.clamp(horizontal * dt * 2.2, 0.3, 3)
	local feet = humanoid.HipHeight + root.Size.Y / 2
	ledgeParams.FilterDescendantsInstances = { LocalPlayer.Character }
	local origin = root.Position + direction * lookAhead
	return Workspace:Raycast(origin, Vector3.new(0, -(feet + Config.Ledge.Drop), 0), ledgeParams) == nil
end

local function ledgeStep(dt)
	local fly = Modules.Fly
	if fly and fly.enabled then
		return
	end
	local ledgeOn = Modules.LedgeJump and Modules.LedgeJump.enabled
	local safeOn = Modules.SafeWalk and Modules.SafeWalk.enabled
	if not ledgeOn and not safeOn then
		return
	end
	local humanoid, root = getHumanoid(), getRoot()
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local move = humanoid.MoveDirection
	if humanoid.FloorMaterial == Enum.Material.Air or move.Magnitude < 0.1 then
		return
	end
	local direction = Vector3.new(move.X, 0, move.Z).Unit
	if not edgeAhead(humanoid, root, direction, dt) then
		return
	end
	local now = os.clock()
	if ledgeOn then
		if now - Ledge.lastJump > 0.3 then
			Ledge.lastJump, Ledge.bypassUntil = now, now + 0.35
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		return -- Safe Walk is bypassed while Ledge Jump owns the edge
	end
	local jumpHeld = humanoid.Jump or UserInputService:IsKeyDown(Enum.KeyCode.Space)
	if now > Ledge.bypassUntil and not jumpHeld then
		-- remove the part of the velocity that points toward the drop
		local velocity = root.AssemblyLinearVelocity
		local along = velocity:Dot(direction)
		if along > 0 then
			root.AssemblyLinearVelocity = velocity - direction * along
		end
	end
end

local function ledgeEnable(_, maid)
	Ledge.users += 1
	if Ledge.users == 1 then
		Ledge.maid = Maid.new()
		Ledge.maid:Add(RunService.Heartbeat:Connect(ledgeStep))
	end
	maid:Add(function()
		Ledge.users = math.max(0, Ledge.users - 1)
		if Ledge.users == 0 and Ledge.maid then
			Ledge.maid:Clean()
			Ledge.maid = nil
		end
	end)
end

defineModule({
	id = "SafeWalk", tab = "Move", title = "Safe Walk",
	desc = "Prevents you from walking off ledges.",
	onEnable = ledgeEnable,
})

defineModule({
	id = "LedgeJump", tab = "Move", title = "Ledge Jump",
	desc = "Jumps for you at the very edge of a block.",
	onEnable = ledgeEnable,
})

defineModule({
	id = "SpinBot", tab = "Move", title = "Spin Bot",
	desc = "Spins your body, your camera stays level.",
	defaults = { Speed = 720 },
	settings = function(ui)
		ui.Slider("Spin speed (deg/s)", "Speed", 90, 2160, 30)
	end,
	onEnable = function(m, maid)
		local humanoid = getHumanoid()
		if not humanoid then
			return false
		end
		local autoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
		maid:Add(function()
			local h = getHumanoid()
			if h then
				h.AutoRotate = autoRotate
			end
		end)
		-- Only the character is rotated. The camera script keeps its own mouse-driven rotation,
		-- so your view stays level while other players see the body spin.
		local angle = 0
		maid:Add(RunService.Heartbeat:Connect(function(dt)
			local root, fly = getRoot(), Modules.Fly
			if not root or (fly and fly.enabled) then
				return
			end
			angle = (angle + math.rad(m.cfg.Speed) * dt) % (math.pi * 2)
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, angle, 0)
		end))
	end,
})

defineModule({
	id = "ClickTeleport", tab = "Move", title = "Click Teleport",
	desc = "Hold " .. Config.ClickTeleportModifier.Name .. " and click to teleport.",
	defaults = { HeightOffset = 3 },
	settings = function(ui)
		ui.Slider("Height offset", "HeightOffset", 0, 10, 0.5)
	end,
	onEnable = function(m, maid)
		maid:Add(UserInputService.InputBegan:Connect(function(input, processed)
			if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			if not UserInputService:IsKeyDown(Config.ClickTeleportModifier) then
				return
			end
			local camera, character = Workspace.CurrentCamera, LocalPlayer.Character
			if not camera or not character then
				return
			end
			local mouse = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			local result = Workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
			if result then
				teleportTo(result.Position + Vector3.new(0, m.cfg.HeightOffset, 0))
			end
		end))
	end,
})

defineModule({
	id = "Teleport", tab = "Move", title = "Teleport", noToggle = true,
	key = Enum.KeyCode.T, primary = teleportToNextPlayer,
	desc = "Teleport to other players (bind = next player).",
	settings = function(ui)
		ui.Picker("Player")
		ui.Button("Teleport to player", teleportToSelected)
		ui.Button("Teleport to next player", teleportToNextPlayer)
	end,
})

-- shared with the chunks that load after this one
S.Ledge = Ledge
S.ledgeParams = ledgeParams
S.edgeAhead = edgeAhead
S.ledgeStep = ledgeStep
S.ledgeEnable = ledgeEnable

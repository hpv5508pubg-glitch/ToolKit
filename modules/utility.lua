-- Toolkit/modules/utility.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local RunService, Workspace, SoundService, LocalPlayer, Env, Config = S.RunService, S.Workspace, S.SoundService, S.LocalPlayer, S.Env, S.Config
local new, notify, getHumanoid, Modules, Friends, Waypoints = S.new, S.notify, S.getHumanoid, S.Modules, S.Friends, S.Waypoints
local defineModule, setModule, getSelectedPlayer, waypointNames, saveWaypoint, teleportToWaypoint = S.defineModule, S.setModule, S.getSelectedPlayer, S.waypointNames, S.saveWaypoint, S.teleportToWaypoint
local deleteWaypoint, rejoin, serverHop, panic, customAsset, normalizeSoundId = S.deleteWaypoint, S.rejoin, S.serverHop, S.panic, S.customAsset, S.normalizeSoundId

-- ---------------------------------------------------------------------------------------
-- C4. Utility
-- ---------------------------------------------------------------------------------------

defineModule({
	id = "AntiAfk", tab = "Utility", title = "Anti-AFK",
	desc = "Prevents you from getting kicked for being idle.",
	onEnable = function(_, maid)
		maid:Add(LocalPlayer.Idled:Connect(function()
			local virtualUser = game:GetService("VirtualUser")
			virtualUser:CaptureController()
			virtualUser:ClickButton2(Vector2.new())
		end))
	end,
})

defineModule({
	id = "FpsUnlocker", tab = "Utility", title = "FPS Unlocker",
	desc = "Raises the framerate cap while enabled.",
	defaults = { Cap = 240 },
	settings = function(ui)
		ui.Slider("FPS cap", "Cap", 30, 360, 10)
	end,
	onEnable = function(m, maid)
		if not Env.setfpscap then
			notify("setfpscap is not available in this executor")
			return false
		end
		Env.setfpscap(m.cfg.Cap)
		-- the cap can be re-applied live when the slider moves
		local last = m.cfg.Cap
		maid:Add(RunService.Heartbeat:Connect(function()
			if m.cfg.Cap ~= last then
				last = m.cfg.Cap
				pcall(Env.setfpscap, last)
			end
		end))
	end,
	onDisable = function()
		if Env.setfpscap then
			pcall(Env.setfpscap, 60)
		end
	end,
})

defineModule({
	id = "PromptChanger", tab = "Utility", title = "Prompt Changer",
	desc = "Use interact prompts from further away and faster.",
	defaults = { Distance = 30, Instant = true },
	settings = function(ui)
		ui.Slider("Distance", "Distance", 10, 100, 5)
		ui.Toggle("Instant hold", "Instant")
		ui.Note("Re-enable the module to apply changed values to existing prompts.")
	end,
	onEnable = function(m, maid)
		local originals = setmetatable({}, { __mode = "k" })
		local function apply(object)
			if not object:IsA("ProximityPrompt") then
				return
			end
			if originals[object] == nil then
				originals[object] = { object.MaxActivationDistance, object.HoldDuration }
			end
			object.MaxActivationDistance = m.cfg.Distance
			if m.cfg.Instant then
				object.HoldDuration = 0
			end
		end
		for _, object in ipairs(Workspace:GetDescendants()) do
			apply(object)
		end
		maid:Add(Workspace.DescendantAdded:Connect(apply))
		maid:Add(function()
			for prompt, original in pairs(originals) do
				if prompt.Parent then
					prompt.MaxActivationDistance = original[1]
					prompt.HoldDuration = original[2]
				end
			end
		end)
	end,
})

defineModule({
	id = "Spectate", tab = "Utility", title = "Spectate",
	desc = "Watch another player.",
	settings = function(ui)
		ui.Picker("Player")
	end,
	onEnable = function(_, maid)
		if not getSelectedPlayer() then
			notify("pick a player first")
			return false
		end
		maid:Add(RunService.Heartbeat:Connect(function()
			local camera = Workspace.CurrentCamera
			local target = getSelectedPlayer()
			if not target then
				setModule("Spectate", false) -- target left the server
				return
			end
			local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
			if camera and humanoid and camera.CameraSubject ~= humanoid then
				camera.CameraSubject = humanoid
			end
		end))
	end,
	onDisable = function()
		local camera, humanoid = Workspace.CurrentCamera, getHumanoid()
		if camera and humanoid then
			camera.CameraSubject = humanoid
		end
	end,
})

defineModule({
	id = "Waypoints", tab = "Utility", title = "Waypoints", noToggle = true,
	desc = "Save positions and return to them.",
	defaults = { HeightOffset = 3 },
	settings = function(ui)
		ui.Cycle("Waypoint", waypointNames, function()
			return Waypoints.selected
		end, function(value)
			Waypoints.selected = value
		end)
		ui.Slider("Height offset", "HeightOffset", 0, 10, 0.5)
		ui.Button("Save current position", saveWaypoint)
		ui.Button("Teleport to waypoint", function()
			teleportToWaypoint(Modules.Waypoints.cfg.HeightOffset)
		end)
		ui.Button("Delete waypoint", deleteWaypoint)
	end,
})

defineModule({
	id = "Friends", tab = "Utility", title = "Friends", noToggle = true,
	desc = "Lets you mark other players as friendly.",
	settings = function(ui)
		ui.Picker("Player")
		ui.Button("Toggle friend for selected", function()
			local player = getSelectedPlayer()
			if not player then
				notify("pick a player first")
				return
			end
			if Friends[player.UserId] then
				Friends[player.UserId] = nil
				notify(player.Name .. " removed from friends")
			else
				Friends[player.UserId] = true
				notify(player.Name .. " marked friendly")
			end
		end)
		ui.Button("Clear friends", function()
			table.clear(Friends)
			notify("friends cleared")
		end)
		ui.Note("Friends are skipped by POV Aim. The list lasts for this session.")
	end,
})

local function listSoundFiles()
	local files = {}
	if Env.listfiles then
		local ok, entries = pcall(Env.listfiles, Config.Folder .. "/sounds")
		if ok and type(entries) == "table" then
			for _, path in ipairs(entries) do
				local name = string.match(path, "([^/\\]+)$")
				if name and string.lower(string.sub(name, -4)) == ".mp3" then
					table.insert(files, name)
				end
			end
		end
	end
	table.sort(files)
	return files
end

defineModule({
	id = "SongBeats", tab = "Utility", title = "Song Beats",
	desc = "Plays your own music files while you play.",
	defaults = { Mode = "Files", File = "", SoundId = "", Volume = 0.6, Loop = true },
	settings = function(ui)
		ui.Choice("Mode", "Mode", { "Files", "Sound ID" })
		ui.Cycle("File", listSoundFiles, function()
			local file = Modules.SongBeats.cfg.File
			return file ~= "" and file or nil
		end, function(value)
			Modules.SongBeats.cfg.File = value
		end)
		ui.Text("Sound ID", "SoundId", "Roblox sound id")
		ui.Slider("Volume", "Volume", 0, 2, 0.05)
		ui.Toggle("Loop", "Loop")
		ui.Note("Files mode plays .mp3 files from " .. Config.Folder .. "/sounds/. If the file cannot be loaded, the Sound ID is used instead.")
	end,
	onEnable = function(m, maid)
		local cfg = m.cfg
		local soundId
		if cfg.Mode == "Files" and cfg.File ~= "" then
			soundId = customAsset(Config.Folder .. "/sounds/" .. cfg.File)
			if not soundId then
				notify("Song Beats: could not load that file, trying the Sound ID")
			end
		end
		soundId = soundId or normalizeSoundId(cfg.SoundId)
		if not soundId then
			notify("Song Beats: pick a file or type a Sound ID")
			return false
		end
		local sound = maid:Add(new("Sound", { SoundId = soundId, Volume = cfg.Volume, Looped = cfg.Loop }, SoundService))
		maid:Add(sound.Ended:Connect(function()
			setModule("SongBeats", false)
		end))
		maid:Add(RunService.Heartbeat:Connect(function()
			sound.Volume = m.cfg.Volume
			sound.Looped = m.cfg.Loop
		end))
		sound:Play()
	end,
})

defineModule({
	id = "AnimationPlayer", tab = "Utility", title = "Animation Player",
	desc = "Plays an animation of your choosing.",
	defaults = { AnimationId = "", Speed = 1, Loop = true },
	settings = function(ui)
		ui.Text("Animation ID", "AnimationId", "Roblox animation id")
		ui.Slider("Speed", "Speed", 0.1, 3, 0.1)
		ui.Toggle("Loop", "Loop")
		ui.Note("Roblox only plays animations your account is allowed to use.")
	end,
	onEnable = function(m, maid)
		local id = string.match(tostring(m.cfg.AnimationId), "%d+")
		local humanoid = getHumanoid()
		if not id or not humanoid then
			notify("Animation Player: type an animation id first")
			return false
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or new("Animator", {}, humanoid)
		local animation = maid:Add(new("Animation", { AnimationId = "rbxassetid://" .. id }))
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not track then
			notify("Animation Player: could not load that animation")
			return false
		end
		track.Looped = m.cfg.Loop
		track:Play()
		maid:Add(function()
			track:Stop()
		end)
		maid:Add(RunService.Heartbeat:Connect(function()
			track:AdjustSpeed(m.cfg.Speed)
		end))
	end,
})

defineModule({
	id = "Rejoin", tab = "Utility", title = "Rejoin", noToggle = true,
	desc = "Rejoin the current server.",
	settings = function(ui)
		ui.Button("Rejoin now", rejoin)
	end,
})

defineModule({
	id = "ServerHop", tab = "Utility", title = "Server Hop", noToggle = true,
	desc = "Jump to another public server.",
	settings = function(ui)
		ui.Button("Hop now", serverHop)
	end,
})

defineModule({
	id = "Panic", tab = "Utility", title = "Panic", noToggle = true, primary = panic,
	desc = "Turns off every module that is currently on.",
	settings = function(ui)
		ui.Button("Turn everything off", panic)
	end,
})

-- Modules that touch the character are cleaned and re-hooked on respawn (see rehookCharacterModules in section G)
for _, id in ipairs({
	"Speed", "HighJump", "Fly", "Phase", "Spider", "AntiFall", "SafeWalk", "LedgeJump", "SpinBot", "Hitboxes",
	"Crosshair", "Cape", "ChinaHat", "GamingChair", "Disguise", "AnimationPlayer",
}) do
	if Modules[id] then
		Modules[id].character = true
	end
end

-- shared with the chunks that load after this one
S.listSoundFiles = listSoundFiles

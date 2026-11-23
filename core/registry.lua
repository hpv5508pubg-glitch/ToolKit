-- Toolkit/core/registry.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local Players, TeleportService, HttpService, LocalPlayer, Config, logError = S.Players, S.TeleportService, S.HttpService, S.LocalPlayer, S.Config, S.logError
local safeCall, Toolkit, Maid, notify, getRoot = S.safeCall, S.Toolkit, S.Maid, S.notify, S.getRoot

-- ======================================================================================
-- C. Modules
-- Each module: onEnable(m, maid) builds everything through the maid, onDisable(m) restores state.
-- onEnable may return false to refuse (state flips back, maid is cleaned).
-- ======================================================================================

local Modules, ModuleList = {}, {}
local Friends = {} -- userId -> true (skipped by aim)
local Selected = { Target = nil } -- shared player target for teleport / spectate / friends
local Waypoints = { list = {}, selected = nil, counter = 0 }
local Bind = { listening = nil } -- id of the module waiting for a key press
local Controls = {} -- "<moduleId>.<label>" -> { get, set }, filled by the UI builders and by `persist` keys
local ModuleListeners = {} -- called with (module) after a module turns on or off
local DEEP_RED = Config.DeepRed
local TargetGuiState = { visible = false } -- written by Target Info, read by Name Tags (no duplicate display)

local function addListener(list, callback)
	table.insert(list, callback)
	return function()
		local index = table.find(list, callback)
		if index then
			table.remove(list, index)
		end
	end
end
local function listenModules(callback)
	return addListener(ModuleListeners, callback)
end

-- Shared aim state: written by POV Aim, read by Crosshair, Player ESP, Name Tags, Target Info, TriggerBot, Hit Sound.
-- Listeners run the moment the lock changes, so colours switch in the same frame.
local AimState = { player = nil, part = nil, listeners = {} }
local function listenAim(callback)
	return addListener(AimState.listeners, callback)
end
local function setAimTarget(part)
	local player = part and Players:GetPlayerFromCharacter(part.Parent) or nil
	if AimState.part == part and AimState.player == player then
		return
	end
	AimState.part, AimState.player = part, player
	for _, callback in ipairs(AimState.listeners) do
		pcall(callback)
	end
end

local function defineModule(spec)
	local m = spec
	m.cfg = {}
	for key, value in pairs(spec.defaults or {}) do
		m.cfg[key] = value
	end
	m.enabled = false
	m.maid = Maid.new()
	m.bind = spec.key
	-- settings that have no widget (dragged widget positions) still travel with profiles
	for _, key in ipairs(spec.persist or {}) do
		Controls[m.id .. "." .. key] = {
			get = function()
				return m.cfg[key]
			end,
			set = function(value)
				if type(value) == "number" and value == value then
					m.cfg[key] = value
				end
			end,
		}
	end
	Modules[m.id] = m
	table.insert(ModuleList, m)
	return m
end

local function setModule(id, value, silent)
	local m = Modules[id]
	if not m or m.noToggle then
		return
	end
	value = value and true or false
	if m.enabled == value then
		return
	end
	if value then
		m.enabled = true
		local ok, result = pcall(m.onEnable, m, m.maid)
		if not ok or result == false then
			if not ok then
				logError("module " .. m.title, result)
			end
			m.enabled = false
			m.maid:Clean()
			if m.onDisable then
				safeCall("module " .. m.title .. " (disable)", m.onDisable, m)
			end
		end
	else
		m.enabled = false
		if m.onDisable then
			safeCall("module " .. m.title .. " (disable)", m.onDisable, m)
		end
		m.maid:Clean()
	end
	if not silent then
		notify(m.title .. (m.enabled and " ON" or " OFF"))
	end
	for _, callback in ipairs(ModuleListeners) do
		pcall(callback, m)
	end
	if Toolkit.RequestSave then
		Toolkit.RequestSave() -- a toggle is a discrete event, safe to save (debounced)
	end
end

local function trackPlayers(maid, onAdd, onRemove)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			onAdd(player)
		end
	end
	maid:Add(Players.PlayerAdded:Connect(function(player)
		if player ~= LocalPlayer then
			onAdd(player)
		end
	end))
	maid:Add(Players.PlayerRemoving:Connect(onRemove))
	maid:Add(function()
		for _, player in ipairs(Players:GetPlayers()) do
			pcall(onRemove, player)
		end
	end)
end

-- Shared actions ----------------------------------------------------------------------

local function getSelectedPlayer()
	if not Selected.Target then
		return nil
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Name == Selected.Target then
			return player
		end
	end
	return nil
end

local function teleportTo(position)
	local character = LocalPlayer.Character
	if not character then
		return false
	end
	local pivot = character:GetPivot()
	character:PivotTo(CFrame.new(position) * (pivot - pivot.Position))
	return true
end

local function teleportToPlayer(target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		notify("player not found")
		return false
	end
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		notify(target.Name .. " has no character")
		return false
	end
	notify("-> " .. target.Name)
	return teleportTo(targetRoot.CFrame:PointToWorldSpace(Vector3.new(0, 0, 4)))
end

local function teleportToSelected()
	local player = getSelectedPlayer()
	if not player then
		notify("pick a player first")
		return
	end
	teleportToPlayer(player)
end

local nextPlayerIndex = 0
local function teleportToNextPlayer()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(list, player)
		end
	end
	if #list == 0 then
		notify("no players to teleport to")
		return
	end
	table.sort(list, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	nextPlayerIndex = nextPlayerIndex % #list + 1
	teleportToPlayer(list[nextPlayerIndex])
end

local function refreshControls()
	if Toolkit.RefreshControls then
		Toolkit.RefreshControls()
	end
end

local function waypointNames()
	local names = {}
	for _, waypoint in ipairs(Waypoints.list) do
		table.insert(names, waypoint.name)
	end
	return names
end

local function saveWaypoint()
	local root = getRoot()
	if not root then
		notify("no character")
		return
	end
	Waypoints.counter += 1
	local name = "WP" .. Waypoints.counter
	table.insert(Waypoints.list, { name = name, position = root.Position })
	Waypoints.selected = name
	notify("saved " .. name)
	refreshControls()
end

local function teleportToWaypoint(offset)
	for _, waypoint in ipairs(Waypoints.list) do
		if waypoint.name == Waypoints.selected then
			teleportTo(waypoint.position + Vector3.new(0, offset, 0))
			return
		end
	end
	notify("no waypoint selected")
end

local function deleteWaypoint()
	for index, waypoint in ipairs(Waypoints.list) do
		if waypoint.name == Waypoints.selected then
			table.remove(Waypoints.list, index)
			local fallback = Waypoints.list[math.min(index, #Waypoints.list)]
			Waypoints.selected = fallback and fallback.name or nil
			refreshControls()
			return
		end
	end
	notify("no waypoint selected")
end

local function rejoin()
	local ok, err = pcall(function()
		if #Players:GetPlayers() <= 1 then
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		else
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end
	end)
	if not ok then
		notify("rejoin failed")
		logError("rejoin", err)
	end
end

local function serverHop()
	local url = string.format(
		"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
		game.PlaceId
	)
	local okGet, body = pcall(function()
		return game:HttpGet(url)
	end)
	if not okGet then
		notify("server list failed (HttpGet)")
		logError("server hop", body)
		return
	end
	local okJson, data = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if not okJson or type(data) ~= "table" or type(data.data) ~= "table" then
		notify("unexpected server list")
		return
	end
	local candidates = {}
	for _, server in ipairs(data.data) do
		if
			type(server) == "table"
			and server.id ~= game.JobId
			and type(server.playing) == "number"
			and type(server.maxPlayers) == "number"
			and server.playing < server.maxPlayers - 1
		then
			table.insert(candidates, server.id)
		end
	end
	if #candidates == 0 then
		notify("no other server found")
		return
	end
	local ok, err = pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, candidates[math.random(#candidates)], LocalPlayer)
	end)
	if not ok then
		notify("hop failed")
		logError("server hop", err)
	end
end

local function panic()
	for _, m in ipairs(ModuleList) do
		if m.enabled then
			setModule(m.id, false, true)
		end
	end
	notify("panic: all modules off")
end

-- shared with the chunks that load after this one
S.Modules = Modules
S.ModuleList = ModuleList
S.Friends = Friends
S.Selected = Selected
S.Waypoints = Waypoints
S.Bind = Bind
S.Controls = Controls
S.ModuleListeners = ModuleListeners
S.DEEP_RED = DEEP_RED
S.TargetGuiState = TargetGuiState
S.addListener = addListener
S.listenModules = listenModules
S.AimState = AimState
S.listenAim = listenAim
S.setAimTarget = setAimTarget
S.defineModule = defineModule
S.setModule = setModule
S.trackPlayers = trackPlayers
S.getSelectedPlayer = getSelectedPlayer
S.teleportTo = teleportTo
S.teleportToPlayer = teleportToPlayer
S.teleportToSelected = teleportToSelected
S.nextPlayerIndex = nextPlayerIndex
S.teleportToNextPlayer = teleportToNextPlayer
S.refreshControls = refreshControls
S.waypointNames = waypointNames
S.saveWaypoint = saveWaypoint
S.teleportToWaypoint = teleportToWaypoint
S.deleteWaypoint = deleteWaypoint
S.rejoin = rejoin
S.serverHop = serverHop
S.panic = panic

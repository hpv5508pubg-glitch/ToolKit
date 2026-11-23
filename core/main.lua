-- Toolkit/core/main.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local Players, UserInputService, LocalPlayer, Config, Log, logError = S.Players, S.UserInputService, S.LocalPlayer, S.Config, S.Log, S.logError
local Toolkit, connections, rootMaid, notify, Modules, ModuleList = S.Toolkit, S.connections, S.rootMaid, S.notify, S.Modules, S.ModuleList
local Bind, ModuleListeners, AimState, setModule, refreshControls, FFlags = S.Bind, S.ModuleListeners, S.AimState, S.setModule, S.refreshControls, S.FFlags
local restoreFlag, ScriptProfiles, buildUi = S.restoreFlag, S.ScriptProfiles, S.buildUi

-- ======================================================================================
-- G. Wiring and unload
-- ======================================================================================

table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	-- key capture for the bind badges has priority over everything else
	if Bind.listening then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local m = Modules[Bind.listening]
			Bind.listening = nil
			if m then
				if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
					m.bind = nil
				else
					for _, other in ipairs(ModuleList) do
						if other ~= m and other.bind == input.KeyCode then
							other.bind = nil -- a key belongs to one module
						end
					end
					m.bind = input.KeyCode
				end
			end
			if Toolkit.RefreshBinds then
				Toolkit.RefreshBinds()
			end
			Toolkit.RequestSave()
		end
		return
	end

	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if input.KeyCode == Config.ToggleKey then
		if Toolkit.ToggleMenu then
			Toolkit.ToggleMenu()
		end
		return
	end
	for _, m in ipairs(ModuleList) do
		if m.bind == input.KeyCode then
			if m.noToggle then
				if m.primary then
					m.primary()
				end
			else
				setModule(m.id, not m.enabled)
			end
			return
		end
	end
end))

table.insert(connections, Players.PlayerRemoving:Connect(function()
	task.defer(refreshControls)
end))

-- Respawn persistence: every enabled module that touches the character is torn down (its maid drops every
-- connection and instance) and re-hooked on the new character. Saving is paused meanwhile so the temporary
-- "off" state never reaches the profile.
local function rehookCharacterModules(character)
	local restart = {}
	for _, m in ipairs(ModuleList) do
		if m.character and m.enabled then
			table.insert(restart, m.id)
		end
	end
	if #restart == 0 then
		return
	end
	Toolkit.suppressSave = (Toolkit.suppressSave or 0) + 1
	for _, id in ipairs(restart) do
		setModule(id, false, true)
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if humanoid and root and LocalPlayer.Character == character then
			task.wait() -- let the default character scripts finish
			for _, id in ipairs(restart) do
				setModule(id, true, true)
			end
		end
		Toolkit.suppressSave -= 1
	end)
end
table.insert(connections, LocalPlayer.CharacterAdded:Connect(rehookCharacterModules))

-- Save when the game closes. BindToClose may not be allowed on the client, so leaving the server also saves.
pcall(function()
	game:BindToClose(function()
		Toolkit.FlushSave()
	end)
end)
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	if player == LocalPlayer then
		Toolkit.FlushSave()
	end
end))

function Toolkit.Unload()
	-- save first, while the modules still carry their on/off state
	pcall(Toolkit.FlushSave)
	Toolkit.unloaded = true
	for _, m in ipairs(ModuleList) do
		if m.enabled then
			setModule(m.id, false, true)
		end
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	-- put back every flag this session changed
	for flagName in pairs(FFlags.originals) do
		restoreFlag(flagName)
	end
	table.clear(ModuleListeners)
	table.clear(AimState.listeners)
	rootMaid:Clean()
	pcall(Log.Close) -- stop the console error hook of this session
	Toolkit.RefreshControls, Toolkit.RefreshBinds, Toolkit.ToggleMenu, Toolkit.MenuOpen = nil, nil, nil, nil
	_G.Toolkit = nil
end

Toolkit.Modules = Modules
Toolkit.Set = setModule
Toolkit.Config = Config
_G.Toolkit = Toolkit

local uiOk, uiErr = pcall(buildUi)
if not uiOk then
	logError("ui", uiErr)
	notify("UI failed, hotkeys still work")
end

-- apply the saved script profile, then the saved FFlags profile (each guarded on its own)
pcall(function()
	local data = ScriptProfiles.store:Get(ScriptProfiles.store.active)
	if data then
		ScriptProfiles.Apply(data)
	end
end)
pcall(function()
	if FFlags.store.active ~= "default" or next(FFlags.store:Get("default")) ~= nil then
		FFlags.Activate(FFlags.store.active)
	end
end)

notify("loaded - " .. Config.ToggleKey.Name .. " opens the menu, right-click a card for its settings")
return Toolkit

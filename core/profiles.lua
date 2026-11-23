-- Toolkit/core/profiles.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local Config, safe, Toolkit, Store, ModuleList, Controls = S.Config, S.safe, S.Toolkit, S.Store, S.ModuleList, S.Controls
local setModule = S.setModule

-- ======================================================================================
-- E. Script profiles (settings, keybinds, which modules were on) + smart auto-save
-- ======================================================================================

local ScriptProfiles = { store = Store.new("profiles") }

local function keyFromName(name)
	if type(name) ~= "string" then
		return nil
	end
	local ok, key = pcall(function()
		return Enum.KeyCode[name]
	end)
	return ok and key or nil
end

function ScriptProfiles.Snapshot()
	local data = { controls = {}, binds = {}, enabled = {} }
	for id, control in pairs(Controls) do
		local ok, value = pcall(control.get)
		if ok and value ~= nil then
			data.controls[id] = value
		end
	end
	for _, m in ipairs(ModuleList) do
		if m.bind then
			data.binds[m.id] = m.bind.Name
		end
		if m.enabled and not m.noToggle then
			data.enabled[m.id] = true
		end
	end
	return data
end

function ScriptProfiles.Apply(data)
	local controls = type(data.controls) == "table" and data.controls or {}
	local binds = type(data.binds) == "table" and data.binds or {}
	local enabled = type(data.enabled) == "table" and data.enabled or nil
	if next(controls) == nil and next(binds) == nil and enabled == nil then
		return -- an empty profile changes nothing
	end
	-- applying a profile must not write the profile back while it is half applied
	Toolkit.suppressSave = (Toolkit.suppressSave or 0) + 1
	pcall(function()
		for id, value in pairs(controls) do
			if Controls[id] then
				pcall(Controls[id].set, value)
			end
		end
		for _, m in ipairs(ModuleList) do
			if not m.noToggle or m.primary then
				m.bind = keyFromName(binds[m.id])
			end
		end
		if enabled and Config.RestoreEnabled then
			for _, m in ipairs(ModuleList) do
				if not m.noToggle then
					setModule(m.id, enabled[m.id] == true, true)
				end
			end
		end
	end)
	Toolkit.suppressSave -= 1
	if Toolkit.RefreshBinds then
		Toolkit.RefreshBinds()
	end
end

-- Auto-save. It is only ever requested after a discrete event: slider / color release, widget drag end,
-- a toggle or choice change, a keybind change, closing the menu, unload, or the game closing.
-- Requests inside half a second collapse into one disk write, and nothing is written while a drag is in progress.
local saveState = { pending = false }

local function flushSave()
	saveState.pending = false
	if not Config.AutoSave or Toolkit.unloaded then
		return
	end
	local store = ScriptProfiles.store
	safe("auto-save", function()
		store:Save(store.active, ScriptProfiles.Snapshot())
	end)
end

function Toolkit.RequestSave()
	if not Config.AutoSave or Toolkit.unloaded or (Toolkit.suppressSave or 0) > 0 or saveState.pending then
		return
	end
	saveState.pending = true
	task.delay(0.5, function()
		if (Toolkit.suppressSave or 0) > 0 then
			saveState.pending = false -- a profile is being applied or the character is re-hooking: skip this one
			return
		end
		flushSave()
	end)
end

function Toolkit.FlushSave()
	flushSave()
end

-- shared with the chunks that load after this one
S.ScriptProfiles = ScriptProfiles
S.keyFromName = keyFromName
S.saveState = saveState
S.flushSave = flushSave

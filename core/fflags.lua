-- Toolkit/core/fflags.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local HttpService, Env, Store = S.HttpService, S.Env, S.Store

-- ======================================================================================
-- D. FFlags manager
-- Profiles are maps { FlagName = value }. Applying needs an executor with setfflag; every flag gets an
-- honest per-flag result (applied / rejected / engine kept another value) instead of a blanket "done".
-- Many flags only take effect at client start; this tool cannot change that.
-- ======================================================================================

local FFlags = { store = Store.new("fflags"), originals = {}, status = "" }

local function flagToString(value)
	local kind = type(value)
	if kind == "boolean" then
		return value and "true" or "false"
	elseif kind == "number" then
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return string.format("%d", value)
		end
		return tostring(value)
	elseif kind == "string" then
		return value
	end
	return nil
end

-- Accepts {"FlagName": value, ...}. Also tolerates an array of {name, value} entries.
local function parseFlags(text)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok or type(decoded) ~= "table" then
		return nil, "that is not valid JSON"
	end
	local flags, count = {}, 0
	local function add(name, value)
		if type(name) == "string" and name ~= "" and flagToString(value) ~= nil then
			flags[name] = value
			count += 1
		end
	end
	if #decoded > 0 then
		for _, entry in ipairs(decoded) do
			if type(entry) == "table" then
				local name = entry.name or entry.Name or entry.flag or entry.Flag or entry.key or entry.Key
				local value = entry.value
				if value == nil then
					value = entry.Value
				end
				add(name, value)
			end
		end
	else
		for name, value in pairs(decoded) do
			add(name, value)
		end
	end
	if count == 0 then
		return nil, "no usable flags found (expected a JSON object like {\"FlagName\": value})"
	end
	return flags, count
end

function FFlags.Apply(flags)
	local report = { applied = 0, failed = {} }
	if not Env.setfflag then
		return report, "setfflag is not available in this executor, profiles are saved but cannot be applied"
	end
	for name, value in pairs(flags) do
		local text = flagToString(value)
		if text then
			if FFlags.originals[name] == nil then
				local original = false -- false = original value unknown
				if Env.getfflag then
					local okGet, current = pcall(Env.getfflag, name)
					if okGet and current ~= nil then
						original = tostring(current)
					end
				end
				FFlags.originals[name] = original
			end
			local ok, err = pcall(Env.setfflag, name, text)
			if not ok then
				table.insert(report.failed, name .. ": " .. tostring(err))
			elseif Env.getfflag then
				local okRead, now = pcall(Env.getfflag, name)
				if okRead and now ~= nil and string.lower(tostring(now)) ~= string.lower(text) then
					table.insert(report.failed, name .. ": engine kept " .. tostring(now))
				else
					report.applied += 1
				end
			else
				report.applied += 1
			end
		end
	end
	return report
end

local function restoreFlag(name)
	local original = FFlags.originals[name]
	FFlags.originals[name] = nil
	if original and Env.setfflag then
		pcall(Env.setfflag, name, original)
	end
end

local function describeReport(prefix, report, err)
	if err then
		return err
	end
	local text = string.format("%s: %d applied, %d failed", prefix, report.applied, #report.failed)
	if #report.failed > 0 then
		text ..= " (" .. report.failed[1] .. ")"
	end
	return text
end

function FFlags.Activate(name)
	local data = FFlags.store:Get(name)
	if not data then
		return "no such profile"
	end
	-- flags set by the previous profile but absent from this one go back to their original values
	for flagName in pairs(FFlags.originals) do
		if data[flagName] == nil then
			restoreFlag(flagName)
		end
	end
	FFlags.store:SetActive(name)
	local report, err = FFlags.Apply(data)
	FFlags.status = describeReport(name, report, err)
	return FFlags.status
end

function FFlags.AddPasted(text)
	local flags, info = parseFlags(text)
	if not flags then
		return info
	end
	local name = FFlags.store.active
	local data = FFlags.store:Get(name)
	for flagName, value in pairs(flags) do
		data[flagName] = value
	end
	FFlags.store:Save(name, data)
	local report, err = FFlags.Apply(flags)
	FFlags.status = describeReport("added " .. info .. " to " .. name, report, err)
	return FFlags.status
end

function FFlags.Reset()
	for flagName in pairs(FFlags.originals) do
		restoreFlag(flagName)
	end
	FFlags.store:SetActive("default")
	local report, err = FFlags.Apply(FFlags.store:Get("default"))
	FFlags.status = "reset to default. " .. describeReport("default", report, err)
	return FFlags.status
end

-- shared with the chunks that load after this one
S.FFlags = FFlags
S.flagToString = flagToString
S.parseFlags = parseFlags
S.restoreFlag = restoreFlag
S.describeReport = describeReport

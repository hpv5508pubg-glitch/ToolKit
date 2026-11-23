-- Toolkit/core/store.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local HttpService, Env, Config, safe, new = S.HttpService, S.Env, S.Config, S.safe, S.new

-- ======================================================================================
-- B. Profile store (shared by FFlags profiles and script profiles)
-- Layout on disk: <Folder>/<kind>/<name>.txt (JSON) and <Folder>/<kind>/_index.txt (order + active).
-- Without file functions the store works in memory for this session only.
-- ======================================================================================

local function cleanName(name)
	name = string.gsub(tostring(name or ""), "^%s*(.-)%s*$", "%1")
	if #name < 1 or #name > 24 or string.find(name, "[^%w _%-]") then
		return nil
	end
	return name
end

local Store = {}
Store.__index = Store

function Store.new(kind)
	local self = setmetatable({
		kind = kind,
		dir = Config.Folder .. "/" .. kind,
		data = {},
		order = { "default" },
		active = "default",
	}, Store)
	self:_load()
	return self
end

function Store:_path(name)
	return self.dir .. "/" .. name .. ".txt"
end

function Store:_ensureDir()
	if not Env.fs then
		return
	end
	pcall(function()
		if not isfolder(Config.Folder) then
			makefolder(Config.Folder)
		end
		if not isfolder(self.dir) then
			makefolder(self.dir)
		end
	end)
end

function Store:_writeIndex()
	if not Env.fs then
		return
	end
	self:_ensureDir()
	safe("profile write", function()
		writefile(self.dir .. "/_index.txt", HttpService:JSONEncode({ names = self.order, active = self.active }))
	end)
end

function Store:_writeProfile(name)
	if not Env.fs then
		return
	end
	self:_ensureDir()
	safe("profile write", function()
		writefile(self:_path(name), HttpService:JSONEncode(self.data[name]))
	end)
end

function Store:_load()
	self.data.default = {}
	if Env.fs then
		pcall(function()
			local indexPath = self.dir .. "/_index.txt"
			if not isfile(indexPath) then
				return
			end
			local index = HttpService:JSONDecode(readfile(indexPath))
			if type(index) ~= "table" then
				return
			end
			if type(index.names) == "table" then
				for _, name in ipairs(index.names) do
					if type(name) == "string" and name ~= "default" and not table.find(self.order, name) then
						table.insert(self.order, name)
					end
				end
			end
			if type(index.active) == "string" then
				self.active = index.active
			end
		end)
		for _, name in ipairs(self.order) do
			pcall(function()
				local path = self:_path(name)
				if isfile(path) then
					local decoded = HttpService:JSONDecode(readfile(path))
					if type(decoded) == "table" then
						self.data[name] = decoded
					end
				end
			end)
		end
	end
	for _, name in ipairs(self.order) do
		if self.data[name] == nil then
			self.data[name] = {}
		end
	end
	if self.data[self.active] == nil then
		self.active = "default"
	end
end

function Store:Get(name)
	return self.data[name]
end

function Store:Save(name, data)
	self.data[name] = data
	self:_writeProfile(name)
end

function Store:Create(name, data)
	name = cleanName(name)
	if not name then
		return nil, "invalid name (1-24 letters, digits, space, _ or -)"
	end
	if self.data[name] then
		return nil, "that profile already exists"
	end
	self.data[name] = data or {}
	table.insert(self.order, name)
	self:_writeProfile(name)
	self:_writeIndex()
	return name
end

function Store:Rename(old, new)
	if old == "default" then
		return nil, "default cannot be renamed"
	end
	if not self.data[old] then
		return nil, "no such profile"
	end
	new = cleanName(new)
	if not new then
		return nil, "invalid new name (type it in the name box first)"
	end
	if self.data[new] then
		return nil, "that profile already exists"
	end
	self.data[new] = self.data[old]
	self.data[old] = nil
	self.order[table.find(self.order, old)] = new
	if self.active == old then
		self.active = new
	end
	self:_writeProfile(new)
	if Env.fs and Env.delfile then
		pcall(delfile, self:_path(old))
	end
	self:_writeIndex()
	return new
end

function Store:Delete(name)
	if name == "default" then
		return nil, "default cannot be deleted"
	end
	if not self.data[name] then
		return nil, "no such profile"
	end
	self.data[name] = nil
	table.remove(self.order, table.find(self.order, name))
	if self.active == name then
		self.active = "default"
	end
	if Env.fs and Env.delfile then
		pcall(delfile, self:_path(name))
	end
	self:_writeIndex()
	return true
end

function Store:SetActive(name)
	if not self.data[name] then
		return false
	end
	self.active = name
	self:_writeIndex()
	return true
end

function Store:Export(name)
	return HttpService:JSONEncode(self.data[name] or {})
end

-- shared with the chunks that load after this one
S.cleanName = cleanName
S.Store = Store

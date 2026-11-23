-- loader.lua: the only file you run. It downloads the parts of the toolkit, runs them in order,
-- and writes errors (errors only, never normal activity) to <FOLDER>/logs/errors.log.
--
--   getgenv().ToolkitBase = "https://raw.githubusercontent.com/<USER>/<REPO>/refs/heads/main/"
--   loadstring(game:HttpGet(getgenv().ToolkitBase .. "loader.lua", true))()

-- Where the parts live. Normally this comes from the one-liner (getgenv().ToolkitBase, see the README), so this file
-- needs no editing. The text below is only a placeholder: it is UNSET until you provide your repository.
local BASE = (type(getgenv) == "function" and getgenv().ToolkitBase)
	or "https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/refs/heads/main/"
local SOURCE = "github" -- "github", or "local" to read <FOLDER>/dev/<part>.lua from your executor workspace while you edit
local FOLDER = "Toolkit" -- workspace folder used for logs, cache and profiles
local CACHE_BUST = true -- adds ?t=<time> to every URL so GitHub's raw cache is less likely to serve an old part

-- used only when manifest.lua cannot be downloaded
local FALLBACK_FILES = {
	{ "core/config", true }, { "core/runtime", true }, { "core/store", true }, { "core/registry", true },
	{ "modules/combat", false }, { "modules/move", false }, { "modules/visual", false }, { "modules/utility", false },
	{ "modules/errorlog", false }, { "core/fflags", true }, { "core/profiles", true }, { "ui/framework", true },
	{ "core/main", true },
}

local LogService = game:GetService("LogService")

-- leave no half-loaded instance behind when this is run a second time
if _G.Toolkit and _G.Toolkit.Unload then
	pcall(_G.Toolkit.Unload)
end

-- ======================================================================================
-- Error log (errors only)
-- ======================================================================================

local hasFs = type(writefile) == "function"
	and type(readfile) == "function"
	and type(isfile) == "function"
	and type(isfolder) == "function"
	and type(makefolder) == "function"

local Log = { path = FOLDER .. "/logs/errors.log", count = 0, last = nil, buffer = {}, seen = {}, started = false }

local function ensureFolders()
	if not hasFs then
		return
	end
	pcall(function()
		for _, dir in ipairs({ FOLDER, FOLDER .. "/logs", FOLDER .. "/cache" }) do
			if not isfolder(dir) then
				makefolder(dir)
			end
		end
	end)
end

local function writeOut(text)
	table.insert(Log.buffer, text)
	if #Log.buffer > 200 then
		table.remove(Log.buffer, 1)
	end
	if not hasFs then
		return
	end
	ensureFolders()
	pcall(function()
		if type(appendfile) == "function" then
			appendfile(Log.path, text)
		else
			local old = isfile(Log.path) and readfile(Log.path) or ""
			writefile(Log.path, old .. text)
		end
	end)
end

-- keeps the file small: when it grows past ~200 KB only the newest ~80 KB stay
local function trimIfLarge()
	if not hasFs then
		return
	end
	pcall(function()
		if isfile(Log.path) then
			local old = readfile(Log.path)
			if #old > 200000 then
				writefile(Log.path, "(older entries removed)\n" .. string.sub(old, -80000))
			end
		end
	end)
end

-- The same error repeated within 10 seconds is counted instead of written again, so an error that fires every
-- frame cannot flood the disk.
function Log.error(where, message)
	where, message = tostring(where), tostring(message)
	local key = where .. "|" .. message
	local now = os.clock()
	local seen = Log.seen[key]
	if seen and now - seen.time < 10 then
		seen.suppressed += 1
		return
	end
	if not Log.started then
		Log.started = true -- the session header is written lazily: a clean session leaves no trace in the file
		ensureFolders()
		trimIfLarge()
		local executor = "unknown executor"
		pcall(function()
			if type(identifyexecutor) == "function" then
				executor = tostring((identifyexecutor()))
			end
		end)
		writeOut(string.format("\n===== session %s | place %s | %s =====\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(game.PlaceId), executor))
	end
	if seen and seen.suppressed > 0 then
		writeOut(string.format("  (the previous error repeated %d more times)\n", seen.suppressed))
	end
	Log.seen[key] = { time = now, suppressed = 0 }
	Log.count += 1
	Log.last = { where = where, message = message }
	writeOut(string.format("[%s] [%s] %s\n", os.date("%H:%M:%S"), where, message))
	if Log.onError then
		pcall(Log.onError, where, message)
	end
end

function Log.read()
	if hasFs then
		local ok, text = pcall(function()
			return isfile(Log.path) and readfile(Log.path) or ""
		end)
		if ok then
			return text
		end
	end
	return table.concat(Log.buffer)
end

function Log.clear()
	table.clear(Log.buffer)
	table.clear(Log.seen)
	Log.count, Log.last = 0, nil
	if hasFs then
		pcall(writefile, Log.path, "")
	end
end

-- Errors thrown inside the parts show up in the console with the part's name ("Toolkit/modules/move:120: ...").
-- This hook copies exactly those console errors into the log.
Log.connection = LogService.MessageOut:Connect(function(message, messageType)
	if messageType == Enum.MessageType.MessageError and string.find(message, "Toolkit/", 1, true) then
		Log.error("console", message)
	end
end)

function Log.Close()
	if Log.connection then
		Log.connection:Disconnect()
		Log.connection = nil
	end
end

-- ======================================================================================
-- Download (or read) the parts
-- ======================================================================================

local function cachePath(path)
	return FOLDER .. "/cache/" .. string.gsub(path, "/", "_") .. ".lua"
end

local function cacheWrite(path, body)
	if hasFs then
		ensureFolders()
		pcall(writefile, cachePath(path), body)
	end
end

local function cacheRead(path)
	if hasFs then
		local ok, body = pcall(function()
			return isfile(cachePath(path)) and readfile(cachePath(path)) or nil
		end)
		return ok and body or nil
	end
	return nil
end

local function fetch(path)
	if SOURCE == "local" then
		local ok, body = pcall(readfile, FOLDER .. "/dev/" .. path .. ".lua")
		if ok and type(body) == "string" then
			return body
		end
		Log.error("loader", "cannot read " .. FOLDER .. "/dev/" .. path .. ".lua: " .. tostring(body))
		return nil
	end
	local url = BASE .. path .. ".lua" .. (CACHE_BUST and ("?t=" .. os.time()) or "")
	local lastError
	for attempt = 1, 3 do
		local ok, body = pcall(function()
			return game:HttpGet(url, true)
		end)
		-- raw.githubusercontent answers a missing file with a short "404: Not Found" body
		if ok and type(body) == "string" and #body > 0 and string.sub(body, 1, 3) ~= "404" then
			cacheWrite(path, body)
			return body
		end
		lastError = ok and ("unexpected answer: " .. string.sub(tostring(body), 1, 60)) or body
		task.wait(0.4 * attempt)
	end
	local cached = cacheRead(path)
	Log.error("loader", "download failed for " .. path .. ": " .. tostring(lastError) .. (cached and " (running the cached copy)" or ""))
	return cached
end

if SOURCE == "github" and string.find(BASE, "YOUR_USER", 1, true) then
	Log.Close()
	warn("[Toolkit] loader.lua: set BASE to your GitHub repository first (or use SOURCE = \"local\")")
	return
end

-- manifest.lua decides the order, so adding a part needs no loader change
local files = FALLBACK_FILES
local manifestSource = fetch("manifest")
if manifestSource then
	local chunk = loadstring(manifestSource, "=Toolkit/manifest")
	local ok, list = pcall(chunk or function() end)
	if ok and type(list) == "table" and #list > 0 then
		files = list
	else
		Log.error("loader", "manifest.lua is unreadable, using the built-in list")
	end
end

-- everything downloads at the same time, then the parts run one after another in manifest order
local results, pending = {}, #files
for _, entry in ipairs(files) do
	task.spawn(function()
		results[entry[1]] = fetch(entry[1]) or false
		pending -= 1
	end)
end
local deadline = os.clock() + 30
while pending > 0 and os.clock() < deadline do
	task.wait(0.05)
end

local S = { Log = Log, Folder = FOLDER, Source = SOURCE }

local function abort(path, reason)
	Log.error("loader", "stopped at " .. path .. ": " .. tostring(reason))
	warn("[Toolkit] failed to start, see " .. Log.path)
	pcall(function()
		if _G.Toolkit and _G.Toolkit.Unload then
			_G.Toolkit.Unload()
		end
	end)
	Log.Close()
end

for _, entry in ipairs(files) do
	local path, critical = entry[1], entry[2]
	local source = results[path]
	if not source then
		if critical then
			return abort(path, "the file could not be downloaded")
		end
		Log.error("loader", "skipped " .. path .. " (could not be downloaded)")
	else
		-- the chunk name becomes the prefix of every error message: "Toolkit/<part>:<line>: ..."
		local chunk, compileError = loadstring(source, "=Toolkit/" .. path)
		if not chunk then
			if critical then
				return abort(path, compileError)
			end
			Log.error(path, compileError)
		else
			local ok, err = xpcall(chunk, function(message)
				return tostring(message) .. "\n" .. debug.traceback("", 2)
			end, S)
			if not ok then
				if critical then
					return abort(path, err)
				end
				Log.error(path, err)
			end
		end
	end
end

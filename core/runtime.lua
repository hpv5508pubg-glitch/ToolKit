-- Toolkit/core/runtime.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local UserInputService, RunService, TextService, LocalPlayer, Env, Config = S.UserInputService, S.RunService, S.TextService, S.LocalPlayer, S.Env, S.Config
local FONT = S.FONT

-- Error logging comes from loader.lua (S.Log). Only errors are ever written to the log file.
local Log = S.Log
local function logError(where, message)
	Log.error(where, message)
end
-- run fn, log the error if it fails, hand back (ok, result)
local function safeCall(where, fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		logError(where, result)
	end
	return ok, result
end
local function safe(where, fn)
	return (safeCall(where, fn))
end

local Toolkit = {}
local connections = {} -- global connections, all disconnected in Toolkit.Unload

-- Maid: one cleanup bag per module so a module can never leak a connection or instance.
local Maid = {}
Maid.__index = Maid
function Maid.new()
	return setmetatable({ items = {} }, Maid)
end
function Maid:Add(item)
	table.insert(self.items, item)
	return item
end
function Maid:Clean()
	local items = self.items
	self.items = {}
	for index = #items, 1, -1 do
		local item = items[index]
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "Instance" then
			pcall(item.Destroy, item)
		elseif kind == "function" then
			pcall(item)
		elseif kind == "thread" then
			pcall(task.cancel, item)
		end
	end
end

local rootMaid = Maid.new() -- UI-level instances (screen gui, blur, ...)

-- Frame-rate independent animation. follow() is exponential decay toward a target:
-- the same curve at 30, 60 or 144 FPS, and re-targeting mid-flight never snaps.
local anim = {}
local followers, timers = {}, {}

function anim.follow(current, target, rate, dt)
	return target + (current - target) * math.exp(-rate * dt)
end
function anim.sineInOut(u)
	return 0.5 - math.cos(math.pi * u) / 2
end
function anim.quintOut(u)
	return 1 - (1 - u) ^ 5
end

function anim.newFollower(initial, rate, apply, epsilon)
	local follower = { value = initial, target = initial, rate = rate, apply = apply, epsilon = epsilon or 0.05 }
	function follower.Set(target, instant)
		follower.target = target
		if instant then
			follower.value = target
			follower.active = false
			apply(target)
			return
		end
		follower.active = true
		if not follower.queued then
			follower.queued = true
			followers[#followers + 1] = follower
		end
	end
	apply(initial)
	return follower
end

function anim.run(duration, curve, apply, onDone)
	local timer = { start = os.clock(), duration = duration, curve = curve, apply = apply, onDone = onDone }
	timers[#timers + 1] = timer
	return timer -- set timer.cancelled = true to stop it
end

local function stepAnimations(dt)
	local list = followers
	followers = {}
	for _, follower in ipairs(list) do
		if follower.active then
			follower.value = anim.follow(follower.value, follower.target, follower.rate, dt)
			if math.abs(follower.value - follower.target) <= follower.epsilon then
				follower.value = follower.target
				follower.active = false
			end
			follower.apply(follower.value)
		end
		if follower.active then
			followers[#followers + 1] = follower
		else
			follower.queued = false
		end
	end

	local now = os.clock()
	local pending = timers
	timers = {}
	for _, timer in ipairs(pending) do
		if not timer.cancelled then
			local u = math.clamp((now - timer.start) / timer.duration, 0, 1)
			timer.apply(timer.curve(u))
			if u >= 1 then
				if timer.onDone then
					timer.onDone()
				end
			else
				timers[#timers + 1] = timer
			end
		end
	end
end

table.insert(connections, RunService.RenderStepped:Connect(stepAnimations))

-- Small helpers ---------------------------------------------------------------------

local function new(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function getGuiRoot()
	local ok, hidden = pcall(function()
		return Env.gethui and Env.gethui() or nil
	end)
	if ok and hidden then
		return hidden
	end
	local okCore = pcall(function()
		return #game:GetService("CoreGui"):GetChildren()
	end)
	if okCore then
		return game:GetService("CoreGui")
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end
local GuiRoot = getGuiRoot()

-- Custom glass toasts: they slide in from the right edge (anim.follow) and fade out after Config.Toast.Seconds.
local toastGui, toastList
local toastCount = 0

local function ensureToastGui()
	if toastGui and toastGui.Parent then
		return
	end
	toastGui = rootMaid:Add(new("ScreenGui", {
		Name = "TkToasts", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1200,
	}, GuiRoot))
	toastList = new("Frame", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(360, 420), BackgroundTransparency = 1,
	}, toastGui)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}, toastList)
end

local function notify(text)
	text = tostring(text)
	local ok = pcall(function()
		ensureToastGui()
		local T = Config.Theme
		local width = math.min(340, TextService:GetTextSize(text, 14, FONT, Vector2.new(320, 60)).X + 34)
		toastCount += 1

		-- keep at most Config.Toast.Max toasts on screen: the oldest ones go first
		local live = {}
		for _, child in ipairs(toastList:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(live, child)
			end
		end
		table.sort(live, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 1, #live - Config.Toast.Max + 1 do
			live[index]:Destroy()
		end

		local holder = new("Frame", {
			BackgroundTransparency = 1, LayoutOrder = toastCount, Size = UDim2.fromOffset(width, 36),
		}, toastList)
		local card = new("Frame", {
			Position = UDim2.fromOffset(width + 30, 0), Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = T.Header, BackgroundTransparency = 0.18, BorderSizePixel = 0,
		}, holder)
		new("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		local rim = new("UIStroke", {
			Color = Color3.fromRGB(255, 255, 255), Transparency = 0.85, Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, card)
		local dot = new("Frame", {
			BackgroundColor3 = T.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 11), Size = UDim2.fromOffset(3, 14),
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 2) }, dot)
		local label = new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -30, 1, 0),
			Font = FONT, TextSize = 14, TextColor3 = T.Title, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = text,
		}, card)

		local slide = anim.newFollower(width + 30, Config.Anim.FollowFast, function(x)
			card.Position = UDim2.fromOffset(x, 0)
		end, 0.5)
		slide.Set(0)
		local fade = anim.newFollower(0, 6, function(a)
			card.BackgroundTransparency = 0.18 + 0.82 * a
			rim.Transparency = 0.85 + 0.15 * a
			dot.BackgroundTransparency = a
			label.TextTransparency = a
		end, 0.01)
		task.delay(Config.Toast.Seconds, function()
			fade.Set(1)
		end)
		task.delay(Config.Toast.Seconds + 0.9, function()
			holder:Destroy()
		end)
	end)
	if not ok then
		logError("toast", "could not show: " .. text)
	end
end

local function getHumanoid()
	local character = LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local character = LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function typingInChat()
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function finite(value, fallback)
	if type(value) ~= "number" or value ~= value or math.abs(value) > 1e9 then
		return fallback
	end
	return value
end

local function copyToClipboard(text)
	if Env.setclipboard then
		return pcall(Env.setclipboard, text)
	end
	return false
end

-- tell the user when something went wrong (at most once every 5 seconds); the details are in the log file
local lastErrorToast = 0
Log.onError = function(where)
	if where ~= "toast" and os.clock() - lastErrorToast > 5 then
		lastErrorToast = os.clock()
		notify("Error logged: " .. tostring(where))
	end
end

-- shared with the chunks that load after this one
S.Log = Log
S.logError = logError
S.safeCall = safeCall
S.safe = safe
S.Toolkit = Toolkit
S.connections = connections
S.Maid = Maid
S.rootMaid = rootMaid
S.anim = anim
S.followers = followers
S.timers = timers
S.stepAnimations = stepAnimations
S.new = new
S.getGuiRoot = getGuiRoot
S.GuiRoot = GuiRoot
S.toastGui = toastGui
S.toastList = toastList
S.toastCount = toastCount
S.ensureToastGui = ensureToastGui
S.notify = notify
S.getHumanoid = getHumanoid
S.getRoot = getRoot
S.typingInChat = typingInChat
S.finite = finite
S.copyToClipboard = copyToClipboard
S.lastErrorToast = lastErrorToast

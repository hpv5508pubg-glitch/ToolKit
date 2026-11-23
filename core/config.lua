-- Toolkit/core/config.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer


-- ======================================================================================
-- A. Environment, config, maid, animation
-- ======================================================================================

local Env = {
	gethui = type(gethui) == "function" and gethui or nil,
	setfflag = type(setfflag) == "function" and setfflag or nil,
	getfflag = type(getfflag) == "function" and getfflag or nil,
	setfpscap = type(setfpscap) == "function" and setfpscap or nil,
	setclipboard = (type(setclipboard) == "function" and setclipboard)
		or (type(toclipboard) == "function" and toclipboard)
		or nil,
	delfile = type(delfile) == "function" and delfile or nil,
	mouse1click = type(mouse1click) == "function" and mouse1click or nil,
	getcustomasset = (type(getcustomasset) == "function" and getcustomasset)
		or (type(getsynasset) == "function" and getsynasset)
		or nil,
	listfiles = type(listfiles) == "function" and listfiles or nil,
	fs = type(writefile) == "function"
		and type(readfile) == "function"
		and type(isfile) == "function"
		and type(isfolder) == "function"
		and type(makefolder) == "function",
}

local Config = {
	Folder = "Toolkit",
	ToggleKey = Enum.KeyCode.RightShift,
	ClickTeleportModifier = Enum.KeyCode.LeftControl,
	FlyDownKey = Enum.KeyCode.LeftShift,
	-- CanvasGroup gives the page fade. If text looks soft on your setup, set this to false (no fade, still slides).
	UseCanvasGroup = true,
	Theme = {
		Backdrop = Color3.fromRGB(48, 48, 48),
		BackdropTransparency = 0.75,
		BlurSize = 24,
		Header = Color3.fromRGB(20, 20, 20),
		Card = Color3.fromRGB(20, 20, 20),
		Outline = Color3.fromRGB(64, 64, 64),
		Title = Color3.fromRGB(221, 221, 221),
		Desc = Color3.fromRGB(153, 153, 153),
		DescHover = Color3.fromRGB(187, 187, 187),
		Accent = Color3.fromRGB(243, 93, 18),
		SwitchOff = Color3.fromRGB(64, 64, 64),
		Pill = Color3.fromRGB(64, 64, 64),
		Input = Color3.fromRGB(14, 14, 14),
		Danger = Color3.fromRGB(235, 72, 52),
		Badge = Color3.fromRGB(45, 45, 45),
		Knob = Color3.fromRGB(235, 235, 235),
	},
	-- Rates are per-second decay constants for anim.follow; times are seconds for timed curves.
	Anim = { FollowFast = 21.9, FollowCard = 23.1, PageSlide = 1.536, SwitchTime = 0.10, ModalTime = 0.30 },
	Layout = { CardWidth = 434, Gap = 8, CardHeader = 50, HeaderBar = 38, MaxPanelHeight = 600 },
	DeepRed = Color3.fromRGB(220, 20, 60), -- aim lock colour (crosshair + ESP outline)
	AutoSave = true, -- writes the active script profile on discrete events only, never while dragging
	RestoreEnabled = true, -- profiles also remember which modules were on
	AimScanInterval = 0.05, -- target scan at 20 Hz; the camera rotation still runs every frame
	EspMaxPlayers = 25, -- Roblox renders about 31 Highlights at once, stay well under that
	Flight = { PitchDeg = 50, RollDeg = 20, TiltRate = 9 },
	Ledge = { Drop = 3.5 }, -- studs below the feet that count as a ledge
	Toast = { Seconds = 2.5, Max = 5 },
}

local FONT, FONT_BOLD = Enum.Font.GothamMedium, Enum.Font.GothamBold
pcall(function()
	FONT = Enum.Font.BuilderSans
	FONT_BOLD = Enum.Font.BuilderSansBold
end)

-- shared with the chunks that load after this one
S.Players = Players
S.UserInputService = UserInputService
S.RunService = RunService
S.Workspace = Workspace
S.Lighting = Lighting
S.SoundService = SoundService
S.TeleportService = TeleportService
S.HttpService = HttpService
S.TextService = TextService
S.Stats = Stats
S.LocalPlayer = LocalPlayer
S.Env = Env
S.Config = Config
S.FONT = FONT
S.FONT_BOLD = FONT_BOLD

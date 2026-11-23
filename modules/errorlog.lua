-- Toolkit/modules/errorlog.lua
-- Part of the split build. Shared names are passed through the table S that loader.lua creates.
local S = ...
local Env, Log, notify, copyToClipboard, defineModule = S.Env, S.Log, S.notify, S.copyToClipboard, S.defineModule

-- Error Log card (Utility tab). The log file only contains errors; this card reads, copies and clears it.
defineModule({
	id = "ErrorLog", tab = "Utility", title = "Error Log", noToggle = true,
	desc = "Shows errors the script hit (errors only).",
	settings = function(ui)
		ui.Note(Log.path .. (Env.fs and "" or " (no file functions here: errors are only kept until you leave)"))
		ui.Button("Show the last error", function()
			local last = Log.last
			notify(last and (last.where .. ": " .. last.message) or "no errors logged this session")
		end)
		ui.Button("Copy the log", function()
			local text = Log.read()
			if text == "" then
				notify("the log is empty")
			elseif copyToClipboard(text) then
				notify("log copied to the clipboard")
			else
				notify("no clipboard function here, open " .. Log.path)
			end
		end)
		ui.Button("Clear the log", function()
			Log.clear()
			notify("log cleared")
		end)
	end,
})

-- shared with the chunks that load after this one


# Toolkit (split build)

`loader.lua` is the only file you run. It downloads `manifest.lua`, then every part listed in it, runs them in order
and logs errors (errors only) to `workspace/Toolkit/logs/errors.log`.

## Set it up
1. Create a **public** GitHub repository and upload everything in this folder to its root
   (`loader.lua`, `manifest.lua`, `core/`, `modules/`, `ui/`). On github.com: Add file > Upload files, drag the contents in, Commit.
2. Run this in your executor (replace `<USER>` and `<REPO>`; nothing inside the files needs editing):

```lua
getgenv().ToolkitBase = "https://raw.githubusercontent.com/<USER>/<REPO>/refs/heads/main/"
loadstring(game:HttpGet(getgenv().ToolkitBase .. "loader.lua", true))()
```

## Where things live
| File | What is in it |
| --- | --- |
| `core/config` | services, executor capabilities (`Env`), `Config` (colors, animation rates, limits) |
| `core/runtime` | Maid, `anim.follow`, helpers, toast notifications, error helpers |
| `core/store` | profile store (disk + memory) |
| `core/registry` | `defineModule`, `setModule`, shared actions (teleport, waypoints, rejoin, server hop, panic), aim state |
| `modules/combat` | POV Aim, Hitboxes, TriggerBot, Hit Sound |
| `modules/move` | Speed, High Jump, Fly, Phase, Spider, Safe Walk, Ledge Jump, Spin Bot, teleports ... |
| `modules/visual` | Player ESP, Name Tags, Target Info, Crosshair, Keystrokes, Cape, Disguise ... |
| `modules/utility` | Anti-AFK, FPS Unlocker, Song Beats, Animation Player, Waypoints, Friends ... |
| `modules/errorlog` | the Error Log card (read, copy, clear) |
| `core/fflags` | FFlags profiles, import / export, apply |
| `core/profiles` | script profiles and the smart auto-save |
| `ui/framework` | the whole menu |
| `core/main` | key handling, respawn re-hook, unload, start-up |

Parts share names through the table `S`: every top-level `local` of a part is exported to the next parts automatically
at the bottom of its file (`S.name = name`) and imported at the top. If you add a new top-level `local` that another
part needs, add it to the export list at the bottom of the file and to the import lines of the part that uses it.

## Fixing a bug
Open the log. Every line starts with the part and line: `Toolkit/modules/move:120: attempt to index nil ...`.
Edit that part only, push, run the loader again. The loader asks for a fresh copy of every part each time.

## Test without GitHub
Set `SOURCE = "local"` in `loader.lua`, copy this folder to `workspace/Toolkit/dev/`, and edit the files there.

## Add a module
Write `defineModule({ ... })` in any file under `modules/` (or add a new file and list it in `manifest.lua`).
A non-critical part (`false` in `manifest.lua`) that fails is skipped and the rest still starts.

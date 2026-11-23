-- manifest.lua: the load order. loader.lua downloads this first, so adding or renaming a part
-- needs no change to the loader. Format: { "path without .lua", critical }.
-- A critical part that fails stops the start; a non-critical part is skipped and the rest still runs.
return {
	{ "core/config", true },
	{ "core/runtime", true },
	{ "core/store", true },
	{ "core/registry", true },
	{ "modules/combat", false },
	{ "modules/move", false },
	{ "modules/visual", false },
	{ "modules/utility", false },
	{ "modules/errorlog", false },
	{ "core/fflags", true },
	{ "core/profiles", true },
	{ "ui/framework", true },
	{ "core/main", true },
}

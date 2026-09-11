-- Nothing Matrix uses its own focus-ring pairing. Other themes keep the
-- borders generated for them by dms.colors.
local settings_path = os.getenv("HOME") .. "/.config/DankMaterialShell/settings.json"
local settings_file = io.open(settings_path, "r")
local settings = ""

if settings_file then
	settings = settings_file:read("*a")
	settings_file:close()
end

if settings:match("/nothingMatrix/theme%.json") then
	hl.config({
		general = {
			col = {
				active_border = "rgb(d71921)",
				inactive_border = "rgb(e8e8e8)",
			},
		},
		group = {
			col = {
				border_active = "rgb(d71921)",
				border_inactive = "rgb(e8e8e8)",
			},
			groupbar = {
				col = {
					active = "rgb(d71921)",
					inactive = "rgb(e8e8e8)",
				},
			},
		},
	})
end

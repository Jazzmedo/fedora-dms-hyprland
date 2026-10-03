-- Match the useful rules from the Niri config and DMS defaults.
hl.window_rule({
	name = "firefox-picture-in-picture",
	match = { class = "firefox$", title = "^Picture-in-Picture$" },
	float = true,
})

hl.window_rule({ match = { class = "^(org\\.wezfurlong\\.wezterm)$" }, tile = true })
hl.window_rule({ match = { class = "^(gnome-control-center|pavucontrol|nm-connection-editor)$" }, tile = true })
hl.window_rule({ match = { class = "^(org\\.gnome\\.Calculator|gnome-calculator|galculator|blueman-manager)$" }, float = true })

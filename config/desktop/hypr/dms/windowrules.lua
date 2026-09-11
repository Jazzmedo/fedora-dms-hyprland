-- Match the useful rules from the Niri config and DMS defaults.
hl.window_rule({
	name = "firefox-picture-in-picture",
	match = { class = "firefox$", title = "^Picture-in-Picture$" },
	float = true,
})

hl.window_rule({ match = { class = "^(org\\.wezfurlong\\.wezterm)$" }, tile = true })
hl.window_rule({ match = { class = "^(gnome-control-center|pavucontrol|nm-connection-editor)$" }, tile = true })
hl.window_rule({ match = { class = "^(org\\.gnome\\.Calculator|gnome-calculator|galculator|blueman-manager)$" }, float = true })

-- Codex animates Kitty's title with a braille spinner while it is working.
-- Hyprland re-evaluates follow-mouse on every title update, which can steal
-- focus back from DMS Settings (and scroll the vertical layout) even when the
-- pointer has not moved. Ignore hover-focus only during those animated titles;
-- clicking or keyboard focus still works normally.
hl.window_rule({
	name = "ignore-codex-kitty-spinner-hover-refocus",
	match = {
		class = "^kitty$",
		title = "^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] hanafi$",
	},
	no_follow_mouse = true,
})

-- Follow links into the browser that handles them. Existing browser windows
-- can request activation when a new tab is opened through xdg-open/portals.
hl.window_rule({
	name = "focus-browser-on-link-activation",
	match = {
		class = "^(zen|firefox|librewolf|helium|brave-origin|brave-browser|Brave-browser|chromium|Chromium|google-chrome|Google-chrome)$",
	},
	focus_on_activate = true,
})

-- DMS reuses its Settings window. Let its activation request focus that
-- existing window when opened from the bar, without enabling global focus
-- stealing for other applications.
hl.window_rule({
	name = "focus-dms-settings-on-activate",
	match = { class = "^com\\.danklinux\\.dms$", title = "^Settings$" },
	focus_on_activate = true,
})

-- DMS/Quickshell surfaces should appear immediately and receive blur normally.
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^dms:.*" }, no_anim = true })

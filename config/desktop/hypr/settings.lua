hl.config({
	input = {
		kb_layout = "us,ara",
		kb_options = "grp:alt_shift_toggle",
		repeat_rate = 40,
		repeat_delay = 300,
		numlock_by_default = true,
		-- Hyprland's mode 1 re-evaluates the window below the pointer on
		-- unrelated surface/title updates.  In a scrolling layout that can move
		-- the whole column while the mouse is completely still.  Mode 2 plus the
		-- movement watcher below gives Niri's behaviour: hover focus follows real
		-- pointer movement, while stationary bar/title updates cannot steal it.
		follow_mouse = 2,
		-- Keep Niri-like hover focus when the pointer actually moves, but do not
		-- refocus a window merely because a DMS popup closed beneath a stationary
		-- pointer. This also stops fullscreen/scroller windows from stealing focus
		-- back immediately after DMS Settings is opened from the bar.
		mouse_refocus = false,
		sensitivity = 0.005,
		accel_profile = "flat",
		touchpad = {
			tap_to_click = true,
			natural_scroll = true,
			scroll_factor = 0.5,
		},
	},
	cursor = {
		-- Afterglow-cursors is an XCursor theme, not a Hyprcursor theme.
		-- Use the XCursor path so the configured Afterglow cursor remains
		-- consistent after reloads and DMS theme updates.
		enable_hyprcursor = false,
	},
	general = {
		gaps_in = 4,
		gaps_out = 4,
		border_size = 2,
		layout = "scrolling",
	},
	decoration = {
		rounding = 12,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		blur = {
			enabled = false,
			size = 10,
			passes = 3,
			new_optimizations = true,
		},
		shadow = {
			enabled = false,
			range = 30,
			render_power = 5,
			offset = "0 5",
			color = "rgba(00000070)",
		},
	},
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		-- Follow legitimate app activation requests to reused/restored windows,
		-- including tray items whose window lives on another workspace.
		focus_on_activate = true,
	},
	scrolling = {
		column_width = 0.5,
		explicit_column_widths = "0.33333, 0.5, 0.66667, 1.0",
		focus_fit_method = 1,
		follow_focus = true,
		-- Match Niri: focus-follows-mouse max-scroll-amount="0%".
		-- Hover-focus only windows already fully visible, so a clipped window
		-- at the tape edge cannot pull the layout toward itself.
		follow_min_visible = 1.0,
		fullscreen_on_one_column = false,
		wrap_focus = false,
		wrap_swapcol = false,
		direction = "right",
	},
})

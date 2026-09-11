-- Quattro-style layout and gap helpers.  This lives in the
-- parent config (after DMS's generated layout) because DMS rewrites the user
-- bindings file as a flat list.  The state file is data-only and remains
-- untouched by DMS.
local quattro_state_path = "@@HOME@@/.config/hypr/quattro-state.lua"
local quattro_defaults = {
	default_layout = "scrolling",
	workspace_layouts = {},
	gaps_in = 4,
	gaps_out = 0,
}
local quattro_state = {}

local state_ok, loaded_state = pcall(dofile, quattro_state_path)
if state_ok and type(loaded_state) == "table" then
	quattro_state = loaded_state
end
for key, value in pairs(quattro_defaults) do
	if quattro_state[key] == nil then
		quattro_state[key] = value
	end
end
if quattro_state.default_layout ~= "scrolling" and quattro_state.default_layout ~= "dwindle" then
	quattro_state.default_layout = quattro_defaults.default_layout
end
if type(quattro_state.workspace_layouts) ~= "table" then
	quattro_state.workspace_layouts = {}
end
quattro_state.gaps_in = math.floor(math.max(0, tonumber(quattro_state.gaps_in) or quattro_defaults.gaps_in))
quattro_state.gaps_out = math.floor(math.max(0, tonumber(quattro_state.gaps_out) or quattro_defaults.gaps_out))

local function quattro_save_state()
	local state_file = io.open(quattro_state_path, "w")
	if not state_file then
		return
	end
	state_file:write("-- Persistent state for the Quattro-style Hyprland workflow.\nreturn {\n")
	state_file:write(string.format("\tdefault_layout = %q,\n", quattro_state.default_layout))
	state_file:write("\tworkspace_layouts = {\n")
	for workspace, layout_name in pairs(quattro_state.workspace_layouts) do
		state_file:write(string.format("\t\t[%q] = %q,\n", workspace, layout_name))
	end
	state_file:write("\t},\n")
	state_file:write(
		string.format("\tgaps_in = %d,\n\tgaps_out = %d,\n}\n", quattro_state.gaps_in, quattro_state.gaps_out)
	)
	state_file:close()
end

-- Workspaces are addressed in contiguous per-monitor ranges: with two outputs
-- and five workspaces each, 1-5 live on the first and 6-10 on the second.  The
-- ranges and the per-output orientation come from monitors.lua, which the
-- installer generates from the displays actually connected.
-- scripts/monitor-workspace derives the same ranges from the focused monitor,
-- so keep the two in sync.  Anything past the ranges (an over-swipe can create
-- workspace 11 and up) falls back to the first output's axis.
local function quattro_monitor_for_workspace(id)
	local per = QUATTRO_WORKSPACES_PER_MONITOR
	local order = QUATTRO_MONITOR_ORDER or {}
	local index = math.floor((id - 1) / per) + 1
	return order[index] or order[1]
end

-- Reapply this whenever a workspace enters scrolling so changing layouts never
-- loses the monitor-specific direction.  Portrait outputs scroll down the tape
-- rather than across it.
local function quattro_scrolling_direction(workspace)
	local monitor = quattro_monitor_for_workspace(workspace.id)
	local vertical = QUATTRO_MONITOR_VERTICAL or {}
	return (monitor and vertical[monitor]) and "down" or "right"
end

local function quattro_apply_workspace_layout(workspace, layout_name)
	if not workspace or workspace.special then
		return
	end
	local rule = { workspace = tostring(workspace.id), layout = layout_name }
	if layout_name == "scrolling" then
		rule.layout_opts = { direction = quattro_scrolling_direction(workspace) }
	end
	hl.workspace_rule(rule)
end

local function quattro_layout_for(workspace)
	return quattro_state.workspace_layouts[tostring(workspace.id)] or quattro_state.default_layout
end

-- Apply persistent values after dms/layout.lua, which makes this state
-- authoritative even if DMS restarts or regenerates that module.
hl.config({
	general = {
		layout = quattro_state.default_layout,
		gaps_in = quattro_state.gaps_in,
		gaps_out = quattro_state.gaps_out,
	},
	group = {
		groupbar = {
			enabled = true,
			render_titles = false,
			height = 2,
			indicator_height = 2,
			gaps_in = 0,
			gaps_out = 1,
			rounding = 0,
		},
	},
})
-- Pin each range to its monitor.  Hyprland merges workspace rules per selector
-- and only overwrites fields that are actually set, so the layout rules emitted
-- by quattro_apply_workspace_layout below do not clear this binding.  When an
-- output is unplugged, Hyprland falls back to whichever monitor is live.
for id = 1, QUATTRO_WORKSPACES_PER_MONITOR * math.max(1, #(QUATTRO_MONITOR_ORDER or {})) do
	hl.workspace_rule({ workspace = tostring(id), monitor = quattro_monitor_for_workspace(id) })
end

for _, workspace in ipairs(hl.get_workspaces()) do
	quattro_apply_workspace_layout(workspace, quattro_layout_for(workspace))
end

function quattro_toggle_workspace_layout()
	local workspace = hl.get_active_workspace()
	if not workspace or workspace.special then
		return
	end
	local next_layout = workspace.tiled_layout == "scrolling" and "dwindle" or "scrolling"
	local workspace_key = tostring(workspace.id)
	if next_layout == quattro_state.default_layout then
		quattro_state.workspace_layouts[workspace_key] = nil
	else
		quattro_state.workspace_layouts[workspace_key] = next_layout
	end
	quattro_apply_workspace_layout(workspace, next_layout)
	quattro_save_state()
end

function quattro_toggle_all_workspace_layouts()
	local next_layout = quattro_state.default_layout == "scrolling" and "dwindle" or "scrolling"
	quattro_state.default_layout = next_layout
	quattro_state.workspace_layouts = {}
	hl.config({ general = { layout = next_layout } })
	for _, workspace in ipairs(hl.get_workspaces()) do
		quattro_apply_workspace_layout(workspace, next_layout)
	end
	quattro_save_state()
end

function quattro_adjust_gap(which, amount)
	local state_key = which == "inner" and "gaps_in" or "gaps_out"
	quattro_state[state_key] = math.max(0, quattro_state[state_key] + amount)
	hl.config({ general = { [state_key] = quattro_state[state_key] } })
	quattro_save_state()
end

function quattro_increase_inner_gap()
	quattro_adjust_gap("inner", 1)
end

function quattro_decrease_inner_gap()
	quattro_adjust_gap("inner", -1)
end

function quattro_increase_outer_gap()
	quattro_adjust_gap("outer", 1)
end

function quattro_decrease_outer_gap()
	quattro_adjust_gap("outer", -1)
end

-- Scrolling provides its own column-aware focus command. All other layouts
-- use Hyprland's native focus dispatcher, whose directions are full words.
function quattro_focus_direction(direction)
	local workspace = hl.get_active_workspace()
	local active_window = hl.get_active_window()
	local active_address = active_window and active_window.address
	if workspace and workspace.tiled_layout == "scrolling" then
		hl.dispatch(hl.dsp.layout("focus " .. direction))
	else
		local directions = { l = "left", r = "right", u = "up", d = "down" }
		local native_direction = directions[direction]
		if native_direction then
			hl.dispatch(hl.dsp.focus({ direction = native_direction }))
		end
	end

	-- If the current layout has no window in the requested horizontal
	-- direction, carry focus to the adjacent monitor. This is deliberately
	-- independent of each monitor's layout, so scrolling and dwindle can be
	-- used side by side.  An empty workspace has no active window at all; that
	-- must also be allowed to cross to its adjacent monitor.
	local focused_window = hl.get_active_window()
	local focus_unchanged = (not active_address and not focused_window)
		or (active_address and focused_window and focused_window.address == active_address)
	if (direction == "l" or direction == "r") and focus_unchanged then
		hl.dispatch(hl.dsp.focus({ monitor = direction }))
	end
end

-- Preserve the Niri-like scrolling moves, while using Hyprland's native
-- directional move dispatcher for dwindle and other normal layouts.
function quattro_move_direction(direction)
	local workspace = hl.get_active_workspace()
	if workspace and workspace.tiled_layout == "scrolling" then
		hl.dispatch(hl.dsp.exec_cmd("@@HOME@@/.config/hypr/scripts/move-direction " .. direction))
		return
	end

	local directions = { l = "left", r = "right", u = "up", d = "down" }
	local native_direction = directions[direction]
	if native_direction then
		hl.dispatch(hl.dsp.window.move({ direction = native_direction }))
	end
end

-- Niri-style touchpad gestures, provided by Hyprgrass.  Keep these in this
-- stable parent config rather than dms/binds.lua: DMS regenerates that file.
-- Hyprgrass consumes matching gestures, so its directional three-finger binds
-- take precedence over DMS's generated three-finger workspace swipe.
-- The guard keeps Hyprland reloadable while the plugin is being installed or
-- rebuilt by hyprpm.
if hl.plugin.hyprgrass then
	local hyprgrass = hl.plugin.hyprgrass

	local function hyprgrass_swipe(fingers, direction, action)
		hyprgrass.bind({
			pattern = { kind = "swipe", fingers = fingers, direction = direction },
			action = action,
		})
	end

	for _, gesture in ipairs({
		{
			direction = "left",
			action = function()
				quattro_focus_direction("l")
			end,
		},
		{
			direction = "right",
			action = function()
				quattro_focus_direction("r")
			end,
		},
		{
			direction = "up",
			action = function()
				quattro_focus_direction("u")
			end,
		},
		{
			direction = "down",
			action = function()
				quattro_focus_direction("d")
			end,
		},
	}) do
		hyprgrass_swipe(3, gesture.direction, gesture.action)
	end

	for _, gesture in ipairs({
		{
			direction = "left",
			action = function()
				quattro_move_direction("l")
			end,
		},
		{
			direction = "right",
			action = function()
				quattro_move_direction("r")
			end,
		},
		{
			direction = "up",
			action = function()
				quattro_move_direction("u")
			end,
		},
		{
			direction = "down",
			action = function()
				quattro_move_direction("d")
			end,
		},
	}) do
		hyprgrass_swipe(4, gesture.direction, gesture.action)
	end

	hyprgrass.bind({
		pattern = { kind = "tap", fingers = 3 },
		action = hl.dsp.exec_cmd("dms ipc call hypr toggleOverview"),
	})
	hyprgrass.bind({
		pattern = { kind = "tap", fingers = 4 },
		action = quattro_toggle_workspace_layout,
	})
end

hl.on("workspace.created", function(workspace)
	quattro_apply_workspace_layout(workspace, quattro_layout_for(workspace))
end)

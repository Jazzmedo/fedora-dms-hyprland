-------------------------------------------------
-- 3 FINGERS – switch focus
-------------------------------------------------
-- Directions are deliberately inverted so the content follows the fingers:
-- dragging left pulls the window on the right into view.  quattro_focus_direction
-- is declared further down as a global, so this closure resolves it at swipe
-- time; it keeps the scrolling tape and the monitor hand-off working.
for _, gesture in ipairs({
	{ direction = "left", focus = "r" },
	{ direction = "right", focus = "l" },
	{ direction = "up", focus = "d" },
	{ direction = "down", focus = "u" },
}) do
	hl.gesture({
		fingers = 3,
		direction = gesture.direction,
		action = function()
			quattro_focus_direction(gesture.focus)
		end,
	})
end


-------------------------------------------------
-- 4 FINGERS – vertical: switch workspace, horizontal: carry the window
-------------------------------------------------
-- Hyprland's built-in workspace swipe tracks the fingers 1:1 and snaps on
-- release, so one vertical gesture covers both up and down.
hl.gesture({ fingers = 4, direction = "vertical", action = "workspace" })

-- Horizontally, take the focused window along instead. Reuse the same helper as
-- SUPER + CTRL + SHIFT + up/down: Hyprland drops a column's width when moving it
-- across workspaces, and the script measures and restores it. move_workspace is
-- assigned below this block, so spell the path out here.
for _, gesture in ipairs({
	{ direction = "left", target = "e+1" },
	{ direction = "right", target = "e-1" },
}) do
	hl.gesture({
		fingers = 4,
		direction = gesture.direction,
		action = function()
			hl.dispatch(
				hl.dsp.exec_cmd(
					"@@HOME@@/.config/hypr/scripts/move-to-workspace-preserve-width " .. gesture.target
				)
			)
		end,
	})
end

-- Custom Niri-style binds replace DMS defaults to avoid duplicate actions.
-- DMS Settings serializes binds-user.lua as a flat list and intentionally
-- drops local declarations. Keep these helpers global in the stable parent
-- config so GUI-edited bindings remain valid after every rewrite.
exec = hl.dsp.exec_cmd
focus = hl.dsp.focus
layout = hl.dsp.layout
move_workspace = "@@HOME@@/.config/hypr/scripts/move-to-workspace-preserve-width "
screenshot = "@@HOME@@/.config/hypr/scripts/dms-screenshot"
require("dms.binds-user")
-- Keep no-argument mouse dispatchers outside binds-user.lua. DMS 0.55's
-- serializer currently appends an extra parenthesis to these two actions.
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })
require("dms.windowrules")

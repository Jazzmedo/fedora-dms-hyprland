
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2, bezier = "default" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "default" })
-- Default to vertical workspace transitions for the primary monitor (workspaces
-- 1-5). The monitor-aware workspace script changes this to horizontal on DP-2.
hl.animation({ leaf = "workspaces", enabled = true, speed = 1, bezier = "default", style = "slidevert" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 2, bezier = "default" })

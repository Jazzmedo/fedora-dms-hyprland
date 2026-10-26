-- DMS Window Rules — managed by Dux Shell
-- Do not edit manually; changes may be overwritten

-- DMS-RULE: id=dms_rule_0, name=
hl.window_rule({ match = { class = "firefox$", title = "^Picture-in-Picture$" }, float = true })

-- DMS-RULE: id=dms_rule_1, name=
hl.window_rule({ match = { class = "^(org\\.wezfurlong\\.wezterm)$" }, tile = true })

-- DMS-RULE: id=dms_rule_2, name=
hl.window_rule({ match = { class = "^(gnome-control-center|pavucontrol|nm-connection-editor)$" }, tile = true })

-- DMS-RULE: id=dms_rule_3, name=
hl.window_rule({ match = { class = "^(org\\.gnome\\.Calculator|gnome-calculator|galculator|blueman-manager)$" }, float = true })

-- DMS-RULE: id=dms-floating-windows, name=DMS Floating Windows
hl.window_rule({ match = { class = "^(dev\\.duxlabs\\.shell|com\\.danklinux\\.dms)$" }, float = true })

-- DMS-RULE: id=dms-window-opaque, name=DMS Window Opaque
hl.window_rule({ match = { class = "^(dev\\.duxlabs\\.shell|com\\.danklinux\\.dms)$" }, opaque = true })

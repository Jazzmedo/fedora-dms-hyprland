#!/usr/bin/env python3
"""Rewrite the DMS settings for this machine and this component selection.

The settings.json in this repo was captured from a two-monitor laptop with a
superset of the plugins installed. Four things have to change before it is
usable anywhere else:

  * plugins the operator did not select, and the seven that are enabled in the
    captured file but have no plugin directory at all, are removed from
    plugin_settings.json and from every bar;
  * monitor names are rewritten to the output detected at install time;
  * the Nothing Clock widget's stored rectangles are recomputed for the real
    screen size, since they were absolute pixels on a 1920x1080 panel;
  * the active theme becomes nothingMatrix and the UI font becomes Ndot 57.

Environment: KEEP_PLUGINS, DEAD_PLUGINS (comma lists), OUTPUT_NAME,
SCREEN_W, SCREEN_H.
"""
import json
import os
import sys

settings_path, plugin_settings_path = sys.argv[1], sys.argv[2]

keep = {p for p in os.environ.get("KEEP_PLUGINS", "").split(",") if p}
dead = {p for p in os.environ.get("DEAD_PLUGINS", "").split(",") if p}
output = os.environ.get("OUTPUT_NAME") or "eDP-1"
screen_w = int(os.environ.get("SCREEN_W") or 1920)
screen_h = int(os.environ.get("SCREEN_H") or 1080)

home = os.path.expanduser("~")


def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save(path, data):
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def widget_id(entry):
    return entry if isinstance(entry, str) else entry.get("id", "")


def prune_bar(widgets):
    """Drop dead plugins outright; disable unselected ones rather than delete,
    so re-running with a wider selection restores them in place."""
    out = []
    for entry in widgets or []:
        wid = widget_id(entry)
        if wid in dead:
            continue
        if wid in plugin_ids and wid not in keep:
            continue
        out.append(entry)
    return out


settings = load(settings_path)
plugin_settings = load(plugin_settings_path)

# --- plugins -----------------------------------------------------------------
# Every id that is a plugin rather than a built-in widget.
plugin_ids = set(plugin_settings.keys()) | dead | keep

for pid in list(plugin_settings.keys()):
    if pid in dead or pid not in keep:
        plugin_settings.pop(pid, None)
for pid in keep:
    entry = plugin_settings.setdefault(pid, {})
    if isinstance(entry, dict):
        entry.setdefault("enabled", True)
        entry["enabled"] = True

# dmsThemeSync drives the GTK/Qt/app recolouring; Fusion is the Qt style that
# actually honours the generated palette.
if "dmsThemeSync" in plugin_settings and isinstance(plugin_settings["dmsThemeSync"], dict):
    plugin_settings["dmsThemeSync"].setdefault("qtStyle", "Fusion")

# --- bars --------------------------------------------------------------------
for bar in settings.get("barConfigs", []) or []:
    for side in ("leftWidgets", "centerWidgets", "rightWidgets"):
        if side in bar:
            bar[side] = prune_bar(bar[side])
    # Bars were pinned to the captured machine's outputs.
    if bar.get("monitors"):
        bar["monitors"] = [output]

# --- theme and fonts ---------------------------------------------------------
settings["currentThemeName"] = "custom"
settings["customThemeFile"] = f"{home}/.config/DankMaterialShell/themes/nothingMatrix/theme.json"
settings["fontFamily"] = "Ndot 57"
settings["monoFontFamily"] = "JetBrainsMono Nerd Font Mono"
settings["matugenTargetMonitor"] = output
settings["desktopClockEnabled"] = False      # the Nothing Clock replaces it

# --- the Nothing Clock -------------------------------------------------------
CAPTURED_W, CAPTURED_H = 1920.0, 1080.0
widgets = settings.get("desktopWidgetInstances") or []
clock = next((w for w in widgets if w.get("widgetType") == "nothingClock"), None)

if clock is None:
    clock = {
        "id": "dw_fedora_nothing_clock",
        "widgetType": "nothingClock",
        "name": "Nothing Clock",
        "enabled": True,
        "config": {},
        "positions": {},
    }
    widgets.append(clock)

clock["enabled"] = True
cfg = clock.setdefault("config", {})
cfg.update({
    "style": "digital",
    "timeFormat": "12",
    "backgroundOpacity": 0,
    "accentColorSource": "primary",
    "clickThrough": False,
    "displayPreferences": ["all"],
    # Nothing red, #D71921.
    "accentCustomColor": {
        "r": 0.843137264251709, "g": 0.09803921729326248,
        "b": 0.12945754826068878, "a": 1,
        "hsvHue": 0.992972195148468, "hsvSaturation": 0.8837262392044067,
        "hsvValue": 0.843137264251709, "hslHue": 0.992972195148468,
        "hslSaturation": 0.7916685938835144, "hslLightness": 0.47058823704719543,
        "valid": True,
    },
})

# Scale the captured rectangle to this panel, then centre it horizontally and
# sit it in the upper third, which is where it was on the original display.
scale = min(screen_w / CAPTURED_W, screen_h / CAPTURED_H)
w = round(745.41 * scale, 2)
h = round(441.90 * scale, 2)
clock["positions"] = {
    output: {
        "width": w,
        "height": h,
        "x": round((screen_w - w) / 2, 2),
        "y": round(screen_h * 0.06, 2),
    }
}

settings["desktopWidgetInstances"] = widgets

save(settings_path, settings)
save(plugin_settings_path, plugin_settings)

print(f"settings: theme=nothingMatrix font='Ndot 57' output={output} "
      f"clock={w}x{h} plugins={len(plugin_settings)}")

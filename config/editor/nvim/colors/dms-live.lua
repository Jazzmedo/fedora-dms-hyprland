local ok, base46 = pcall(require, "base46")
if not ok or not base46._DMS_SUPPORT then
  vim.notify("AvengeMedia/base46 with DMS support is required", vim.log.levels.ERROR)
  return
end

local cache_home = vim.env.XDG_CACHE_HOME
if not cache_home or cache_home == "" then
  cache_home = vim.fs.joinpath(vim.env.HOME, ".cache")
end

local palette_path = vim.fs.joinpath(cache_home, "DankMaterialShell", "dms-colors.json")

local function read_palette()
  local file = assert(io.open(palette_path, "r"), "cannot read " .. palette_path)
  local palette = vim.json.decode(file:read("*a"))
  file:close()
  return palette
end

local mode_result = vim.system({ "dms", "ipc", "call", "theme", "getMode" }, { text = true }):wait()
local mode = mode_result.stdout and mode_result.stdout:match("light") and "light" or "dark"
vim.o.background = mode

local palette = read_palette()
local c = assert(palette.colors[mode], "DMS palette has no " .. mode .. " colors")
local d = assert(palette.dank16, "DMS palette has no dank16 colors")
local function ansi(index)
  local color = assert(d["color" .. index], "missing dank16 color" .. index)
  return color[mode] or color.default
end

local theme_name = "dms-live"
base46.theme_tables[theme_name] = {
  type = mode,
  base_30 = {
    white = c.on_surface,
    black = c.background,
    darker_black = c.surface_container_lowest,
    black2 = c.surface_container,
    one_bg = c.surface_container_high,
    one_bg2 = c.surface_container_highest,
    one_bg3 = c.surface_variant,
    grey = ansi(8),
    grey_fg = c.on_surface_variant,
    grey_fg2 = c.outline,
    light_grey = ansi(7),
    red = ansi(1),
    baby_pink = ansi(9),
    pink = ansi(13),
    line = c.outline_variant,
    green = ansi(2),
    vibrant_green = ansi(10),
    nord_blue = c.primary,
    blue = ansi(4),
    yellow = ansi(3),
    sun = ansi(11),
    purple = ansi(5),
    dark_purple = ansi(13),
    teal = ansi(6),
    orange = ansi(9),
    cyan = ansi(14),
    statusline_bg = c.surface_container_high,
    lightbg = c.surface_container_highest,
    pmenu_bg = c.primary,
    folder_bg = c.primary,
  },
  base_16 = {
    base00 = c.background,
    base01 = c.surface_container,
    base02 = c.surface_container_high,
    base03 = c.surface_container_highest,
    base04 = c.on_surface_variant,
    base05 = c.on_surface,
    base06 = ansi(7),
    base07 = ansi(15),
    base08 = ansi(1),
    base09 = ansi(9),
    base0A = ansi(3),
    base0B = ansi(2),
    base0C = ansi(6),
    base0D = ansi(4),
    base0E = ansi(13),
    base0F = ansi(5),
  },
}

base46.load(theme_name)
vim.g.colors_name = theme_name

if not _G._dms_live_theme_watcher then
  local uv = vim.uv or vim.loop
  local watcher = uv.new_fs_event()
  local timer = uv.new_timer()
  _G._dms_live_theme_watcher = { watcher = watcher, timer = timer }

  local function watch()
    watcher:stop()
    watcher:start(palette_path, {}, function()
      timer:stop()
      timer:start(150, 0, vim.schedule_wrap(function()
        if vim.g.colors_name == theme_name then
          base46.theme_tables[theme_name] = nil
          vim.cmd.colorscheme(theme_name)
        end
        watch()
      end))
    end)
  end
  watch()
end


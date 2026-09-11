# hint(): a printed cheat sheet for everything defined in these fragments.

hint() { # Displays a colorful, organized guide for all custom aliases and functions
  local P='%F{cyan}'    # Primary color (Headers)
  local S='%F{yellow}'  # Secondary color (Examples)
  local A='%F{magenta}' # Alias/Function name
  local R='%f'          # Reset

  print -P "\n${P}━━━━━━━━━━━━━━━━━━━━━━ 💡 TERMINAL HINTS ━━━━━━━━━━━━━━━━━━━━━━${R}"

  # 1. Package & System Management
  print -P "\n${P}[ PACKAGE & SYSTEM ]${R}"
  print -P "  ${A}dnfi${R}      : Search & install dnf pkgs    "
  print -P "  ${A}fp${R}        : Search & install Flatpaks    "
  print -P "  ${A}prg${R}       : Interactive purge (Any)      "
  print -P "  ${A}updt${R}      : Full dnf system upgrade     "
  print -P "  ${A}rpmi${R}     : Install a local .rpm          | ${S}Example:${R} rpmi file.rpm"
  print -P "  ${A}cln${R}       : Clear system RAM cache       "
  print -P "  ${A}apprfrsh${R}  : Refresh KDE config cache     "
  print -P "  ${A}orgd${R}      : Organize the Downloads       "
  print -P "  ${A}rr${R}        : Alais for ranger             "

   # 2. Cybersecurity & Docker Labs
  print -P "\n${P}[ CYBERSECURITY & LABS ]${R}"
  print -P "  ${A}dbe${R}       : Enable Kali Lab Bridge       "
  print -P "  ${A}dbd${R}       : Disable Kali Lab Bridge      "
  print -P "  ${A}dstop${R}     : Kill all Docker containers   "
  print -P "  ${A}thm${R}       : Run TryHackMe VPN script     "
  print -P "  ${A}wrp${R}       : Reset Cloudflare WARP        "

  # 3. Development & Workflow
  print -P "\n${P}[ DEVELOPMENT & WORKFLOW ]${R}"
  print -P "  ${A}lazyp${R}     : Git add/commit/push          | ${S}Example:${R} lazyp 'fix'"
  print -P "  ${A}lazyc${R}     : Git add/commit only          | ${S}Example:${R} lazyc 'wip'"
  print -P "  ${A}fetch${R}     : Git fetch & pull main        "
  print -P "  ${A}installfonts${R}: Install fonts from ~/fonts "
  print -P "  ${A}zconfig${R}    : Edit .zshrc in nvim         "
  print -P "  ${A}dev${R}    : Open tmux development env   "

  # 4. Utilities & Aesthetics
  print -P "\n${P}[ UTILITIES & LOOKS ]${R}"
  print -P "  ${A}pray${R}      : Prayer times (Pretty)        "
  print -P "  ${A}cls${R}       : Clear + Fastfetch            "
  print -P "  ${A}cat${R} / ${A}grep${R}  : Uses ${S}batcat${R} / ${S}ripgrep${R}"
  print -P "  ${A}ls${R} / ${A}ll${R}    : Uses ${S}eza${R} (Icons/Grouped)"
  print -P "  ${A}htop${R}      : Uses ${S}btop${R}"
  print -P "  ${A}rm${R}        : Uses ${S}trash-put${R} (Safe)"
  print -P "  ${A}vim${R}       : Uses ${S}Neovim${R}"

  print -P "\n${P}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
}

alias hnt='hint'


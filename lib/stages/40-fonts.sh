# shellcheck shell=bash
# Nothing's typefaces, a Nerd Font for the terminal, and the fontconfig rules
# that make Ndot 57 the system sans without wrecking monospace metrics.

NERD_FONT_VERSION="3.4.0"

stage_fonts() {
  step "Fonts"

  local dest=/usr/share/fonts/nothing
  if [[ -f $dest/Ndot57-Regular.otf ]]; then
    skip "Nothing fonts already installed"
  else
    as_root mkdir -p "$dest"
    as_root cp "$REPO_DIR"/assets/fonts/nothing/*.otf "$dest/"
    ok "Nothing fonts installed (Ndot 55/57, NType 82)"
  fi

  local nerd=/usr/share/fonts/jetbrains-nerd
  if [[ -d $nerd && -n $(ls -A "$nerd" 2>/dev/null) ]]; then
    skip "JetBrainsMono Nerd Font already installed"
  else
    local tmp; tmp=$(mktemp -d)
    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONT_VERSION}/JetBrainsMono.tar.xz"
    if retry 3 curl -fL --progress-bar -o "$tmp/jb.tar.xz" "$url"; then
      as_root mkdir -p "$nerd"
      run tar -xf "$tmp/jb.tar.xz" -C "$tmp"
      as_root bash -c "cp '$tmp'/*.ttf '$nerd'/"
      ok "JetBrainsMono Nerd Font installed"
    else
      soft_fail "could not download JetBrainsMono Nerd Font; terminals will fall back"
    fi
    rm -rf "$tmp"
  fi

  # Ndot is a dot-matrix display face with no monospace metrics. It becomes the
  # sans-serif default; monospace stays on the Nerd Font so terminals, Neovim
  # and code remain aligned and legible.
  local conf=/etc/fonts/local.conf
  if [[ -f $conf ]] && grep -q "Ndot 57" "$conf"; then
    skip "fontconfig defaults already set"
  else
    as_root tee "$conf" >/dev/null <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Written by fedora-nothing. Ndot 57 is the UI face; it has no monospace
       metrics, so sans and monospace are deliberately different families. -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Ndot 57</family>
      <family>Noto Sans</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font Mono</family>
      <family>Noto Sans Mono</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
  <alias>
    <family>system-ui</family>
    <prefer><family>Ndot 57</family></prefer>
  </alias>
</fontconfig>
XML
    ok "fontconfig: sans → Ndot 57, monospace → JetBrainsMono Nerd Font Mono"
  fi

  as_root fc-cache -f >/dev/null
  ok "font cache rebuilt"

  # Cursor and icon themes referenced by the DMS settings and by Dolphin.
  local icons="$HOME/.local/share/icons"
  run mkdir -p "$icons"
  if [[ -d $icons/Afterglow-cursors ]]; then
    skip "Afterglow cursors present"
  else
    run tar -xf "$REPO_DIR/assets/icons/Afterglow-cursors.tar.zst" -C "$icons"
    ok "Afterglow cursor theme installed"
  fi
  if [[ -d "$icons/Cawnonical Mono-Glyph Icon Suite (White)" ]]; then
    skip "Cawnonical icon theme present"
  else
    run tar -xf "$REPO_DIR/assets/icons/cawnonical-mono-glyph-white.tar.zst" -C "$icons"
    ok "Cawnonical icon theme installed"
  fi
}

# shellcheck shell=bash
# Nothing's typefaces, a Nerd Font for the terminal, an Arabic pair, and the
# fontconfig rules that make Ndot 57 the system sans without wrecking monospace
# metrics or the shaping of scripts Ndot does not cover.

NERD_FONT_VERSION="3.4.0"

stage_fonts() {

  local dest=/usr/share/fonts/nothing
  if [[ -f $dest/Ndot57-Regular.otf ]]; then
    skip "The Nothing typefaces are already installed"
  else
    as_root mkdir -p "$dest"
    as_root cp "$REPO_DIR"/assets/fonts/nothing/*.otf "$dest/"
    record file "$dest"
    ok "Installed the Nothing typefaces: Ndot 55, Ndot 57 and NType 82"
  fi

  local nerd=/usr/share/fonts/jetbrains-nerd
  if [[ -d $nerd && -n $(ls -A "$nerd" 2>/dev/null) ]]; then
    skip "The terminal typeface is already installed"
  else
    local tmp; tmp=$(mktemp -d)
    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONT_VERSION}/JetBrainsMono.tar.xz"
    if retry 3 curl -fL --progress-bar -o "$tmp/jb.tar.xz" "$url"; then
      as_root mkdir -p "$nerd"
      run tar -xf "$tmp/jb.tar.xz" -C "$tmp"
      as_root bash -c "cp '$tmp'/*.ttf '$nerd'/"
      record file "$nerd"
      ok "Installed JetBrains Mono, the typeface the terminal and editor use"
    else
      soft_fail "Could not download the terminal typeface" \
                  "The download from GitHub failed. Your terminal will use a plainer font." \
                  "./install.sh --only=fonts"
    fi
    clean_tmp "$tmp"
  fi

  # Ndot covers no Arabic, so Arabic falls back. Kawkab Mono is the monospaced
  # face the terminal needs and Fedora does not package it; IBM Plex Sans
  # Arabic, the proportional face for everything else, comes from the package
  # list. Both are SIL OFL.
  local arabic=/usr/share/fonts/kawkab-mono
  if [[ -f $arabic/KawkabMono-Regular.ttf ]]; then
    skip "The Arabic terminal typeface is already installed"
  else
    as_root mkdir -p "$arabic"
    as_root cp "$REPO_DIR"/assets/fonts/arabic/KawkabMono-*.ttf "$arabic/"
    as_root cp "$REPO_DIR/assets/fonts/arabic/OFL.txt" "$arabic/"
    record file "$arabic"
    ok "Installed Kawkab Mono, the monospaced Arabic typeface"
  fi

  # Ndot is a dot-matrix display face with no monospace metrics. It becomes the
  # sans-serif default; monospace stays on the Nerd Font so terminals, Neovim
  # and code remain aligned and legible.
  local conf=/etc/fonts/local.conf
  if [[ -f $conf ]] && grep -q "Kawkab Mono" "$conf"; then
    skip "The system fonts are already set"
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

  <!-- Arabic, split by context. Ndot and JetBrains Mono have no Arabic glyphs,
       so it always falls back. The terminal wants a monospaced Arabic face so
       Arabic lines up with the Latin grid; everywhere else, above all the
       shell UI, wants a proportional one. Forcing one advance width on Arabic
       spaces the letters evenly and the script stops looking joined.

       Setting this here rather than in a terminal's own per-codepoint font map
       matters: pinning a font per codepoint splits the line into one character
       shaping runs and disables contextual shaping, so Arabic renders in
       isolated form and words come out disconnected. A fontconfig fallback
       keeps the normal shaping path intact.

       Note: XML comments may not contain a double hyphen. -->
  <match target="pattern">
    <test name="family" compare="contains"><string>JetBrainsMono Nerd Font</string></test>
    <edit name="family" mode="append" binding="strong">
      <string>Kawkab Mono</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="lang" compare="contains"><string>ar</string></test>
    <test name="spacing" compare="eq"><const>mono</const></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Kawkab Mono</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="family"><string>monospace</string></test>
    <test name="lang" compare="contains"><string>ar</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Kawkab Mono</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="lang" compare="contains"><string>ar</string></test>
    <edit name="family" mode="prepend" binding="weak">
      <string>IBM Plex Sans Arabic</string>
    </edit>
  </match>
</fontconfig>
XML
    record file "$conf"
    ok "Set Ndot 57 as the system font, JetBrains Mono for code, and the Arabic faces"
  fi

  as_root fc-cache -f >/dev/null
  ok "Told the system about the new fonts"

  # Cursor and icon themes referenced by the DMS settings and by Dolphin.
  local icons="$HOME/.local/share/icons"
  run mkdir -p "$icons"
  if [[ -d $icons/Afterglow-cursors ]]; then
    skip "The mouse cursor theme is already installed"
  else
    run tar -xf "$REPO_DIR/assets/icons/Afterglow-cursors.tar.zst" -C "$icons"
    record file "$icons/Afterglow-cursors"
    ok "Installed the Afterglow mouse cursors"
  fi
  if [[ -d "$icons/Cawnonical Mono-Glyph Icon Suite (White)" ]]; then
    skip "The icon set is already installed"
  else
    run tar -xf "$REPO_DIR/assets/icons/cawnonical-mono-glyph-white.tar.zst" -C "$icons"
    record file "$icons/Cawnonical Mono-Glyph Icon Suite (White)"
    ok "Installed the Cawnonical icon set"
  fi
}

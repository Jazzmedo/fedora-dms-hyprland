#!/usr/bin/env bash
# Collect what went wrong into one pasteable file.
#
#   ./report.sh              write the report and print where it went
#   ./report.sh -            write it to stdout instead
#
# Home paths, hostnames and anything token-shaped are redacted, so the output
# is safe to paste into a chat or an issue.

set -uo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$REPO_DIR/lib/common.sh"

LOG_DIR="$HOME/.cache/fedora-nothing"
OUT=${1:-"$LOG_DIR/report-$(date +%Y%m%d-%H%M%S).txt"}

latest_log=$(ls -1t "$LOG_DIR"/install-*.log 2>/dev/null | head -1)

redact() {
  sed -E \
    -e "s|$HOME|~|g" \
    -e "s/\b$USER\b/USER/g" \
    -e "s/\b$(hostname)\b/HOST/g" \
    -e 's/([A-Za-z0-9_-]*(token|secret|key|passwd|password)[A-Za-z0-9_-]*[[:space:]]*[=:][[:space:]]*"?)[^[:space:]",]+/\1REDACTED/gI' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/EMAIL/g'
}

generate() {
  echo "fedora-nothing report — $(date -Is)"
  echo "==================================================================="

  echo
  echo "## System"
  ( . /etc/os-release 2>/dev/null; echo "os        ${PRETTY_NAME:-unknown}" )
  echo "kernel    $(uname -r)"
  echo "arch      $(rpm -E %_arch 2>/dev/null)"
  echo "virt      $(systemd-detect-virt 2>/dev/null | head -1 || true)"
  echo "gpu       $(lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller' | sed 's/^[^ ]* //' | paste -sd'; ' -)"
  echo "session   ${XDG_CURRENT_DESKTOP:-none} / ${XDG_SESSION_TYPE:-none}"

  echo
  echo "## Selection"
  if [[ -f $HOME/.config/fedora-nothing/selection.conf ]]; then
    sed 's/^/  /' "$HOME/.config/fedora-nothing/selection.conf"
  else
    echo "  (no selection.conf; the installer has not completed a run)"
  fi

  echo
  echo "## Repositories"
  dnf repolist 2>/dev/null | sed 's/^/  /' | head -30

  echo
  echo "## Key packages"
  local p
  for p in hyprland quickshell matugen sddm kitty dolphin cliphist grim slurp \
           hyprlock hyprpicker pipewire pavucontrol zsh neovim; do
    printf '  %-24s %s\n' "$p" "$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$p" 2>/dev/null || echo 'NOT INSTALLED')"
  done
  printf '  %-24s %s\n' "dms" "$(command -v dms >/dev/null && dms --version 2>/dev/null | head -1 || echo 'NOT INSTALLED')"
  printf '  %-24s %s\n' "zen" "$( [[ -x /opt/zen/zen ]] && echo /opt/zen/zen || echo 'NOT INSTALLED')"

  echo
  echo "## DMS plugins on disk"
  if [[ -d $HOME/.config/DankMaterialShell/plugins ]]; then
    ( cd "$HOME/.config/DankMaterialShell/plugins" && \
      for d in */; do
        [[ -d $d ]] || continue
        printf '  %-24s %s\n' "${d%/}" "$(readlink "${d%/}" || echo 'real dir')"
      done )
  else
    echo "  (none)"
  fi

  echo
  echo "## systemd user units"
  systemctl --user list-units --all --no-legend --no-pager \
    'dms*' 'hypr*' 'Universal-Mpris*' 2>/dev/null | sed 's/^/  /' || echo "  (no user bus)"
  echo "  --- failed:"
  systemctl --user --failed --no-legend --no-pager 2>/dev/null | sed 's/^/  /' || true

  echo
  echo "## Installer log: ${latest_log:-none found}"
  if [[ -n $latest_log ]]; then
    echo "  --- warnings and failures"
    grep -E ' (WARN|FATAL) ' "$latest_log" | sed 's/^/  /' || echo "  (none)"
    echo
    echo "  --- dnf and download errors"
    grep -inE 'error|failed|cannot|no match|unable|timed out|404|conflict' "$latest_log" \
      | grep -viE 'skip-unavailable|error_|errors=0' | tail -60 | sed 's/^/  /' || echo "  (none)"
    echo
    echo "  --- last 40 lines"
    tail -40 "$latest_log" | sed 's/^/  /'
  fi

  echo
  echo "## Hyprland"
  if [[ -f $HOME/.config/hypr/monitors.env ]]; then
    sed 's/^/  /' "$HOME/.config/hypr/monitors.env"
  fi
  [[ -f $HOME/.config/hypr/dms/outputs.lua ]] && grep -h '^hl.monitor' "$HOME/.config/hypr/dms/outputs.lua" | sed 's/^/  /'
  if command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    echo "  --- runtime errors"
    hyprctl rollinglog 2>/dev/null | grep -iE 'err|fail' | tail -20 | sed 's/^/  /'
  fi

  echo
  echo "==================================================================="
  echo "end of report"
}

if [[ $OUT == - ]]; then
  generate | redact
else
  mkdir -p "$(dirname "$OUT")"
  generate | redact > "$OUT"
  step "Report written"
  info "$OUT"
  info "size: $(wc -l < "$OUT") lines"
  echo
  echo "  Send it with:  cat '$OUT'"
fi

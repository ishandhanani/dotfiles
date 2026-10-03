#!/usr/bin/env bash
# home-manager/scripts/install-mac-apps.sh
#
# Opt-in bootstrap for common macOS GUI apps previously declared as nix-darwin casks.
# Apps: Dia, iTerm2, Raycast, Rectangle, Cursor.
#
# Usage: ./install-mac-apps.sh [options]
#   -h, --help              Show this help and exit
#   -n, --dry-run           Print what would be done without installing
#   -l, --list              List tracked apps and their install status
#       --install-homebrew  Install Homebrew if it is missing

set -euo pipefail

NAMES=("Dia" "iTerm2" "Raycast" "Rectangle" "Cursor")
TOKENS=("thebrowsercompany-dia" "iterm2" "raycast" "rectangle" "cursor")
BUNDLES=("Dia.app" "iTerm.app" "Raycast.app" "Rectangle.app" "Cursor.app")

info()  { printf '\033[1;34m=> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m   %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
error() { printf '\033[0;31m!! %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./install-mac-apps.sh [options]
  -h, --help              Show this help and exit
  -n, --dry-run           Print what would be done without installing
  -l, --list              List tracked apps and their install status
      --install-homebrew  Install Homebrew if it is missing
EOF
}

DRY_RUN=0
LIST=0
INSTALL_HOMEBREW=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -l|--list)
      LIST=1
      shift
      ;;
    --install-homebrew)
      INSTALL_HOMEBREW=1
      shift
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$OSTYPE" != darwin* ]]; then
  error "This script is intended for macOS only (found OSTYPE=$OSTYPE)"
  exit 1
fi

app_exists() {
  local bundle="$1"
  [[ -d "/Applications/${bundle}" ]] || [[ -d "$HOME/Applications/${bundle}" ]]
}

list_apps() {
  local i name token bundle status
  printf '%-12s %-28s %-18s %s\n' "Name" "Cask" "Bundle" "Status"
  for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    token="${TOKENS[$i]}"
    bundle="${BUNDLES[$i]}"
    if app_exists "$bundle"; then
      status="installed"
    else
      status="missing"
    fi
    printf '%-12s %-28s %-18s %s\n' "$name" "$token" "$bundle" "$status"
  done
}

if [[ "$LIST" == 1 ]]; then
  list_apps
  exit 0
fi

find_brew() {
  local p
  local found
  found=$(type -P brew 2>/dev/null || true)
  if [[ -n "$found" && -x "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.homebrew/bin/brew"; do
    if [[ -x "$p" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

ensure_brew() {
  local install_script

  if BREW_BIN=$(find_brew); then
    ok "Homebrew found: $BREW_BIN"
    return 0
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    if [[ "$INSTALL_HOMEBREW" == 1 ]]; then
      info "Would install Homebrew"
    else
      warn "Homebrew is not installed; pass --install-homebrew to install it"
    fi
    BREW_BIN="brew"
    return 0
  fi

  if [[ "$INSTALL_HOMEBREW" == 1 ]]; then
    info "Installing Homebrew..."
    install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
    NONINTERACTIVE=1 /bin/bash -c "$install_script"
    if ! BREW_BIN=$(find_brew); then
      error "Homebrew was installed but could not be found on PATH."
      error "Add it to your shell PATH and rerun this script."
      exit 1
    fi
    ok "Homebrew installed: $BREW_BIN"
    return 0
  fi

  error "Homebrew is required but not installed."
  error "Install it from https://brew.sh, then rerun this script."
  error "Alternatively, rerun with --install-homebrew."
  exit 1
}

ensure_brew

MISSING=0
for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  token="${TOKENS[$i]}"
  bundle="${BUNDLES[$i]}"

  if app_exists "$bundle"; then
    ok "$name already present ($bundle)"
    continue
  fi

  MISSING=1

  if [[ "$DRY_RUN" == 1 ]]; then
    info "Would install $name (brew install --cask $token)"
    continue
  fi

  info "Installing $name (brew install --cask $token)..."
  "$BREW_BIN" install --cask "$token"
  ok "$name installed"
done

if [[ "$DRY_RUN" == 1 && "$MISSING" == 0 ]]; then
  ok "Dry run: nothing to install"
fi

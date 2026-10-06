#!/usr/bin/env bash

set -euo pipefail

INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
INTERACTIVE=0

info() { printf '\033[1;34m=> %s\033[0m\n' "$*" >&2; }
ok() { printf '\033[1;32m   %s\033[0m\n' "$*" >&2; }
error() { printf '\033[0;31m!! %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: install-homebrew.sh [options]

Options:
  -h, --help       Show this help and exit
      --interactive
                   Let Homebrew ask for confirmation before installing

By default this sets NONINTERACTIVE=1 for the official Homebrew installer, so
the only expected prompt is sudo asking for your password.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --interactive)
      INTERACTIVE=1
      shift
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  error "Homebrew bootstrap is intended for macOS only"
  exit 1
fi

default_brew_path() {
  case "$(uname -m)" in
    arm64) printf '/opt/homebrew/bin/brew\n' ;;
    *) printf '/usr/local/bin/brew\n' ;;
  esac
}

brew_path="$(command -v brew || true)"
if [[ -z "$brew_path" && -x "$(default_brew_path)" ]]; then
  brew_path="$(default_brew_path)"
fi

if [[ -n "$brew_path" ]]; then
  ok "Homebrew already installed at ${brew_path}"
  "$brew_path" --version
  exit 0
fi

info "Installing Homebrew with the official installer"
info "Installer source: ${INSTALL_URL}"

if ! id -Gn | tr ' ' '\n' | grep -qx admin; then
  error "Homebrew needs an administrator account, but $(whoami) is not in the admin group"
  exit 1
fi

info "Checking sudo access before running Homebrew"
if ! sudo -v; then
  error "sudo authentication failed; Homebrew cannot install without admin access"
  exit 1
fi

install_script="$(curl -fsSL "$INSTALL_URL")"
if [[ "$INTERACTIVE" -eq 1 ]]; then
  /bin/bash -c "$install_script"
else
  NONINTERACTIVE=1 /bin/bash -c "$install_script"
fi

brew_path="$(command -v brew || true)"
if [[ -z "$brew_path" && -x "$(default_brew_path)" ]]; then
  brew_path="$(default_brew_path)"
fi

if [[ -z "$brew_path" ]]; then
  error "Homebrew installer finished, but brew is not on PATH"
  info "Try: eval \"\$($(default_brew_path) shellenv)\""
  exit 1
fi

ok "Homebrew installed at ${brew_path}"
"$brew_path" --version
info "For the current shell, run: eval \"\$(${brew_path} shellenv)\""

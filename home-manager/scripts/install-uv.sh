#!/usr/bin/env bash

set -euo pipefail

INSTALL_URL="https://astral.sh/uv/install.sh"

info() { printf '\033[1;34m=> %s\033[0m\n' "$*" >&2; }
ok() { printf '\033[1;32m   %s\033[0m\n' "$*" >&2; }
error() { printf '\033[0;31m!! %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: install-uv.sh [options]

Options:
  -h, --help       Show this help and exit

Installs uv with Astral's official standalone installer when uv is not already
available on PATH.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

if command -v uv >/dev/null 2>&1; then
  ok "uv already installed: $(command -v uv)"
  uv --version
  exit 0
fi

info "Installing uv with Astral's official installer"
curl -LsSf "$INSTALL_URL" | sh

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

if ! command -v uv >/dev/null 2>&1; then
  error "uv installer completed, but uv is still not on PATH"
  exit 1
fi

ok "uv installed: $(command -v uv)"
uv --version

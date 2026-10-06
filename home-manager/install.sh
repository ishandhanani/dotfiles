#!/usr/bin/env bash
set -euo pipefail

if command -v nix >/dev/null 2>&1; then
  printf 'Nix is already installed.\n'
  exit 0
fi
if [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
  printf 'Nix is installed; restart your terminal to load its PATH.\n'
  exit 0
fi

curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
printf 'Restart your terminal, then run make setup-macos (Mac only) and make apply.\n'

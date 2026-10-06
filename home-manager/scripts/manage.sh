#!/usr/bin/env bash
set -euo pipefail

config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$config_dir"
DOTFILES_USER="$(id -un)"
DOTFILES_HOME="$HOME"
DOTFILES_ROOT="$(cd .. && pwd)"
export DOTFILES_USER DOTFILES_HOME DOTFILES_ROOT

if [[ "$DOTFILES_USER" == root ]]; then
  printf 'Run make as your normal user; setup-macos requests sudo only for system activation.\n' >&2
  exit 1
fi
if ! command -v nix >/dev/null 2>&1; then
  printf 'Nix is missing from PATH. Run make install, then restart your terminal.\n' >&2
  exit 1
fi

case "${1:-}" in
  apply)
    generation="$(nix build --impure --no-write-lock-file --no-link --print-out-paths '.#homeConfigurations.default.activationPackage')"
    HOME_MANAGER_BACKUP_EXT=backup "$generation/activate"
    ;;
  setup-macos)
    if [[ "$(uname -s)" != Darwin ]]; then
      printf 'setup-macos is only available on macOS. Use make apply on Linux.\n' >&2
      exit 1
    fi
    system_path="$(nix build --impure --no-write-lock-file --no-link --print-out-paths '.#darwinConfigurations.macos.system')"
    # Build as the login user, then register and activate that exact system as root.
    sudo "$(command -v nix-env)" --profile /nix/var/nix/profiles/system --set "$system_path"
    sudo "$system_path/sw/bin/darwin-rebuild" activate
    ./scripts/install-mac-apps.sh
    ;;
  check)
    for script in install.sh scripts/*.sh; do bash -n "$script"; done
    targets=('.#homeConfigurations.default.activationPackage')
    if [[ "$(uname -s)" == Darwin ]]; then
      targets+=('.#darwinConfigurations.macos.system')
    fi
    nix build --impure --no-write-lock-file --no-link "${targets[@]}"
    ;;
  *)
    printf 'Usage: %s {apply|setup-macos|check}\n' "$0" >&2
    exit 1
    ;;
esac

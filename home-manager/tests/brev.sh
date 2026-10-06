#!/usr/bin/env bash
# Exercise the real Brev package and Home Manager migration in a disposable home.
# Nix, rather than Bash, expands the interpolations in the expressions below.
# shellcheck disable=SC2016
set -euo pipefail
BREV_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case_dir="$(mktemp -d)"
cleanup() {
  local result=$?
  if [[ "$result" != 0 ]]; then cat "$case_dir"/*.log >&2 2>/dev/null || true; fi
  rm -rf "$case_dir"
  exit "$result"
}
trap cleanup EXIT
BREV_TEST_HOME="$case_dir/home"
export BREV_TEST_ROOT BREV_TEST_HOME
mkdir -p "$BREV_TEST_HOME/.local/bin" "$BREV_TEST_HOME/.local/state/nix/profiles"
nix_bin_dir="$(dirname "$(command -v nix)")"

generation="$(nix build --impure --no-link --print-out-paths --expr '
  let
    root = builtins.getEnv "BREV_TEST_ROOT";
    flake = builtins.getFlake (root + "/home-manager");
    pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  in (flake.inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs.brevSource = flake.inputs.brev-cli;
    modules = [
      (builtins.toPath (root + "/home-manager/modules/clis.nix"))
      ({ lib, ... }: {
        home.username = "brev-package-test";
        home.homeDirectory = builtins.getEnv "BREV_TEST_HOME";
        home.stateVersion = "24.05";
        # Test file activation without modifying any package profile.
        home.activation.installPackages = lib.mkForce "";
      })
    ];
  }).activationPackage
')"

in_test_home() {
  env -i \
    HOME="$BREV_TEST_HOME" USER=brev-package-test \
    PATH="$nix_bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
    XDG_CONFIG_HOME="$BREV_TEST_HOME/.config" \
    XDG_DATA_HOME="$BREV_TEST_HOME/.local/share" \
    XDG_STATE_HOME="$BREV_TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$BREV_TEST_HOME/.cache" \
    NIX_PROFILE="$BREV_TEST_HOME/.local/state/nix/profiles/default" \
    HOME_MANAGER_BACKUP_EXT=backup "$@"
}

printf 'previous Brev binary\n' > "$BREV_TEST_HOME/.local/bin/brev"
cp "$BREV_TEST_HOME/.local/bin/brev" "$case_dir/original"

in_test_home DRY_RUN=1 "$generation/activate" --driver-version 1 > "$case_dir/dry-run.log" 2>&1
cmp "$case_dir/original" "$BREV_TEST_HOME/.local/bin/brev"
test ! -e "$BREV_TEST_HOME/.local/bin/brev.backup"

in_test_home "$generation/activate" --driver-version 1 > "$case_dir/activate.log" 2>&1
test -L "$BREV_TEST_HOME/.local/bin/brev"
cmp "$case_dir/original" "$BREV_TEST_HOME/.local/bin/brev.backup"
cmp "$generation/home-files/.local/bin/brev" "$BREV_TEST_HOME/.local/bin/brev"
test -x "$BREV_TEST_HOME/.local/bin/brev"

in_test_home "$generation/activate" --driver-version 1 > "$case_dir/repeat.log" 2>&1
cmp "$case_dir/original" "$BREV_TEST_HOME/.local/bin/brev.backup"

# A missing binary is restored on apply as well.
rm "$BREV_TEST_HOME/.local/bin/brev"
in_test_home "$generation/activate" --driver-version 1 > "$case_dir/fresh.log" 2>&1
test -x "$BREV_TEST_HOME/.local/bin/brev"
in_test_home "$BREV_TEST_HOME/.local/bin/brev" --help > "$case_dir/help.log" 2>&1
go_package="$(nix build --impure --no-link --print-out-paths --expr '(builtins.getFlake (builtins.getEnv "BREV_TEST_ROOT" + "/home-manager")).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.go')"
build_info="$("$go_package/bin/go" version -m "$BREV_TEST_HOME/.local/bin/brev")"
revision="$(nix eval --impure --raw --expr '(builtins.getFlake (builtins.getEnv "BREV_TEST_ROOT" + "/home-manager")).inputs.brev-cli.shortRev')"
[[ "$build_info" == *"Version=dev-$revision"* ]]
printf 'Brev tests passed: dry-run, existing binary backup, repeat apply, missing binary, version dev-%s.\n' "$revision"

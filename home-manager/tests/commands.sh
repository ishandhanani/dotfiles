#!/usr/bin/env bash
# Exercise command ownership and failure propagation without activating this host.
set -euo pipefail
config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case_dir="$(mktemp -d)"
trap 'rm -rf "$case_dir"' EXIT
export CASE_DIR="$case_dir"
mkdir -p "$case_dir/config/scripts" "$case_dir/bin" "$case_dir/user-generation" "$case_dir/system/sw/bin"
cp "$config_dir/scripts/manage.sh" "$case_dir/config/scripts/manage.sh"
cp "$config_dir/install.sh" "$case_dir/config/install.sh"

cat > "$case_dir/bin/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$CASE_DIR/log"
[[ "${FAIL_BUILD:-0}" == 0 ]] || exit 7
case "$*" in
  *--print-out-paths*homeConfigurations*) printf '%s/user-generation\n' "$CASE_DIR" ;;
  *--print-out-paths*darwinConfigurations*) printf '%s/system\n' "$CASE_DIR" ;;
esac
SH
cat > "$case_dir/bin/id" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${TEST_USER:-tester}"
SH
cat > "$case_dir/bin/uname" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${TEST_OS:-Darwin}"
SH
cat > "$case_dir/bin/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$CASE_DIR/log"
"$@"
SH
cat > "$case_dir/bin/nix-env" <<'SH'
#!/usr/bin/env bash
printf 'system-profile %s\n' "$*" >> "$CASE_DIR/log"
SH
cat > "$case_dir/user-generation/activate" <<'SH'
#!/usr/bin/env bash
printf 'user-activate backup=%s user=%s\n' "$HOME_MANAGER_BACKUP_EXT" "$DOTFILES_USER" >> "$CASE_DIR/log"
SH
cat > "$case_dir/system/sw/bin/darwin-rebuild" <<'SH'
#!/usr/bin/env bash
printf 'system-activate %s\n' "$*" >> "$CASE_DIR/log"
SH
cat > "$case_dir/config/scripts/install-mac-apps.sh" <<'SH'
#!/usr/bin/env bash
printf 'gui-apps\n' >> "$CASE_DIR/log"
SH
chmod +x "$case_dir/bin/"* "$case_dir/user-generation/activate" "$case_dir/system/sw/bin/darwin-rebuild" "$case_dir/config/scripts/"*.sh
export PATH="$case_dir/bin:$PATH"

: > "$case_dir/log"
bash "$case_dir/config/scripts/manage.sh" apply
grep -q '^user-activate backup=backup user=tester$' "$case_dir/log"
if grep -Eq 'sudo|darwinConfigurations|system-activate|gui-apps' "$case_dir/log"; then exit 1; fi

: > "$case_dir/log"
bash "$case_dir/config/scripts/manage.sh" setup-macos
grep -q '^system-profile --profile /nix/var/nix/profiles/system --set ' "$case_dir/log"
grep -q '^system-activate activate$' "$case_dir/log"
grep -q '^gui-apps$' "$case_dir/log"
if grep -Eq 'homeConfigurations|user-activate' "$case_dir/log"; then exit 1; fi

: > "$case_dir/log"
bash "$case_dir/config/scripts/manage.sh" check
grep -q 'homeConfigurations.default.activationPackage.*darwinConfigurations.macos.system' "$case_dir/log"
if grep -Eq 'sudo|user-activate|system-activate|gui-apps' "$case_dir/log"; then exit 1; fi

: > "$case_dir/log"
TEST_OS=Linux bash "$case_dir/config/scripts/manage.sh" check
grep -q 'homeConfigurations.default.activationPackage' "$case_dir/log"
if grep -q darwinConfigurations "$case_dir/log"; then exit 1; fi
if TEST_OS=Linux bash "$case_dir/config/scripts/manage.sh" setup-macos 2>/dev/null; then exit 1; fi

: > "$case_dir/log"
if FAIL_BUILD=1 bash "$case_dir/config/scripts/manage.sh" apply; then exit 1; fi
if grep -q user-activate "$case_dir/log"; then exit 1; fi
if FAIL_BUILD=1 bash "$case_dir/config/scripts/manage.sh" setup-macos; then exit 1; fi
if grep -Eq 'sudo|gui-apps' "$case_dir/log"; then exit 1; fi
if TEST_USER=root bash "$case_dir/config/scripts/manage.sh" apply 2>/dev/null; then exit 1; fi
printf 'Command tests passed: user/system separation, Linux selection, failed builds, root rejection.\n'

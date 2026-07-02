#!/bin/bash
# Re-sign /Applications/Codex.app ad-hoc, inside-out, after swapping its embedded
# codex binary. Strips restricted entitlements (AMFI kills ad-hoc binaries that
# carry them -> "error 163 / Launchd job spawn failed"). Keeps capability entitlements.
#
# Usage: bash resign-app.sh [/path/to/Codex.app]
set -e
APP="${1:-/Applications/Codex.app}"
PB=/usr/libexec/PlistBuddy
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Electron framework version dir is discovered dynamically (survives app updates).
FW="$APP/Contents/Frameworks/Codex Framework.framework/Versions/Current"
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

# Entitlements AMFI rejects for ad-hoc signatures (need Apple provisioning).
RESTRICTED=(
  ":com.apple.application-identifier"
  ":com.apple.developer.team-identifier"
  ":com.apple.security.application-groups"
  ":keychain-access-groups"
)

i=0
sign() {
  local target="$1"
  [ -e "$target" ] || { echo "  skip (missing): $target"; return 0; }
  i=$((i+1))
  local ent="$TMP/ent_$i.plist"
  if codesign -d --entitlements "$ent" --xml "$target" 2>/dev/null && [ -s "$ent" ]; then
    for key in "${RESTRICTED[@]}"; do
      $PB -c "Delete $key" "$ent" >/dev/null 2>&1 || true
    done
    codesign --force --sign - --entitlements "$ent" "$target"
  else
    codesign --force --sign - "$target"
  fi
}

echo ">> dylibs / libraries"
for f in "$FW/Libraries/"*.dylib; do [ -e "$f" ] && sign "$f"; done

echo ">> standalone helper binaries"
for f in app_mode_loader browser_crashpad_handler web_app_shortcut_copier; do
  sign "$FW/Helpers/$f"
done

echo ">> Electron helper apps"
for app in "$FW/Helpers/"*.app; do [ -e "$app" ] && sign "$app"; done

echo ">> Sparkle internals"
sign "$SP/XPCServices/Downloader.xpc"
sign "$SP/XPCServices/Installer.xpc"
sign "$SP/Autoupdate"
sign "$SP/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"

echo ">> Resources helper executables"
sign "$APP/Contents/Resources/codex"
sign "$APP/Contents/Resources/codex_chronicle"
# any other mach-o helpers shipped under Resources (cua_node, native, etc.)
while IFS= read -r f; do
  file "$f" 2>/dev/null | grep -qi mach-o && sign "$f" || true
done < <(find "$APP/Contents/Resources" -maxdepth 2 -type f \
           \( -path "*/cua_node/*" -o -path "*/native/*" \) 2>/dev/null)

echo ">> Codex Framework bundle"
sign "$APP/Contents/Frameworks/Codex Framework.framework"

echo ">> PlugIns"
for p in "$APP/Contents/PlugIns/"*; do [ -e "$p" ] && sign "$p"; done

echo ">> top-level app"
sign "$APP"

echo ">> VERIFY"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "VERIFY_OK"
echo ">> restricted entitlements remaining on main exe:"
codesign -d --entitlements :- "$APP" 2>/dev/null \
  | grep -E "application-identifier|team-identifier|application-groups|keychain" \
  || echo "(none - good)"

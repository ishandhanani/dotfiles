#!/usr/bin/env bash

set -euo pipefail

failures=0

ok() { printf '\033[1;32mOK\033[0m   %s\n' "$*"; }
bad() {
  printf '\033[0;31mBAD\033[0m  %s\n' "$*"
  failures=$((failures + 1))
}
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

read_default() {
  local domain="$1"
  local key="$2"

  if [[ "$domain" == "-g" ]]; then
    /usr/bin/defaults read -g "$key" 2>/dev/null || printf '<unset>'
  else
    /usr/bin/defaults read "$domain" "$key" 2>/dev/null || printf '<unset>'
  fi
}

number_equal() {
  /usr/bin/awk -v actual="$1" -v expected="$2" 'BEGIN {
    if (actual !~ /^-?[0-9]+([.][0-9]+)?$/) exit 1
    exit ((actual + 0) == (expected + 0) ? 0 : 1)
  }'
}

check_number() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if number_equal "$actual" "$expected"; then
    ok "${label}: ${actual}"
  else
    bad "${label}: expected ${expected}, got ${actual}"
  fi
}

check_string() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" == "$expected" ]]; then
    ok "${label}: ${actual}"
  else
    bad "${label}: expected ${expected}, got ${actual}"
  fi
}

check_file_contains() {
  local label="$1"
  local path="$2"
  local pattern="$3"

  if [[ ! -e "$path" ]]; then
    bad "${label}: missing ${path}"
  elif /usr/bin/grep -Fq "$pattern" "$path"; then
    ok "${label}: ${path}"
  else
    bad "${label}: expected ${path} to contain ${pattern}"
  fi
}

check_disabled_or_unset() {
  local label="$1"
  local actual="$2"

  case "$actual" in
    0|false|FALSE|"<unset>")
      ok "${label}: ${actual}"
      ;;
    *)
      bad "${label}: expected disabled or unset, got ${actual}"
      ;;
  esac
}

check_caps_lock_escape() {
  local mapping

  mapping="$(/usr/bin/hidutil property --get UserKeyMapping 2>/dev/null || true)"
  if printf '%s\n' "$mapping" | /usr/bin/grep -q '30064771129' \
    && printf '%s\n' "$mapping" | /usr/bin/grep -q '30064771113'; then
    ok "Caps Lock -> Escape mapping present"
  else
    bad "Caps Lock -> Escape mapping missing"
  fi
}

check_spotlight_hotkey_disabled() {
  local hotkey_id="$1"
  local enabled
  enabled="$(/usr/bin/defaults export com.apple.symbolichotkeys - 2>/dev/null \
    | /usr/bin/plutil -extract "AppleSymbolicHotKeys.${hotkey_id}.enabled" raw -o - -- - 2>/dev/null || printf '<unset>')"
  case "$enabled" in
    0|false) ok "Spotlight hotkey ${hotkey_id} disabled" ;;
    *) bad "Spotlight hotkey ${hotkey_id}: expected disabled, got ${enabled}" ;;
  esac
}

check_chrome_extension_policy() {
  local extensions_file policy i id name mode

  extensions_file="$(cd "$(dirname "$0")/.." && pwd)/chrome/extensions.json"
  if ! policy="$(/usr/bin/defaults export /Library/Preferences/com.google.Chrome - 2>/dev/null)"; then
    bad "Chrome extension policy: expected ExtensionSettings in /Library/Preferences/com.google.Chrome"
    return
  fi

  i=0
  while id="$(/usr/bin/plutil -extract "${i}.id" raw -o - "$extensions_file" 2>/dev/null)"; do
    name="$(/usr/bin/plutil -extract "${i}.name" raw -o - "$extensions_file" 2>/dev/null || printf '%s' "$id")"
    mode="$(printf '%s\n' "$policy" | /usr/bin/plutil -extract "ExtensionSettings.${id}.installation_mode" raw -o - -- - 2>/dev/null || printf '<unset>')"
    check_string "Chrome extension ${name}" "$mode" normal_installed
    i=$((i + 1))
  done
  if [[ "$i" == 0 ]]; then bad "Chrome extension manifest is empty or invalid"; fi
}

check_rectangle_defaults() {
  check_number "Rectangle launch on login" "$(read_default com.knollsoft.Rectangle launchOnLogin)" "1"
  check_number "Rectangle alternate shortcuts" "$(read_default com.knollsoft.Rectangle alternateDefaultShortcuts)" "1"
  local shortcuts key actual
  shortcuts="$(/usr/bin/defaults export com.knollsoft.Rectangle - 2>/dev/null || true)"
  for key in keyCode modifierFlags; do
    actual="$(printf '%s\n' "$shortcuts" | /usr/bin/plutil -extract "leftHalf.$key" raw -o - -- - 2>/dev/null || printf '<unset>')"
    case "$key" in
      keyCode) check_number "Rectangle left-half key" "$actual" 123 ;;
      modifierFlags) check_number "Rectangle left-half modifiers" "$actual" 786432 ;;
    esac
  done
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  bad "This check is intended for macOS only"
  exit "$failures"
fi

info "Keyboard and pointer"
check_number "Key repeat" "$(read_default -g KeyRepeat)" "2"
check_number "Initial key repeat" "$(read_default -g InitialKeyRepeat)" "15"
check_number "Press-and-hold disabled" "$(read_default -g ApplePressAndHoldEnabled)" "0"
check_number "Trackpad speed" "$(read_default -g com.apple.trackpad.scaling)" "2.5"
check_number "Mouse speed" "$(read_default -g com.apple.mouse.scaling)" "3.0"
check_caps_lock_escape

info "Dock and appearance"
check_disabled_or_unset "Automatic appearance switching" "$(read_default -g AppleInterfaceStyleSwitchesAutomatically)"
check_string "Interface style" "$(read_default -g AppleInterfaceStyle)" "Dark"
check_number "Dock recent apps" "$(read_default com.apple.dock show-recents)" "0"
check_number "Dock tile size" "$(read_default com.apple.dock tilesize)" "47"
check_number "Dock magnification" "$(read_default com.apple.dock magnification)" "1"

info "Raycast and Spotlight"
check_string "Raycast hotkey" "$(read_default com.raycast.macos raycastGlobalHotkey)" "Command-49"
check_spotlight_hotkey_disabled 64
check_spotlight_hotkey_disabled 65

info "Chrome extensions"
check_chrome_extension_policy

info "App configs"
check_file_contains "Ghostty config" "${HOME}/.config/ghostty/config" "working-directory = ${HOME}"
check_file_contains "Ghostty dark background" "${HOME}/.config/ghostty/config" "background = #000000"
check_file_contains "Ghostty dark foreground" "${HOME}/.config/ghostty/config" "foreground = #bbbbbb"
check_rectangle_defaults

info "Tracked GUI apps"
if ! "$(dirname "$0")/install-mac-apps.sh" --check; then
  bad "Tracked GUI apps are missing"
fi

if [[ "$failures" -eq 0 ]]; then
  ok "macOS settings, app configs, and GUI apps match this repo"
else
  printf '\n%s check(s) failed. Run make setup-macos for system settings/apps and make apply for app configs. Keyboard/pointer changes may need a restart.\n' "$failures" >&2
fi

exit "$failures"

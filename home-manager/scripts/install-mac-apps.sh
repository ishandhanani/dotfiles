#!/usr/bin/env bash
# Opt-in bootstrap for common macOS GUI apps.
#
# This does not require Homebrew. It uses Homebrew's public cask JSON as a
# metadata feed for current vendor download URLs, then downloads and installs
# ZIP/DMG app bundles directly.

set -euo pipefail

NAMES=("Google Chrome" "iTerm2" "Raycast" "Rectangle" "Cursor")
CASKS=("google-chrome" "iterm2" "raycast" "rectangle" "cursor")
BUNDLES=("Google Chrome.app" "iTerm.app" "Raycast.app" "Rectangle.app" "Cursor.app")
KINDS=("dmg" "zip" "dmg" "dmg" "zip")

APP_DIR="/Applications"
DOWNLOAD_DIR="${HOME}/Downloads/mac-apps"
DRY_RUN=0
LIST=0
DOWNLOAD_ONLY=0
KEEP_DOWNLOADS=0

info() { printf '\033[1;34m=> %s\033[0m\n' "$*" >&2; }
ok() { printf '\033[1;32m   %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }
error() { printf '\033[0;31m!! %s\033[0m\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./install-mac-apps.sh [options]

Options:
  -h, --help              Show this help and exit
  -n, --dry-run           Print what would be done without downloading or installing
  -l, --list              List tracked apps and their install status
      --download-only     Download missing app archives without installing them
      --download-dir DIR  Directory for downloaded archives (default: ~/Downloads/mac-apps)
      --app-dir DIR       Install destination (default: /Applications)
      --user-app-dir      Install to ~/Applications
      --keep-downloads    Keep downloaded archives after installing
EOF
}

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
    --download-only)
      DOWNLOAD_ONLY=1
      KEEP_DOWNLOADS=1
      shift
      ;;
    --download-dir)
      DOWNLOAD_DIR="${2:?missing directory after --download-dir}"
      shift 2
      ;;
    --app-dir)
      APP_DIR="${2:?missing directory after --app-dir}"
      shift 2
      ;;
    --user-app-dir)
      APP_DIR="${HOME}/Applications"
      shift
      ;;
    --keep-downloads)
      KEEP_DOWNLOADS=1
      shift
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "${OSTYPE}" != darwin* ]]; then
  error "This script is intended for macOS only (found OSTYPE=${OSTYPE})"
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command: $1"
    exit 1
  fi
}

app_location() {
  local bundle="$1"
  local dir

  for dir in "$APP_DIR" /Applications "$HOME/Applications"; do
    if [[ -d "${dir}/${bundle}" ]]; then
      printf '%s\n' "${dir}/${bundle}"
      return 0
    fi
  done

  return 1
}

list_apps() {
  local i name cask bundle status

  printf '%-12s %-28s %s\n' "Name" "Metadata" "Status"
  for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    cask="${CASKS[$i]}"
    bundle="${BUNDLES[$i]}"
    if status="$(app_location "$bundle")"; then
      printf '%-12s %-28s %s\n' "$name" "$cask" "$status"
    else
      printf '%-12s %-28s %s\n' "$name" "$cask" "missing"
    fi
  done
}

metadata_url() {
  printf 'https://formulae.brew.sh/api/cask/%s.json\n' "$1"
}

resolve_download_url() {
  local cask="$1"
  curl -fsSL "$(metadata_url "$cask")" | /usr/bin/plutil -extract url raw -o - -
}

find_app_bundle() {
  local root="$1"
  local bundle="$2"
  local found

  found="$(find "$root" -maxdepth 4 -name "$bundle" -type d -print -quit)"
  if [[ -z "$found" ]]; then
    return 1
  fi

  printf '%s\n' "$found"
}

ensure_app_dir() {
  if [[ -d "$APP_DIR" ]]; then
    return 0
  fi

  mkdir -p "$APP_DIR" 2>/dev/null || sudo mkdir -p "$APP_DIR"
}

copy_app() {
  local source="$1"
  local bundle="$2"
  local dest="${APP_DIR%/}/${bundle}"

  if [[ -e "$dest" ]]; then
    warn "${bundle} appeared during install; leaving it untouched"
    return 0
  fi

  ensure_app_dir
  if [[ -w "$APP_DIR" ]]; then
    ditto "$source" "$dest"
  else
    info "Copying ${bundle} with sudo into ${APP_DIR}"
    sudo ditto "$source" "$dest"
  fi
}

download_archive() {
  local name="$1"
  local cask="$2"
  local kind="$3"
  local url archive

  url="$(resolve_download_url "$cask")"
  archive="${DOWNLOAD_DIR%/}/${cask}.${kind}"

  info "Downloading ${name}"
  mkdir -p "$DOWNLOAD_DIR"
  curl -fL --progress-bar -o "$archive" "$url"
  printf '%s\n' "$archive"
}

install_zip() {
  local archive="$1"
  local bundle="$2"
  local extract_dir source

  extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/mac-app-zip.XXXXXX")"
  cleanup_zip() {
    rm -rf "$extract_dir"
  }
  trap cleanup_zip RETURN

  ditto -x -k "$archive" "$extract_dir"
  source="$(find_app_bundle "$extract_dir" "$bundle")"
  copy_app "$source" "$bundle"

  cleanup_zip
  trap - RETURN
}

install_dmg() {
  local archive="$1"
  local bundle="$2"
  local mount_dir source

  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/mac-app-dmg.XXXXXX")"
  cleanup_dmg() {
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  }
  trap cleanup_dmg RETURN

  hdiutil attach "$archive" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
  source="$(find_app_bundle "$mount_dir" "$bundle")"
  copy_app "$source" "$bundle"

  cleanup_dmg
  trap - RETURN
}

install_archive() {
  local archive="$1"
  local kind="$2"
  local bundle="$3"

  case "$kind" in
    zip)
      install_zip "$archive" "$bundle"
      ;;
    dmg)
      install_dmg "$archive" "$bundle"
      ;;
    *)
      error "Unsupported archive kind: $kind"
      exit 1
      ;;
  esac
}

if [[ "$LIST" == 1 ]]; then
  list_apps
  exit 0
fi

MISSING_INDEXES=()
for i in "${!NAMES[@]}"; do
  if app_location "${BUNDLES[$i]}" >/dev/null; then
    ok "${NAMES[$i]} already present (${BUNDLES[$i]})"
  else
    MISSING_INDEXES+=("$i")
  fi
done

if [[ "${#MISSING_INDEXES[@]}" -eq 0 ]]; then
  ok "All tracked apps are present"
  exit 0
fi

if [[ "$DRY_RUN" == 1 ]]; then
  for i in "${MISSING_INDEXES[@]}"; do
    info "Would resolve ${NAMES[$i]} from $(metadata_url "${CASKS[$i]}")"
    if [[ "$DOWNLOAD_ONLY" == 1 ]]; then
      info "Would download ${NAMES[$i]} to ${DOWNLOAD_DIR}"
    else
      info "Would download and install ${NAMES[$i]} into ${APP_DIR}"
    fi
  done
  exit 0
fi

require_command curl

if [[ "$DOWNLOAD_ONLY" != 1 ]]; then
  require_command ditto
  require_command hdiutil
fi

if [[ ! -x /usr/bin/plutil ]]; then
  error "Missing required command: /usr/bin/plutil"
  exit 1
fi

if [[ "$KEEP_DOWNLOADS" != 1 ]]; then
  DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-app-downloads.XXXXXX")"
  cleanup_downloads() {
    rm -rf "$DOWNLOAD_DIR"
  }
  trap cleanup_downloads EXIT
fi

for i in "${MISSING_INDEXES[@]}"; do
  name="${NAMES[$i]}"
  archive="$(download_archive "$name" "${CASKS[$i]}" "${KINDS[$i]}")"

  if [[ "$DOWNLOAD_ONLY" == 1 ]]; then
    ok "Downloaded ${name}: ${archive}"
    continue
  fi

  install_archive "$archive" "${KINDS[$i]}" "${BUNDLES[$i]}"
  ok "Installed ${name}"
done

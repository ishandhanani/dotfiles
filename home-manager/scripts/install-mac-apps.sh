#!/usr/bin/env bash

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
CLEANUP_DIRS=()
CLEANUP_FILES=()
MOUNT_DIRS=()
DOWNLOADED_ARCHIVE=""
FETCHED_METADATA_FILE=""
SELECTED_URL=""
SELECTED_SHA=""

info() { printf '\033[1;34m=> %s\033[0m\n' "$*" >&2; }
ok() { printf '\033[1;32m   %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }
error() { printf '\033[0;31m!! %s\033[0m\n' "$*" >&2; }

cleanup_all() {
  local mount dir file

  set +u

  for mount in "${MOUNT_DIRS[@]}"; do
    hdiutil detach "$mount" >/dev/null 2>&1 || true
    rmdir "$mount" >/dev/null 2>&1 || true
  done

  for dir in "${CLEANUP_DIRS[@]}"; do
    rm -rf "$dir"
  done

  for file in "${CLEANUP_FILES[@]}"; do
    rm -f "$file"
  done
}

trap cleanup_all EXIT

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

macos_codename() {
  local version major minor

  version="$(sw_vers -productVersion)"
  major="${version%%.*}"

  case "$major" in
    27)
      printf 'golden_gate\n'
      ;;
    26)
      printf 'tahoe\n'
      ;;
    15)
      printf 'sequoia\n'
      ;;
    14)
      printf 'sonoma\n'
      ;;
    13)
      printf 'ventura\n'
      ;;
    12)
      printf 'monterey\n'
      ;;
    11)
      printf 'big_sur\n'
      ;;
    10)
      minor="${version#10.}"
      minor="${minor%%.*}"
      case "$minor" in
        15)
          printf 'catalina\n'
          ;;
        14)
          printf 'mojave\n'
          ;;
        13)
          printf 'high_sierra\n'
          ;;
        12)
          printf 'sierra\n'
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

variation_candidates() {
  local arch codename

  arch="$(uname -m)"
  codename="$(macos_codename || true)"

  case "$arch" in
    arm64)
      if [[ -n "$codename" ]]; then
        printf 'arm64_%s\n' "$codename"
      fi
      printf 'arm64\n'
      ;;
    x86_64)
      if [[ -n "$codename" ]]; then
        printf '%s\n' "$codename"
        printf 'x86_64_%s\n' "$codename"
        printf 'intel_%s\n' "$codename"
      fi
      printf 'x86_64\n'
      printf 'intel\n'
      ;;
    *)
      if [[ -n "$codename" ]]; then
        printf '%s_%s\n' "$arch" "$codename"
      fi
      printf '%s\n' "$arch"
      ;;
  esac
}

extract_metadata_value() {
  local metadata_file="$1"
  local path="$2"
  local value

  if ! value="$(/usr/bin/plutil -extract "$path" raw -o - "$metadata_file" 2>/dev/null)"; then
    return 1
  fi

  if [[ -z "$value" || "$value" == "null" ]]; then
    return 1
  fi

  printf '%s\n' "$value"
}

fetch_cask_metadata() {
  local cask="$1"
  local metadata_file

  metadata_file="$(mktemp "${TMPDIR:-/tmp}/mac-app-cask.XXXXXX")"
  CLEANUP_FILES+=("$metadata_file")
  curl -fsSL "$(metadata_url "$cask")" -o "$metadata_file"
  FETCHED_METADATA_FILE="$metadata_file"
}

select_cask_metadata() {
  local metadata_file="$1"
  local key url sha

  SELECTED_URL=""
  SELECTED_SHA=""

  while IFS= read -r key; do
    if url="$(extract_metadata_value "$metadata_file" "variations.${key}.url")"; then
      sha="$(extract_metadata_value "$metadata_file" "variations.${key}.sha256" || printf 'no_check')"
      SELECTED_URL="$url"
      SELECTED_SHA="$sha"
      return 0
    fi
  done < <(variation_candidates)

  if url="$(extract_metadata_value "$metadata_file" url)"; then
    sha="$(extract_metadata_value "$metadata_file" sha256 || printf 'no_check')"
    SELECTED_URL="$url"
    SELECTED_SHA="$sha"
    return 0
  fi

  error "Could not resolve a download URL from cask metadata"
  return 1
}

verify_archive() {
  local name="$1"
  local archive="$2"
  local expected="$3"
  local actual

  if [[ "$expected" == "no_check" ]]; then
    warn "No SHA-256 published for ${name}; skipping verification"
    return 0
  fi

  require_command shasum
  actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
  if [[ "$actual" != "$expected" ]]; then
    error "SHA-256 mismatch for ${name}"
    error "Expected: ${expected}"
    error "Actual:   ${actual}"
    return 1
  fi

  ok "Verified ${name} SHA-256"
}

find_app_bundle() {
  local root="$1"
  local bundle="$2"
  local found

  found="$(find "$root" -maxdepth 4 -name "$bundle" -type d -print -quit)"
  if [[ -z "$found" ]]; then
    error "Could not find ${bundle} under ${root}"
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
  local metadata_file url sha archive

  fetch_cask_metadata "$cask"
  metadata_file="$FETCHED_METADATA_FILE"
  select_cask_metadata "$metadata_file"
  url="$SELECTED_URL"
  sha="$SELECTED_SHA"
  archive="${DOWNLOAD_DIR%/}/${cask}.${kind}"

  info "Downloading ${name}"
  mkdir -p "$DOWNLOAD_DIR"
  curl -fL --progress-bar -o "$archive" "$url"
  verify_archive "$name" "$archive" "$sha"
  DOWNLOADED_ARCHIVE="$archive"
}

install_zip() {
  local archive="$1"
  local bundle="$2"
  local extract_dir source

  extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/mac-app-zip.XXXXXX")"
  CLEANUP_DIRS+=("$extract_dir")

  ditto -x -k "$archive" "$extract_dir"
  source="$(find_app_bundle "$extract_dir" "$bundle")"
  copy_app "$source" "$bundle"

  rm -rf "$extract_dir"
}

install_dmg() {
  local archive="$1"
  local bundle="$2"
  local mount_dir source

  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/mac-app-dmg.XXXXXX")"
  MOUNT_DIRS+=("$mount_dir")

  hdiutil attach "$archive" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
  source="$(find_app_bundle "$mount_dir" "$bundle")"
  copy_app "$source" "$bundle"

  hdiutil detach "$mount_dir" >/dev/null
  rmdir "$mount_dir"
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
  CLEANUP_DIRS+=("$DOWNLOAD_DIR")
fi

for i in "${MISSING_INDEXES[@]}"; do
  name="${NAMES[$i]}"
  download_archive "$name" "${CASKS[$i]}" "${KINDS[$i]}"
  archive="$DOWNLOADED_ARCHIVE"

  if [[ "$DOWNLOAD_ONLY" == 1 ]]; then
    ok "Downloaded ${name}: ${archive}"
    continue
  fi

  install_archive "$archive" "${KINDS[$i]}" "${BUNDLES[$i]}"
  ok "Installed ${name}"
done

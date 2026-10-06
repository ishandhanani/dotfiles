#!/usr/bin/env bash
set -euo pipefail

manifest="$(dirname "${BASH_SOURCE[0]}")/mac-apps.tsv"
mode="${1:-install}"
if [[ $# -gt 1 ]]; then
  printf 'Expected at most one option\n' >&2
  exit 1
fi
case "$mode" in
  --help|-h)
    printf 'Usage: %s [--list|--check|--dry-run]\n' "$0"
    printf 'Install missing GUI apps into /Applications. --check fails if apps are missing.\n'
    exit 0 ;;
  install|--list|--check|--dry-run) ;;
  *) printf 'Unknown option: %s\n' "$mode" >&2; exit 1 ;;
esac
if [[ "$(uname -s)" != Darwin ]]; then
  printf 'This installer is only available on macOS\n' >&2
  exit 1
fi

app_location() {
  local dir
  for dir in /Applications "$HOME/Applications"; do
    if [[ -d "$dir/$1" ]]; then
      printf '%s\n' "$dir/$1"
      return 0
    fi
  done
  return 1
}

macos_codename() {
  local version
  version="$(sw_vers -productVersion)"
  case "$version" in
    27.*) printf 'golden_gate\n' ;;
    26.*) printf 'tahoe\n' ;;
    15.*) printf 'sequoia\n' ;;
    14.*) printf 'sonoma\n' ;;
    13.*) printf 'ventura\n' ;;
    12.*) printf 'monterey\n' ;;
    11.*) printf 'big_sur\n' ;;
    10.15.*) printf 'catalina\n' ;;
    10.14.*) printf 'mojave\n' ;;
    *) return 1 ;;
  esac
}

variation_candidates() {
  local codename
  codename="$(macos_codename || true)"
  case "$(uname -m)" in
    arm64)
      [[ -z "$codename" ]] || printf 'arm64_%s\n' "$codename"
      printf 'arm64\n' ;;
    x86_64)
      [[ -z "$codename" ]] || printf '%s\nx86_64_%s\nintel_%s\n' "$codename" "$codename" "$codename"
      printf 'x86_64\nintel\n' ;;
    *) printf 'Unsupported Mac architecture\n' >&2; return 1 ;;
  esac
}

metadata_value() {
  local value
  value="$(/usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null)" || return 1
  [[ -n "$value" && "$value" != null ]] || return 1
  printf '%s\n' "$value"
}

select_metadata() {
  local key
  while IFS= read -r key; do
    if download_url="$(metadata_value "$1" "variations.$key.url")"; then
      expected_sha="$(metadata_value "$1" "variations.$key.sha256" || printf no_check)"
      return
    fi
  done < <(variation_candidates)
  download_url="$(metadata_value "$1" url)"
  expected_sha="$(metadata_value "$1" sha256 || printf no_check)"
}

work_dir=""
mount_dir=""
cleanup() {
  if [[ -n "$mount_dir" ]]; then
    if ! hdiutil detach "$mount_dir" >/dev/null 2>&1; then
      printf 'Could not unmount %s; leaving temporary files in place\n' "$mount_dir" >&2
      return
    fi
  fi
  if [[ -n "$work_dir" ]]; then rm -rf "$work_dir"; fi
}
trap cleanup EXIT

copy_bundle() {
  local source
  source="$(find "$1" -maxdepth 4 -type d -name "$2" -print -quit)"
  if [[ -z "$source" ]]; then
    printf 'Could not find %s in the downloaded archive\n' "$2" >&2
    return 1
  fi
  if [[ -e "/Applications/$2" ]]; then
    printf '%s appeared during installation, skipping\n' "$2"
  elif [[ -w /Applications ]]; then
    ditto "$source" "/Applications/$2"
  else
    sudo ditto "$source" "/Applications/$2"
  fi
}

missing=0
while IFS=$'\t' read -r name cask bundle kind; do
  if location="$(app_location "$bundle")"; then
    printf '%-14s %s\n' "$name" "$location"
    continue
  fi
  missing=$((missing + 1))
  case "$mode" in
    --list|--check) printf '%-14s missing\n' "$name"; continue ;;
    --dry-run) printf 'Would download and install %s into /Applications\n' "$name"; continue ;;
  esac

  if [[ -z "$work_dir" ]]; then work_dir="$(mktemp -d)"; fi
  curl -fsSL "https://formulae.brew.sh/api/cask/$cask.json" -o "$work_dir/metadata.json"
  select_metadata "$work_dir/metadata.json"
  archive="$work_dir/$cask.$kind"
  printf 'Downloading %s\n' "$name"
  curl -fL --progress-bar "$download_url" -o "$archive"
  if [[ "$expected_sha" == no_check ]]; then
    printf 'No SHA-256 published for %s; skipping verification\n' "$name" >&2
  else
    actual_sha="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      printf 'SHA-256 mismatch for %s\n' "$name" >&2
      exit 1
    fi
    printf 'Verified %s SHA-256\n' "$name"
  fi

  case "$kind" in
    zip)
      mkdir "$work_dir/extracted"
      ditto -x -k "$archive" "$work_dir/extracted"
      copy_bundle "$work_dir/extracted" "$bundle"
      rm -rf "$work_dir/extracted" ;;
    dmg)
      mkdir "$work_dir/mount"
      hdiutil attach "$archive" -nobrowse -readonly -mountpoint "$work_dir/mount" >/dev/null
      mount_dir="$work_dir/mount"
      copy_bundle "$mount_dir" "$bundle"
      hdiutil detach "$mount_dir" >/dev/null
      rmdir "$mount_dir"
      mount_dir="" ;;
    pkg)
      sudo /usr/sbin/installer -pkg "$archive" -target / ;;
    *) printf 'Unsupported archive format: %s\n' "$kind" >&2; exit 1 ;;
  esac
  if ! app_location "$bundle" >/dev/null; then
    printf 'Installer completed but %s is missing\n' "$bundle" >&2
    exit 1
  fi
  rm -f "$archive"
  printf 'Installed %s\n' "$name"
done < "$manifest"

if [[ "$mode" == --check && "$missing" -gt 0 ]]; then
  printf '%s GUI app(s) missing\n' "$missing" >&2
  exit 1
fi

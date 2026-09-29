---
name: codex-install-from-patch
description: Install a patched Codex CLI (and desktop app on macOS) from a GitHub release or source. Run only when explicitly invoked.
user-invocable: true
---

# Codex Install From Patch

Install a Codex fork (e.g. `Aphoh/codex` `enforce-us` releases) on macOS Apple Silicon or Linux, replacing the current `codex` CLI and any bundled desktop app.

## Invocation policy (hard rule)

Run this ONLY when the user explicitly invokes `/codex-install-from-patch`. Do not trigger it from any other prompt, do not let another agent/skill select it, and do not run it as a side effect. If you are reasoning about which skill fits a task, this one is never the answer unless the user named it.

## Inputs

Ask the user for (or infer from their message):
- **Source ref**: a release-tag URL (e.g. `https://github.com/Aphoh/codex/releases/tag/enforce-us-v0.142.2`), or `owner/repo` + tag/branch/commit. From a release URL, derive `owner/repo` and the tag.

## Preconditions / assumptions

- A fresh build directory for each installation. Preserve prior build directories because they can contain restore backups; record the selected path in the handoff.
- Backups go in `$BUILD_DIR/backups/`.
- On macOS: Apple Silicon (`uname -m` = `arm64`), macOS, Rust toolchain, `/Applications/Codex.app` Electron app.
- On Linux: `~/.local/bin/codex` (or `which codex`), x86-64 or aarch64, `gh` or `curl` available. `~/.local/bin/codex-code-mode-host` is installed alongside `codex` if the release ships it.

## Platform detection

Run `uname -s` and `uname -m` first. Support matrix:
- `Darwin` + `arm64` → macOS Apple Silicon path below.
- `Linux` + `x86_64` / `aarch64` → Linux path below.
- Anything else → stop and tell the user the platform is unsupported.

## macOS path

### 0. Recon
```
uname -m
which codex && codex --version
file "$(which codex)"
/Applications/Codex.app/Contents/Resources/codex --version
codesign -dv /Applications/Codex.app 2>&1 | grep -E "Identifier|flags|TeamIdentifier"
```
Confirm the fork version is the SAME generation as the bundled CLI. A large mismatch risks an app-server protocol break — warn the user.

### 1. Build from source
```
BUILD_DIR=$(mktemp -d "$HOME/codex-fork-build.XXXXXX")
git clone --depth 1 --branch <TAG> https://github.com/<OWNER>/<REPO>.git "$BUILD_DIR/source"
cd "$BUILD_DIR/source/codex-rs"
git rev-parse HEAD
CARGO_TERM_COLOR=never cargo build --release --bin codex > "$BUILD_DIR/build.log" 2>&1
```
The `codex` binary comes from the `codex-cli` crate. Run the build in the background (~15-25 min). Output: `codex-rs/target/release/codex`. Verify `--version`. If the build also produces `codex-code-mode-host`, copy it to `~/.local/bin` as well.

### 2. Install the CLI
```
BIN="$BUILD_DIR/source/codex-rs/target/release/codex"
mkdir -p "$BUILD_DIR/backups"
cp -p ~/.local/bin/codex "$BUILD_DIR/backups/cli-original"
cp "$BIN" ~/.local/bin/codex && chmod +x ~/.local/bin/codex
codesign --force --sign - ~/.local/bin/codex
~/.local/bin/codex --version
```

### 3. Patch the desktop app
Quit the desktop app only when authorized; otherwise prepare the binary and backup plan, then ask.
```
osascript -e 'tell application "Codex" to quit'
# wait for exit; force-kill only if it hangs
```
Swap the embedded binary and move the backup OUT of the bundle:
```
RES=/Applications/Codex.app/Contents/Resources/codex
mkdir -p "$BUILD_DIR/backups"
cp -p "$RES" "$BUILD_DIR/backups"/codex.bak-<BUNDLEDVER>
cp "$BIN" "$RES" && chmod +x "$RES"
```

### 4. Re-sign the whole bundle
Modifying a sealed resource invalidates the app signature. Re-sign inside-out, ad-hoc, and strip restricted entitlements.
- `codesign --deep` alone leaves nested frameworks invalid — sign each component explicitly, deepest first.
- Do NOT preserve `requirements` (the original pins OpenAI's Team ID). Let codesign generate a fresh designated requirement.
- Strip restricted entitlements (`com.apple.application-identifier`, `com.apple.developer.team-identifier`, `com.apple.security.application-groups`, `keychain-access-groups`). Ad-hoc signatures carrying these are killed by AMFI at launch. Keep capability entitlements (jit, camera, mic, network, file access).
```
bash <SKILL_DIR>/resign-app.sh
```
It ends with `codesign --verify --deep --strict /Applications/Codex.app` → expect `VERIFY_OK` and "satisfies its Designated Requirement".

### 5. Launch and verify
```
xattr -dr com.apple.quarantine /Applications/Codex.app 2>/dev/null
open -a /Applications/Codex.app
pgrep -fl "Codex.app/Contents/MacOS/Codex"
pgrep -fl "Codex.app/Contents/Resources/codex app-server"
```
Success = main process stable + a `Resources/codex app-server` child + renderer/GPU helpers up.

## Linux path

### 0. Recon
```
uname -sm
which codex && codex --version
file "$(which codex)"
```

### 1. Download the release asset
Use `gh release download` if authenticated; otherwise `curl -L`. Derive the asset name from the tag and architecture, e.g. `codex-0.156.1-enforce-us-linux-x86-64.tar.gz`.
```
BUILD_DIR=$(mktemp -d "$HOME/codex-install.XXXXXX")
cd "$BUILD_DIR"
gh release download <TAG> --repo <OWNER>/<REPO> --pattern '*linux-x86-64.tar.gz'
# or aarch64: --pattern '*linux-aarch64.tar.gz'
```
Verify the SHA-256 from the release body. Extract the archive and confirm the binaries:
```
tar -xzf codex-*.tar.gz
./codex --version
file ./codex
file ./codex-code-mode-host 2>/dev/null || true
```

### 2. Install the CLI binaries
Back up the current binaries, then replace them. If any binary is currently running, `cp` will fail with "Text file busy". In that case `mv` the old binary aside first (running processes keep the old inode) and then `cp` the new one.
```
mkdir -p "$BUILD_DIR/backups"
cp -p ~/.local/bin/codex "$BUILD_DIR/backups/codex" 2>/dev/null || true
cp -p ~/.local/bin/codex-code-mode-host "$BUILD_DIR/backups/codex-code-mode-host" 2>/dev/null || true

for bin in codex codex-code-mode-host; do
  [ -e "$bin" ] || continue
  if [ -e ~/.local/bin/"$bin" ]; then
    # move the old file to avoid ETXTBSY if it's currently executing
    mv ~/.local/bin/"$bin" "$BUILD_DIR/backups/$bin-old" 2>/dev/null || true
  fi
  cp "$bin" ~/.local/bin/"$bin" && chmod +x ~/.local/bin/"$bin"
done

~/.local/bin/codex --version
```

### 3. Replace running processes (optional, when safe)
New launches use the installed binary, but existing `codex` / `codex-code-mode-host` processes still hold the old inode. To fully switch over:
- Kill stale `codex app-server` / `codex app-server proxy` / `codex-code-mode-host` processes.
- If a supervisor such as `cortexd` or an agent-dashboard bridge respawns `codex app-server`, restart that supervisor after confirming it is safe to interrupt.
- Verify with `ps aux | grep -i codex` that new processes use the new version path.

## Restore originals

Set `BUILD_DIR` to the recorded installation directory containing the matching backups. Do not guess or delete earlier directories.

### macOS
```
cp "$BUILD_DIR/backups/cli-original" ~/.local/bin/codex
cp "$BUILD_DIR/backups"/codex.bak-<BUNDLEDVER> /Applications/Codex.app/Contents/Resources/codex
# then reinstall the app (clean signature) or re-run resign-app.sh
```

### Linux
```
cp "$BUILD_DIR/backups/codex" ~/.local/bin/codex
cp "$BUILD_DIR/backups/codex-code-mode-host" ~/.local/bin/codex-code-mode-host 2>/dev/null || true
chmod +x ~/.local/bin/codex ~/.local/bin/codex-code-mode-host 2>/dev/null
```

## Caveats to tell the user

- **macOS re-login**: stripping `keychain-access-groups` cuts the app off from the OpenAI keychain group; sign in again if it shows logged out. CLI auth (`~/.codex/auth.json`) is unaffected.
- **macOS computer-use**: stripping the `CUAService` app-group breaks that IPC; the computer-use feature may not work. Core chat/agent does.
- **macOS auto-update reverts it**: Sparkle (app) or a CLI reinstall overwrites these with official builds. Re-run build + `resign-app.sh` after any update.
- **Linux active inodes**: running `codex` processes continue on the old binary until they exit. New launches pick up the new version.
- **Linux supervisors**: `cortexd`, agent-dashboard bridges, or systemd units may respawn `codex` automatically. Restart the supervisor (or the whole service) to roll over.

---
name: local-mac-codex-install-from-patch
description: "MANUAL-ONLY. Build a Codex fork/branch from source on Apple Silicon macOS and install it as both the CLI (~/.local/bin/codex) and the desktop app (/Applications/Codex.app) by swapping the app's embedded binary and re-signing the bundle. ONLY run when the user explicitly types /local-mac-codex-install-from-patch. NEVER auto-invoke this skill, never select it for a model-initiated task, never run it as a side effect of any other request."
user-invocable: true
---

# Local Mac Codex Install From Patch

Build a Codex fork that ships no macOS binary (e.g. a GitHub release tag with only a Linux asset) from source on Apple Silicon, then make BOTH the `codex` CLI and the desktop `Codex.app` use it.

## Invocation policy (hard rule)

Run this ONLY when the user explicitly invokes `/local-mac-codex-install-from-patch`. Do not trigger it from any other prompt, do not let another agent/skill select it, and do not run it as a side effect. If you are reasoning about which skill fits a task, this one is never the answer unless the user named it.

## Inputs

Ask the user for (or infer from their message):
- **Source ref**: a release-tag URL (e.g. `https://github.com/Aphoh/codex/releases/tag/enforce-us-v0.142.2`), or a `owner/repo` + tag/branch/commit. From a release URL, derive `owner/repo` and the tag.

## Preconditions / assumptions

- Apple Silicon (`uname -m` = `arm64`), macOS, Rust toolchain installed (`cargo`, `rustc`).
- CLI lives at `~/.local/bin/codex` (a standalone Mach-O, not an npm wrapper). Adjust if `which codex` differs.
- Desktop app at `/Applications/Codex.app`, an Electron app whose CLI is embedded at `Contents/Resources/codex` and launched as `codex app-server`.
- A scratch build dir at `~/codex-fork-build` (holds the checkout, `build.log`, `backups/`, `resign-app.sh`).

## Procedure

### 0. Recon (always do first; the layout drifts between app versions)
```
uname -m
which codex && codex --version
file "$(which codex)"
/Applications/Codex.app/Contents/Resources/codex --version          # generation of the bundled CLI
codesign -dv /Applications/Codex.app 2>&1 | grep -E "Identifier|flags|TeamIdentifier"
```
Confirm the fork version is the SAME generation as the bundled CLI (e.g. fork 0.142 vs bundled 0.140). A large mismatch risks an app-server protocol break — warn the user.

### 1. Build from source
```
cd ~ && rm -rf codex-fork-build
git clone --depth 1 --branch <TAG> https://github.com/<OWNER>/<REPO>.git codex-fork-build
cd codex-fork-build/codex-rs
git rev-parse HEAD                                                   # sanity: matches release commit
CARGO_TERM_COLOR=never cargo build --release --bin codex > ~/codex-fork-build/build.log 2>&1
```
The `codex` binary comes from the `codex-cli` crate (`cli/Cargo.toml` has `[[bin]] name = "codex"`). Run the build in the **background** — it pulls forked git deps (crossterm/ratatui/tungstenite) and takes ~15-25 min. Output: `codex-rs/target/release/codex`. Verify `--version`.

### 2. Install the CLI
```
BIN=~/codex-fork-build/codex-rs/target/release/codex
cp -p ~/.local/bin/codex ~/.local/bin/codex.bak-<OLDVER>            # backup once
cp "$BIN" ~/.local/bin/codex && chmod +x ~/.local/bin/codex
codesign --force --sign - ~/.local/bin/codex                        # ad-hoc; arm64 needs a valid sig
~/.local/bin/codex --version
```

### 3. Patch the desktop app
Quit it first (ASK the user — it interrupts any live desktop session):
```
osascript -e 'tell application "Codex" to quit'
# wait for exit; force-kill only if it hangs
```
Swap the embedded binary and move the backup OUT of the bundle (so it isn't sealed in):
```
RES=/Applications/Codex.app/Contents/Resources/codex
mkdir -p ~/codex-fork-build/backups
cp -p "$RES" ~/codex-fork-build/backups/codex.bak-<BUNDLEDVER>
cp "$BIN" "$RES" && chmod +x "$RES"
```

### 4. Re-sign the whole bundle (the critical, finicky step)
Modifying a sealed resource invalidates the app signature → macOS refuses to launch. You must re-sign **inside-out**, ad-hoc, AND strip restricted entitlements.

Two gotchas, both learned the hard way:
- `codesign --deep` alone leaves nested frameworks "modified or invalid". Sign each component explicitly, deepest first.
- **Do NOT preserve `requirements`** (the original pins OpenAI's Team ID → mismatch). Let codesign generate a fresh designated requirement.
- **Strip restricted entitlements** (`com.apple.application-identifier`, `com.apple.developer.team-identifier`, `com.apple.security.application-groups`, `keychain-access-groups`). Ad-hoc signatures carrying these are killed by AMFI at launch with `error 163 / Launchd job spawn failed`. Keep the capability entitlements (jit, camera, mic, network, file access).

Run the bundled script (it enumerates dylibs → standalone helpers → helper .apps → Sparkle internals → resources execs → Codex Framework → plugin → top app, stripping restricted entitlements on each):
```
bash <SKILL_DIR>/resign-app.sh
```
It ends with `codesign --verify --deep --strict /Applications/Codex.app` → expect `VERIFY_OK` and "satisfies its Designated Requirement". The script discovers the Electron framework version dir dynamically (`Versions/Current`), so it survives app updates, but re-check the component list if Apple/OpenAI restructure the bundle.

### 5. Launch & verify (empirical, not assumed)
```
xattr -dr com.apple.quarantine /Applications/Codex.app 2>/dev/null
open -a /Applications/Codex.app
# confirm the MAIN process is alive AND it spawned the fork as app-server:
pgrep -fl "Codex.app/Contents/MacOS/Codex"
pgrep -fl "Codex.app/Contents/Resources/codex app-server"
```
Success = main process stable + a `Resources/codex app-server` child + renderer/GPU helpers up. If the app dies instantly, re-check entitlement stripping and signature validity in Console/`log show`.

## Caveats to tell the user

- **Re-login**: stripping `keychain-access-groups` cuts the app off from the OpenAI keychain group; sign in again if it shows logged out. CLI auth (`~/.codex/auth.json`) is unaffected.
- **Computer-use**: stripping the `CUAService` app-group breaks that IPC; the computer-use feature may not work. Core chat/agent does.
- **Auto-update reverts it**: Sparkle (app) or a CLI reinstall overwrites these with official builds. Re-run build + `resign-app.sh` after any update.

## Restore originals
```
cp ~/.local/bin/codex.bak-<OLDVER> ~/.local/bin/codex
cp ~/codex-fork-build/backups/codex.bak-<BUNDLEDVER> /Applications/Codex.app/Contents/Resources/codex
# then reinstall the app (clean signature) or re-run resign-app.sh
```

# Dotfiles setup

Use the same commands from the repository root or this directory. Account name, home directory, checkout path, and architecture are detected automatically; there are no work/home profiles.

## First setup

```bash
git clone https://github.com/ishandhanani/dotfiles.git ~/dotfiles
cd ~/dotfiles
make install
# Restart your terminal so Nix is on PATH.
make setup-macos    # Skip on Linux.
make apply
```

`make install` installs Determinate Nix if needed. It does not apply configuration. Homebrew is not required or installed.

`make setup-macos` builds the local nix-darwin configuration as your user, then requests sudo to register and activate that built system. It applies keyboard and pointer settings, Caps Lock to Escape, Dock/Finder/appearance settings, Raycast and Spotlight hotkeys, and Chrome extension policy. It then installs missing GUI apps. Run it on a new Mac or after changing `darwin/system.nix`; it does not run Home Manager.

`make apply` builds and activates standalone Home Manager without sudo. Home Manager owns shell/editor configuration, Nix packages, Cursor settings, Ghostty config, and Rectangle preferences and shortcuts. Brev is built from the configured branch in `clis.nix`. The `rust.nix`, `go.nix`, `uvx.nix`, and `agents.nix` modules install missing external tools during user activation, skipping existing installations. The custom agent CLI release remains Linux x86-64 only.

Nix supplies build and installer dependencies, including Go for Brev and uv for Python tools. Vendor installations happen after Home Manager links the dotfiles; a tool installation failure exits nonzero and can leave an activation partially applied. Rerun `make apply` after resolving the failure.

## Daily use

| Command | Behavior |
| --- | --- |
| `make apply` | Apply dotfiles and install missing external tools |
| `make check` | Build Home Manager; also build nix-darwin on macOS; no activation or vendor downloads |
| `make status` | Read-only macOS settings, app configuration, and GUI app checks; exits nonzero on mismatches |
| `make setup-macos` | Reapply system preferences and install missing GUI apps |
| `make update` | Update `home-manager/flake.lock`; run check/apply afterward |
| `make help` | List commands |

The `rebuild` shell alias runs `make apply` from the checkout used for your last application. `edit-home` opens that checkout's `home.nix`. If you move the checkout, run `make apply` from its new location to refresh the aliases.

Nix dependencies are pinned by `flake.lock`. Commands use `--impure` only to read the local identity and checkout supplied by the command wrapper; `make apply`, `make check`, and `make setup-macos` do not update the lock file. External vendor installers download their current release only when a tool or app is missing.

## Brev

The `brev-cli` input in `flake.nix` selects `brevdev/brev-cli` branch `idhanani/feat-brev-ssh-config-env-var`; `flake.lock` pins its published commit. `modules/clis.nix` builds that source with Nix's Go compiler and installs it at `~/.local/bin/brev`. No existing Go installation or local Brev checkout is needed, and there is no fallback to the upstream release installer.

On the first apply, Home Manager backs up an existing regular `~/.local/bin/brev` to `brev.backup` and links the configured build. Later applies reuse the Nix build. Unrelated symlinks and existing backup conflicts need the same manual handling described below. Keep development builds at a separate path; `BREV_CLI_SOURCE_DIR` no longer selects the managed CLI.

`make update` advances the locked inputs, including Brev. To update only Brev, run `nix flake update brev-cli` from `home-manager/`, then `make check` and `make apply`. If the branch's Go dependencies changed, update `vendorHash` in `modules/clis.nix` to the actual hash reported by the failed build; review the dependency change before accepting the new hash.

## GUI apps

`scripts/mac-apps.tsv` lists Google Chrome, iTerm2, Raycast, Rectangle, Cursor, Tailscale, Ghostty, bb, and 1Password. The installer uses public cask metadata to locate vendor downloads and verify published SHA-256 hashes. Apps with explicit `no_check` metadata report that verification is unavailable. Existing bundles in `/Applications` or `~/Applications` are left in place.

```bash
home-manager/scripts/install-mac-apps.sh --list       # Inventory; always succeeds if readable
home-manager/scripts/install-mac-apps.sh --check      # Fails if any tracked app is missing
home-manager/scripts/install-mac-apps.sh --dry-run    # Show missing installs without downloads
```

The installer copies ZIP/DMG app bundles into `/Applications`; PKG installers may request sudo. Temporary downloads and mounted images are cleaned up on exit. App updates remain with the apps' own updaters.

Chrome extensions come from `chrome/extensions.json` and use `normal_installed` policy. Reload `chrome://policy` if Chrome was already running. App sign-in, work SSO, and 1Password authentication remain manual; this setup does not configure a 1Password SSH agent.

## First-run conflicts and migration

Home Manager backs up conflicting regular files with `.backup`. If a backup already exists, preserve or move it before retrying. Home Manager intentionally does not replace unrelated symlinks: if the Nix installer left `~/.profile` pointing to `~/.zprofile`, move that symlink aside before running `make apply` again. Existing Home Manager-owned links are handled automatically.

When migrating from the previous combined nix-darwin/Home Manager setup, run `make setup-macos` and then `make apply`. This removes the system's embedded Home Manager ownership and activates the standalone user configuration.

Some keyboard and pointer preferences take effect after logout or restart. `make status` reports stored settings and selected live state; it cannot verify every app's interactive behavior.

## Editing configuration

- `home.nix`: shared user packages, aliases, and module imports.
- `modules/`: zsh, Bash, Git, SSH, Neovim, Vim, and Mac app configuration.
- `darwin/system.nix`: macOS system settings, independent of Home Manager.
- `modules/clis.nix`: build and install the locked Brev branch; `flake.nix` selects its repository and branch.
- `modules/{agents,uvx,rust,go}.nix`: install missing external tools during user activation.
- `scripts/mac-apps.tsv`: GUI app names, cask metadata tokens, bundles, and archive formats.
- `chrome/extensions.json`: Chrome extension policy.
- `../rectangle/rectangle.json`: Rectangle preferences and shortcuts; values are converted to individual defaults writes so unrelated preferences survive.

To inspect or roll back standalone Home Manager generations, use `home-manager generations` and `home-manager rollback`. System generations remain available through `sudo darwin-rebuild --list-generations` and `sudo darwin-rebuild --rollback`. Vendor installations and macOS preference writes are not transactionally undone by a generation rollback.

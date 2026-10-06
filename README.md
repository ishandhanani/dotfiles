# dotfiles

Personal dotfiles managed with Home Manager and Nix.

```bash
make install        # Install Nix if missing, then restart your terminal
make setup-macos    # macOS settings and missing GUI apps (Mac only)
make apply          # Shell/editor configuration and missing CLI tools
```

Run these commands from the repository root or `home-manager/`. They detect your account and architecture; there is no work/home profile to select.

- `make setup-macos` uses nix-darwin for system settings and a direct-download installer for GUI apps. Run it on a new Mac or when changing system preferences.
- `make apply` uses standalone Home Manager for zsh, Neovim, Git, SSH, Cursor, Ghostty, Rectangle, and CLI tools. The existing Nix modules install missing external tools during activation. This is the normal command after editing dotfiles.
- `make check` builds the configurations without applying them. `make status` checks the live Mac setup. `make update` updates locked Nix dependencies.

See [setup and maintenance](home-manager/README.md) for ownership, first-run conflicts, and verification.

## Agents

Shared agent instructions and skills live in `agents/`. Link them with `./agents/setup.sh`.

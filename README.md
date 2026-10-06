# dotfiles

Personal dotfiles managed with Home Manager and Nix.

## macOS

The macOS setup lives under `home-manager/` and has two layers:

- Home Manager manages the user shell, CLI packages, git/vim/zsh config, Cursor settings, and Rectangle defaults.
- nix-darwin manages system preferences like keyboard repeat, Caps Lock as Escape, dark mode, Dock/Finder settings, trackpad settings, Raycast on Cmd-Space, and disabled Spotlight hotkeys.

Useful commands:

```bash
cd home-manager
make darwin-check
sudo nix run nix-darwin/nix-darwin-25.11#darwin-rebuild -- switch --flake .#work
sudo darwin-rebuild switch --flake .#work
make darwin-status
```

Homebrew and GUI app installs are opt-in. Nix does not own Homebrew in this repo. The app bootstrap covers Google Chrome, iTerm2, Raycast, Rectangle, Cursor, Tailscale, Ghostty, and bb.

```bash
cd home-manager
nix run .#install-homebrew
make darwin-apps-list
make darwin-apps-dry-run
make darwin-apps-install
```

## agents

- shared source: `agents/`
- install both Claude + Codex: `./setup.sh`

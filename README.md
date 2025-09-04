# Dotfiles

Dead simple dotfiles. Just copy what you need.

## Structure

```
.
├── zsh/
│   └── .zshrc
├── bash/
│   └── .bashrc
├── vim/
│   └── .vimrc
├── git/
│   └── .gitconfig
├── ssh/
│   └── (your ssh keys)
├── config/
│   └── (app configs)
├── install.sh      # Simple symlink installer
└── home.nix        # Nix home-manager config
```

## Quick Install

### Option 1: Simple (just symlinks)
```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

### Option 2: Home Manager (Nix)
```bash
# Install Nix and home-manager first
nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.05.tar.gz home-manager
nix-channel --update

# Clone dotfiles
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Apply config
home-manager switch -f home.nix
```

### Option 3: Manual (pick what you want)
```bash
# Just copy what you need
cp dotfiles/zsh/.zshrc ~/.zshrc
cp dotfiles/vim/.vimrc ~/.vimrc
# etc...
```

## What's Included

- **zsh/bash**: Shell configs with git aliases, AI functions (gcai, gprai)
- **vim**: Pre-configured with ALE, auto-save, markdown support
- **git**: Basic gitconfig with useful aliases
- **home.nix**: Full Nix home-manager setup with all tools

## AI Functions

The zsh config includes AI-powered git helpers:
- `gcai` - Generate semantic commit messages
- `gprai` - Generate PR descriptions

Requires `cgpt` to be installed.
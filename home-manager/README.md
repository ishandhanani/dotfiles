# Home Manager Dotfiles Configuration

A fully declarative dotfiles configuration using Nix Home Manager. This manages your entire shell environment, tools, and configurations in a reproducible way.

## Features

- **Fully Declarative**: Your entire zsh configuration is managed in Nix
- **Modular Structure**: Separated into logical modules (zsh, vim, git)
- **AI Functions**: Complex shell functions for git operations using `cgpt`
- **Cross-Platform**: Works on both macOS and Linux
- **Reproducible**: Flake-based for perfect reproducibility
- **Comprehensive**: Includes modern CLI tools, development environments, and more

## Structure

```
home-manager/
├── flake.nix           # Flake definition with inputs and outputs
├── home.nix            # Main configuration file
├── modules/
│   ├── zsh.nix        # Declarative zsh config with aliases
│   ├── vim.nix        # Vim plugins and configuration
│   └── git.nix        # Git aliases and settings
└── functions/
    └── ai-functions.zsh # Complex AI shell functions
```

## Installation

### Prerequisites

**Install Nix** (if not already installed) — use the Determinate installer, which enables flakes by default and has a clean uninstaller:
```bash
# macOS/Linux
curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm

# After installation, restart your terminal
```

### Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles/home-manager

# Pick the flake target matching this machine (see flake.nix homeConfigurations):
#   work        idhanani@macbook
#   home        ishandhanani@macbook
#   brev-vm     ubuntu@linux x86_64
#   brev-vm-arm ubuntu@linux aarch64
#   brev-vm-gpu nvidia@linux
#   simbox      ishan@linux

# Apply the configuration
nix run home-manager/master -- switch --flake .#work -b backup

# Or use the Makefile shortcuts: make work | make home | make vm | make vm-arm
```

### Alternative: Using nix-darwin (macOS only)

For system-wide macOS configuration:

```bash
# Install nix-darwin
nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer
./result/bin/darwin-installer

# Apply both system and home configuration
darwin-rebuild switch --flake .#macbook
```

## Usage

### Daily Operations

```bash
# Rebuild after changes (substitute your flake target: work, home, brev-vm, ...)
home-manager switch --flake .#work

# Or use the alias (after first install)
rebuild

# Edit configuration
edit-home  # Opens home.nix in your editor

# Update all inputs
nix flake update
```

### AI Functions

The configuration includes AI-powered git helpers:

```bash
# Generate semantic commit messages
git add .
gcai  # Will generate and propose a commit message

# Generate PR descriptions
gprai  # Analyzes branch changes and creates PR description

# Explain commands
explain ls -la

# Fix errors
command_that_fails 2>&1 | fixerr
```

### Shell Features

All shell aliases and functions are declaratively managed:

- **Git aliases**: `gs`, `ga`, `gc`, `gp`, etc.
- **Navigation**: `godesk`, `godown`
- **Better tools**: `ls` → `eza`, `cat` → `bat`, `grep` → `ripgrep`
- **Docker/Kubernetes**: `d`, `dc`, `k`

## Customization

### Adding Packages

Edit `home.nix`:
```nix
home.packages = with pkgs; [
  # Add your packages here
  neovim
  tmux
];
```

### Adding Shell Aliases

Edit `modules/zsh.nix`:
```nix
shellAliases = {
  # Add your aliases
  myalias = "my command";
};
```

### Adding Vim Plugins

Edit `modules/vim.nix`:
```nix
plugins = with pkgs.vimPlugins; [
  # Add plugins
  vim-fugitive
];
```

### Platform-Specific Configuration

The configuration automatically detects your platform:
```nix
] ++ lib.optionals isDarwin [
  # macOS only packages
] ++ lib.optionals isLinux [
  # Linux only packages
];
```

## Migrating from Traditional Dotfiles

### Before (traditional dotfiles)
- Edit `.zshrc` directly
- Manually install tools
- Copy files between machines
- Inconsistent environments

### After (Home Manager)
- Edit `modules/zsh.nix`
- Packages installed declaratively
- Single command to reproduce
- Identical environment everywhere

### Migration Tips

1. **Start Simple**: Don't try to migrate everything at once
2. **Keep Backups**: Your old dotfiles are backed up automatically
3. **Test First**: Use `home-manager build` to test without applying
4. **Gradual Migration**: Start with basic configs, add complexity over time

## Troubleshooting

### Common Issues

1. **"Command not found: home-manager"**
   ```bash
   nix-shell -p home-manager --run "home-manager switch --flake .#work"
   ```

2. **"Attribute not found"**
   - Check the flake target matches a `homeConfigurations` output in `flake.nix`
   - Ensure system architecture is correct (aarch64-darwin for Apple Silicon)

3. **"Permission denied"**
   ```bash
   # Restart the Nix daemon (Determinate Nix)
   sudo launchctl kickstart -k system/org.nixos.nix-daemon
   ```

4. **Conflicts with existing files**
   ```bash
   # home-manager switch already handles this with -b backup
   home-manager switch --flake .#work -b backup
   ```

## Benefits of This Approach

1. **Reproducibility**: Exact same environment on every machine
2. **Rollback**: Easy to revert to previous configurations
3. **Version Control**: All changes tracked in git
4. **Declarative**: Describe what you want, not how to get it
5. **Modular**: Organize configuration logically
6. **Cross-Platform**: Same config works on macOS and Linux
7. **No Side Effects**: Changes are atomic and reversible

## Advanced Features

### Using the Flake

```bash
# Build without switching
nix build .#homeConfigurations.work.activationPackage

# Enter a shell with your configuration
nix develop

# Update specific input
nix flake lock --update-input nixpkgs
```

### Creating Machine-Specific Configs

Add new configurations in `flake.nix`:
```nix
"ishandhanani@laptop" = mkHomeConfiguration system [
  ./home.nix
  ./machines/laptop.nix  # Machine-specific overrides
];
```

## Resources

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [Nixpkgs Search](https://search.nixos.org/packages)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.html)

## License

MIT - Feel free to use and modify
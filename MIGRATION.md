# Migration Guide: From Traditional Dotfiles to Home Manager

## Understanding the Difference

### Traditional Dotfiles
- You maintain actual files (`.zshrc`, `.vimrc`, etc.)
- You copy/symlink them to your home directory
- You manually install tools
- Each machine might have slight differences

### Home Manager
- You write Nix configurations
- Home Manager generates the dotfiles for you
- Tools are installed automatically
- Every machine is identical

## Migration Steps

### Step 1: Backup Your Current Dotfiles

```bash
# Create a backup
mkdir ~/dotfiles-backup
cp ~/.zshrc ~/dotfiles-backup/
cp ~/.vimrc ~/dotfiles-backup/
cp ~/.gitconfig ~/dotfiles-backup/
```

### Step 2: Extract Your Settings

#### From `.zshrc` → `modules/zsh.nix`

**Aliases:**
```bash
# Old (.zshrc)
alias ll="ls -la"
alias gs="git status"
```

```nix
# New (modules/zsh.nix)
shellAliases = {
  ll = "ls -la";
  gs = "git status";
};
```

**Environment Variables:**
```bash
# Old (.zshrc)
export EDITOR="vim"
export PATH="$HOME/bin:$PATH"
```

```nix
# New (modules/zsh.nix)
sessionVariables = {
  EDITOR = "vim";
};
initExtraFirst = ''
  export PATH="$HOME/bin:$PATH"
'';
```

**Functions:**
```bash
# Old (.zshrc)
function mkcd() {
  mkdir -p "$1" && cd "$1"
}
```

```nix
# New (modules/zsh.nix)
initExtra = ''
  mkcd() {
    mkdir -p "$1" && cd "$1"
  }
'';
```

#### From `.vimrc` → `modules/vim.nix`

**Settings:**
```vim
" Old (.vimrc)
set number
set expandtab
set tabstop=4
```

```nix
# New (modules/vim.nix)
settings = {
  number = true;
  expandtab = true;
  tabstop = 4;
};
```

**Plugins:**
```vim
" Old (.vimrc with vim-plug)
call plug#begin()
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'
call plug#end()
```

```nix
# New (modules/vim.nix)
plugins = with pkgs.vimPlugins; [
  vim-fugitive
  vim-gitgutter
];
```

#### From `.gitconfig` → `modules/git.nix`

**User Info:**
```ini
# Old (.gitconfig)
[user]
    name = John Doe
    email = john@example.com
```

```nix
# New (modules/git.nix)
userName = "John Doe";
userEmail = "john@example.com";
```

**Aliases:**
```ini
# Old (.gitconfig)
[alias]
    st = status
    co = checkout
```

```nix
# New (modules/git.nix)
aliases = {
  st = "status";
  co = "checkout";
};
```

### Step 3: Tools You Manually Installed

List your tools:
```bash
# Check what you have installed
which rg fd bat eza  # Modern CLI tools
which node go rustc  # Development tools
```

Add them to `home.nix`:
```nix
home.packages = with pkgs; [
  ripgrep
  fd
  bat
  eza
  nodejs
  go
  rustup
];
```

### Step 4: Complex Configurations

For complex shell functions or scripts that don't translate well to Nix:

1. Create a file in `functions/`:
```bash
# functions/my-complex-functions.zsh
function complex_function() {
  # Your complex logic here
}
```

2. Source it in `modules/zsh.nix`:
```nix
initExtra = ''
  source ${../functions/my-complex-functions.zsh}
'';
```

### Step 5: Test Your Configuration

```bash
# Build without switching (safe)
cd ~/dotfiles/home-manager
nix build .#homeConfigurations.$USER@macbook.activationPackage

# If successful, apply it
home-manager switch --flake .#$USER@macbook
```

### Step 6: Verify Everything Works

```bash
# Check your aliases
alias | grep your-alias

# Check your functions
type your-function

# Check installed tools
which rg fd bat

# Test vim plugins
vim -c "PlugStatus"
```

## Common Patterns

### Oh My Zsh → Native Zsh

```nix
# Instead of Oh My Zsh plugins
programs.zsh = {
  # Built-in replacements
  enableCompletion = true;  # Replaces completions plugin
  autosuggestion.enable = true;  # Replaces zsh-autosuggestions
  syntaxHighlighting.enable = true;  # Replaces zsh-syntax-highlighting
  
  # For other plugins
  plugins = [
    {
      name = "zsh-z";
      src = pkgs.zsh-z;
      file = "share/zsh-z/zsh-z.plugin.zsh";
    }
  ];
};
```

### Homebrew → Nix Packages

```bash
# Find Nix equivalents
nix search nixpkgs package-name

# Example migrations:
# brew install ripgrep → ripgrep
# brew install bat → bat  
# brew install exa → eza (exa is now eza)
# brew install --cask cursor → not in nixpkgs (keep using brew)
```

### Platform-Specific Code

```nix
# In any module
let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  # Platform-specific aliases
  shellAliases = {
    # Common aliases
  } // lib.optionalAttrs isDarwin {
    # macOS only
    showfiles = "defaults write com.apple.finder AppleShowAllFiles -bool true";
  } // lib.optionalAttrs isLinux {
    # Linux only  
    pbcopy = "xclip -selection clipboard";
  };
}
```

## Troubleshooting

### "I made changes but they're not showing up"
- Did you run `home-manager switch`?
- Check `home-manager generations` to see what's active

### "My shell is slow to start"
- Move complex operations to functions that are called on-demand
- Use `initExtraFirst` for critical PATH setup
- Profile with `zsh -xv` to find slow parts

### "A tool isn't available"
- Search for it: `nix search nixpkgs tool-name`
- Not in nixpkgs? Keep using your system package manager for now
- Or package it yourself (advanced)

### "I want to go back"
- Your backups are in `~/dotfiles-backup-*`
- Run `home-manager generations` to see previous versions
- Rollback: `home-manager rollback`

## Tips

1. **Start Simple**: Migrate basic aliases and settings first
2. **Test Often**: Use `nix build` before `home-manager switch`
3. **Keep Notes**: Document what doesn't translate directly
4. **Use the REPL**: `nix repl` to test expressions
5. **Read the Docs**: Home Manager has excellent documentation

## Need Help?

- [Home Manager Options Search](https://mipmip.github.io/home-manager-option-search/)
- [Nix Package Search](https://search.nixos.org/packages)
- [Example Configurations](https://github.com/topics/home-manager-config)
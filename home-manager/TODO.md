# Future Enhancements

Once you're comfortable with the basic setup, consider adding these tools and features:

## Modern CLI Tools
```nix
# In home.nix, add to home.packages:
ripgrep    # Better grep
fd         # Better find  
bat        # Better cat with syntax highlighting
eza        # Better ls with icons
bottom     # Better top
jq         # JSON processor
```

Then update your aliases in `modules/zsh.nix`:
```nix
shellAliases = {
  cat = "bat --style=plain";
  ls = "eza --color=always --group-directories-first";
  ll = "eza -la --color=always --group-directories-first";
  grep = "rg";
  find = "fd";
};
```

## Enhanced Shell Experience
```nix
# In modules/zsh.nix, add:
programs.starship = {
  enable = true;
  enableZshIntegration = true;
  # Custom prompt configuration
};

programs.atuin = {
  enable = true;
  enableZshIntegration = true;
  # Better shell history
};

programs.zoxide = {
  enable = true;
  enableZshIntegration = true;
  # Smarter cd command
};
```

## Fuzzy Finding
```nix
# In home.nix, add:
programs.fzf = {
  enable = true;
  enableZshIntegration = true;
  defaultCommand = "fd --type f";
};
```

## Tmux Configuration
```nix
programs.tmux = {
  enable = true;
  terminal = "screen-256color";
  keyMode = "vi";
  mouse = true;
  # Add your tmux configuration
};
```

## Git Enhancements
```nix
# In modules/git.nix, add:
programs.git.delta = {
  enable = true;  # Better git diffs
  options = {
    navigate = true;
    line-numbers = true;
  };
};

programs.gh = {
  enable = true;  # GitHub CLI
  settings = {
    git_protocol = "ssh";
  };
};
```

## Development Tools
```nix
# Add language-specific tools as needed:
home.packages = with pkgs; [
  # Languages
  go
  rustup
  nodejs
  python3
  
  # LSPs and formatters
  gopls
  rust-analyzer
  nodePackages.typescript-language-server
  nodePackages.prettier
  black
  ruff
];
```

## Vim/Neovim Upgrade
Consider switching to Neovim for better plugin ecosystem:
```nix
programs.neovim = {
  enable = true;
  viAlias = true;
  vimAlias = true;
  
  plugins = with pkgs.vimPlugins; [
    nvim-lspconfig
    nvim-cmp
    telescope-nvim
    nvim-treesitter.withAllGrammars
  ];
};
```

## Directory-Specific Environments
```nix
programs.direnv = {
  enable = true;
  enableZshIntegration = true;
  nix-direnv.enable = true;
};
```

## SSH Configuration
```nix
programs.ssh = {
  enable = true;
  matchBlocks = {
    "myserver" = {
      hostname = "server.example.com";
      user = "myuser";
      identityFile = "~/.ssh/id_ed25519";
    };
  };
};
```

## Platform-Specific Tools

### macOS
```nix
home.packages = lib.optionals isDarwin [
  mas  # Mac App Store CLI
  rectangle  # Window manager
];
```

### Linux
```nix
home.packages = lib.optionals isLinux [
  xclip  # Clipboard support
  firefox
];
```

## Gradual Migration Strategy

1. **Start small**: Get comfortable with the basic setup first
2. **Add one tool at a time**: Test each addition thoroughly
3. **Learn the Nix way**: Understand how each tool is configured in Nix
4. **Keep notes**: Document what works for your workflow
5. **Rollback if needed**: `home-manager generations` and `home-manager rollback`

## Resources

- [Home Manager Options](https://nix-community.github.io/home-manager/options.html)
- [Nix Package Search](https://search.nixos.org)
- [Awesome Nix](https://github.com/nix-community/awesome-nix)
- [Home Manager Examples](https://github.com/nix-community/home-manager/tree/master/tests)
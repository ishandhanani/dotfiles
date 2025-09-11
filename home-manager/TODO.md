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

## Resources

- [Home Manager Options](https://nix-community.github.io/home-manager/options.html)
- [Nix Package Search](https://search.nixos.org)
- [Awesome Nix](https://github.com/nix-community/awesome-nix)
- [Home Manager Examples](https://github.com/nix-community/home-manager/tree/master/tests)

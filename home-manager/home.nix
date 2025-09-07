{ config, pkgs, lib, ... }:

{
  # Basic information about you and your system
  home = {
    username = "ishandhanani";  # Update with your username
    homeDirectory = "/Users/ishandhanani";
    
    # This value determines the Home Manager release that your
    # configuration is compatible with. This helps avoid breakage
    # when a new Home Manager release introduces backwards incompatible changes.
    # Don't change this value unless you know what you're doing.
    stateVersion = "24.05";  # Please read the comment before changing.
    
    # Global shell aliases available to all shells
    shellAliases = {
      # Quick edits
      edit-home = "$EDITOR ~/.config/home-manager/home.nix";
      rebuild = "home-manager switch";
    };
    
    # Session path additions
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/go/bin"
    ];
  };
  
  # Import modular configurations
  imports = [
    ./modules/zsh.nix
    ./modules/vim.nix
    ./modules/git.nix
    ./modules/uvx.nix
  ];
  
  # Minimal packages - just the essentials
  home.packages = with pkgs; [
    gh
    delta
    curl
    wget
    git
    uv 
    ruff
    yq
    ripgrep
    starship
    jq
    fzf
    eza
    bat
    zoxide
    zellij
    fd
    yazi
    gh-dash
  ];
  
  # Additional program configurations can be added here later
  
  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  
  # Fonts configuration (macOS doesn't need fontconfig)
  fonts.fontconfig.enable = false;
  
  # News - notify about home-manager news
  news.display = "silent";
  
  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };
}
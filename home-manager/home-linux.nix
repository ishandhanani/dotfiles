{ config, pkgs, lib, ... }:

{
  # Basic information about you and your system
  home = {
    username = "ishandhanani";  # Update with your username
    homeDirectory = "/home/ishandhanani";
    
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
  
  # Import modular configurations (Linux-specific)
  imports = [
    ./modules/bash.nix
    ./modules/vim.nix
    ./modules/git.nix
  ];
  
  # Minimal packages - just the essentials (no uv for Linux)
  home.packages = with pkgs; [
    gh
    delta
    curl
    wget
    git
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
  ];
  
  # Additional program configurations can be added here later
  
  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  
  # Fonts configuration (Linux)
  fonts.fontconfig.enable = true;
  
  # News - notify about home-manager news
  news.display = "silent";
  
  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };
}

{ config, pkgs, lib, user, homeDirectory, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  # Basic information about you and your system - dynamic detection
  home = {
    username = user;
    homeDirectory = homeDirectory;
    
    stateVersion = "24.05";
    
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
  
  # Import modular configurations - conditional based on platform
  imports = [
    ./modules/vim.nix
    ./modules/git.nix
    ./modules/zsh.nix
    ./modules/uvx.nix
    ./modules/bash.nix
    ./modules/ssh.nix
  ];
  
  # Unified packages with platform-specific additions
  home.packages = with pkgs; [
    # Core packages for all platforms
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
    uv
    gh-dash
    gh-notify
    sccache
    nvtop
  ];
  
  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  
  # Platform-specific font configuration
  fonts.fontconfig.enable = isLinux;
  
  # News - notify about home-manager news
  news.display = "silent";
  
  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };
}
{ config, pkgs, lib, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  # Basic information about you and your system
  home = {
    username = "ishandhanani";  # Update with your username
    homeDirectory = if isDarwin then "/Users/ishandhanani" else "/home/ishandhanani";
    
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
    
    # Global session variables
    sessionVariables = {
      EDITOR = "vim";
      BROWSER = if isDarwin then "open" else "firefox";
      PAGER = "less";
      # Development
      GOPATH = "$HOME/go";
      
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
  ];
  
  # Minimal packages - just the essentials
  home.packages = with pkgs; [
    # Core tools
    curl
    wget
    git
    vim
    
    # Development basics (uncomment if you need them)
    # go
    # nodejs
    # python3
  ];
  
  # Additional program configurations can be added here later
  
  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  
  # Fonts configuration (macOS specific)
  fonts.fontconfig.enable = lib.mkDefault pkgs.stdenv.isLinux;
  
  # News - notify about home-manager news
  news.display = "silent";
  
  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };
}
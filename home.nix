{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "ishandhanani";
  home.homeDirectory = "/Users/ishandhanani";

  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # Packages to install
  home.packages = with pkgs; [
    # Tools
    bat
    eza
    atuin
    starship
    ripgrep
    fd
    jq
    yq
    bottom
    
    # Development
    go
    rustup
    nodejs
    python3
    
    # Git
    git
    gh
  ];

  # Dotfiles
  home.file = {
    ".zshrc".source = ./zsh/.zshrc;
    ".bashrc".source = ./bash/.bashrc;
    ".vimrc".source = ./vim/.vimrc;
    ".gitconfig".source = ./git/.gitconfig;
  };

  # SSH keys (if they exist)
  home.file.".ssh" = {
    source = ./ssh;
    recursive = true;
  };

  # Program configurations
  programs.home-manager.enable = true;
  
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
  };
  
  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      ale
      vim-auto-save
      tabular
      vim-markdown
    ];
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };
}
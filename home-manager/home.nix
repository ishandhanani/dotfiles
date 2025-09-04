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
      
      # System info
      sysinfo = "nix-shell -p neofetch --run neofetch";
    };
    
    # Global session variables
    sessionVariables = {
      EDITOR = "vim";
      BROWSER = if isDarwin then "open" else "firefox";
      PAGER = "less";
      LESS = "-R";
      
      # Development
      GOPATH = "$HOME/go";
      
      # XDG Base directories
      XDG_CONFIG_HOME = "$HOME/.config";
      XDG_DATA_HOME = "$HOME/.local/share";
      XDG_CACHE_HOME = "$HOME/.cache";
    };
    
    # Session path additions
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/go/bin"
      "$HOME/.cargo/bin"
    ];
  };
  
  # Import modular configurations
  imports = [
    ./modules/zsh.nix
    ./modules/vim.nix
    ./modules/git.nix
  ];
  
  # Packages to install
  home.packages = with pkgs; [
    # Core tools
    coreutils
    curl
    wget
    tree
    htop
    ncdu
    
    # Modern CLI tools
    ripgrep        # Better grep
    fd             # Better find
    bat            # Better cat
    eza            # Better ls
    bottom         # Better top
    du-dust        # Better du
    procs          # Better ps
    sd             # Better sed
    tokei          # Code statistics
    hyperfine      # Benchmarking
    
    # Development tools
    git
    gh             # GitHub CLI
    jq             # JSON processor
    yq             # YAML processor
    httpie         # Better curl for APIs
    
    # Languages and runtimes
    go
    rustup
    nodejs_20
    python3
    
    # Container tools
    docker
    docker-compose
    
    # Text processing
    pandoc
    graphviz
    
    # Network tools
    nmap
    mtr
    speedtest-cli
    
    # Archive tools
    unzip
    p7zip
    
    # Fun stuff
    cowsay
    fortune
    lolcat
    
    # Platform-specific packages
  ] ++ lib.optionals isDarwin [
    # macOS specific tools
    mas           # Mac App Store CLI
    darwin.trash  # Move files to trash
  ] ++ lib.optionals isLinux [
    # Linux specific tools
    xclip         # Clipboard support
    wl-clipboard  # Wayland clipboard
  ];
  
  # Program configurations not in modules
  
  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
  
  # Fzf for fuzzy finding
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
    ];
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetOptions = [
      "--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
    ];
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
  };
  
  # Bat configuration
  programs.bat = {
    enable = true;
    config = {
      theme = "gruvbox-dark";
      style = "numbers,changes,header";
    };
  };
  
  # Eza configuration
  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    git = true;
    icons = true;
  };
  
  # Zoxide - smarter cd command
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
  
  # Tmux configuration
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;
    
    extraConfig = ''
      # Better prefix key
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix
      
      # Split panes using | and -
      bind | split-window -h
      bind - split-window -v
      unbind '"'
      unbind %
      
      # Reload config
      bind r source-file ~/.tmux.conf
      
      # Fast pane switching
      bind -n M-h select-pane -L
      bind -n M-l select-pane -R
      bind -n M-k select-pane -U
      bind -n M-j select-pane -D
      
      # Status bar
      set -g status-bg black
      set -g status-fg white
      set -g status-left '#[fg=green]#S '
      set -g status-right '#[fg=yellow]#(uptime | cut -d "," -f 1)'
    '';
  };
  
  # SSH configuration
  programs.ssh = {
    enable = true;
    compression = true;
    controlMaster = "auto";
    controlPath = "~/.ssh/master-%r@%h:%p";
    controlPersist = "10m";
    
    matchBlocks = {
      # Example SSH config
      # "myserver" = {
      #   hostname = "server.example.com";
      #   user = "myuser";
      #   port = 22;
      #   identityFile = "~/.ssh/id_ed25519";
      # };
    };
  };
  
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
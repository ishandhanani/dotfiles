{ config, pkgs, lib, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    # History configuration
    history = {
      size = 10000;
      save = 20000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      extended = true;
    };
    
    # Environment variables
    sessionVariables = {
      EDITOR = "vim";
      VISUAL = "vim";
      GPG_TTY = "$(tty)";
    };
    
    # Path additions
    initExtraFirst = ''
      # Add to PATH early
      export PATH="$HOME/go/bin:$PATH"
      export PATH="$HOME/.local/bin:$PATH"
    '';
    
    # Shell aliases - declaratively managed
    shellAliases = {
      # Git shortcuts
      ga = "git add";
      gc = "git commit";
      gps = "git push";
      gs = "git status";
      gpl = "git pull";
      gf = "git fetch";
      gcb = "git checkout -b";
      gp = "git push";
      gll = "git log";
      
      # Shell management
      editz = "vim ~/.config/home-manager/home.nix";
      sourcez = "source ~/.zshrc";
      reload = "home-manager switch";
      
      # Navigation
      v = "vim .";
      ll = "ls -alh";
      d = "docker";
      dc = "docker compose";
      k = "kubectl";
      m = "make";
      c = "cursor .";
      speed = "speedtest";
      
      # Better defaults with installed tools
      cat = "bat --style=plain";
      ls = "eza --color=always --group-directories-first";
      ll = "eza -la --color=always --group-directories-first";
      ltree = "eza --tree --level=3 --color=always";
      
      # Networking
      myip = "curl -s icanhazip.com";
      
      # Brev
      brs = "brev refresh && brev ls";
      
      # Platform-specific navigation
    } // lib.optionalAttrs isDarwin {
      godesk = "cd ~/Desktop";
      godown = "cd ~/Downloads";
    } // lib.optionalAttrs isLinux {
      godesk = "cd ~/Desktop";
      godown = "cd ~/Downloads";
      pbcopy = "xclip -selection clipboard";
      pbpaste = "xclip -selection clipboard -o";
    };
    
    # Zsh-specific configuration
    initExtra = ''
      # Load edit-command-line widget
      autoload -Uz edit-command-line
      zle -N edit-command-line
      bindkey '^X^E' edit-command-line
      
      # Source external env if exists
      [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
      
      # Source AI functions (complex functions that need special handling)
      source ${../functions/ai-functions.zsh}
      
      # Simple inline functions
      mkcd() {
        mkdir -p "$1" && cd "$1"
      }
      
      # Platform-specific configurations
      ${lib.optionalString isDarwin ''
        # macOS specific settings
        export HOMEBREW_PREFIX="/opt/homebrew"
        [ -d "$HOMEBREW_PREFIX" ] && export PATH="$HOMEBREW_PREFIX/bin:$PATH"
        
        # iTerm2 integration if available
        test -e "''${HOME}/.iterm2_shell_integration.zsh" && source "''${HOME}/.iterm2_shell_integration.zsh"
      ''}
      
      ${lib.optionalString isLinux ''
        # Linux specific settings
        export XDG_SESSION_TYPE="wayland"  # or x11 based on your setup
      ''}
    '';
    
    # Oh My Zsh (optional, can be removed if you prefer manual plugin management)
    oh-my-zsh = {
      enable = false;  # Set to true if you want Oh My Zsh
      plugins = [ "git" "z" "docker" "kubectl" ];
      theme = "robbyrussell";
    };
    
    # Manual plugin management (if not using Oh My Zsh)
    plugins = [
      {
        name = "zsh-z";
        src = pkgs.zsh-z;
        file = "share/zsh-z/zsh-z.plugin.zsh";
      }
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.zsh-syntax-highlighting;
        file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      }
    ];
  };
  
  # Atuin for better shell history
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      search_mode = "fuzzy";
      style = "compact";
    };
  };
  
  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = true;
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      git_branch = {
        symbol = " ";
      };
      git_status = {
        ahead = "⇡\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        behind = "⇣\${count}";
      };
    };
  };
}
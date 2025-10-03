{ config, pkgs, lib, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    
    # Basic history configuration  
    history = {
      size = 10000;
      save = 20000;
      ignoreDups = true;
      share = true;
    };
    
    # Environment variables
    sessionVariables = {
      EDITOR = "vim";
      VISUAL = "vim";
    };
    
    # Shell aliases - just the basics
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
      gd = "git diff";

      # Quick navigation
      godesk = "cd ~/Desktop";
      gorepo = "cd ~/Documents/repos";
      
      # Basic aliases
      v = "vim .";
      d = "docker";
      dc = "docker compose";
      k = "kubectl";
      m = "make";
      c = "cursor .";

      # Tool aliases
      cat = "bat --style=plain --paging=never";
      ls = "eza --color=always --group-directories-first";
      ll = "eza -la --color=always --group-directories-first";
      
      # Networking
      myip = "curl -s icanhazip.com";

      # venv
      venv = "source .venv/bin/activate";
    };
    
    # Zsh-specific configuration
    initContent = lib.mkMerge [
      # PATH setup (needs to be early)
      (lib.mkBefore ''
        # Add to PATH early
        export GPG_TTY="$(tty)"
        export PATH="$HOME/go/bin:$PATH"
        export PATH="$HOME/.local/bin:$PATH"
      '')
      
      # Main configuration
      ''
        # Load edit-command-line widget
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey '^X^E' edit-command-line
        bindkey "^[b" backward-word
        bindkey "^[f" forward-word
        
        # Source external env if exists
        [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
        
        # Source Cargo environment if it exists
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

        # Add yazi q alias to switch cwd
        # based on https://yazi-rs.github.io/docs/quick-start#shell-wrapper
        function y() {
          local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
          yazi "$@" --cwd-file="$tmp"
          IFS= read -r -d $'\0' cwd ${"<"} "$tmp"
          [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
          rm -f -- "$tmp"
        }
        
        # Source AI functions
        source ${../functions/ai-functions.sh} > /dev/null 2>&1
      ''
    ];
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };
}
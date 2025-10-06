{ config, pkgs, lib, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    
    # Basic history configuration  
    historySize = 10000;
    historyFileSize = 20000;
    historyControl = [ "ignoredups" ];
    
    # Environment variables
    sessionVariables = {
      EDITOR = "vim";
      VISUAL = "vim";
      RUSTC_WRAPPER = "sccache";
    };
    
    # Shell aliases - same as zsh
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
      gco = "git checkout";

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
    
    # Bash-specific configuration
    initExtra = ''
      # PATH setup
      export GPG_TTY="$(tty)"
      export PATH="$HOME/go/bin:$PATH"
      export PATH="$HOME/.local/bin:$PATH"
      
      # Source external env if exists
      [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
      
      # Source Cargo environment if it exists
      [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

      # Add yazi q alias to switch cwd
      function y() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
        yazi "$@" --cwd-file="$tmp"
        IFS= read -r -d $'\0' cwd < "$tmp"
        [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
        rm -f -- "$tmp"
      }
      
      # Source AI functions (bash version)
      source ${../functions/ai-functions.sh} > /dev/null 2>&1 || true
    '';
  };

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
  };
}
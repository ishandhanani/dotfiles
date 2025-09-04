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
      
      # Shell management
      editz = "vim ~/.zshrc";
      sourcez = "source ~/.zshrc";
      
      # Basic aliases
      v = "vim .";
      ll = "ls -alh";
      d = "docker";
      dc = "docker compose";
      k = "kubectl";
      m = "make";
      c = "cursor .";
      
      # Networking
      myip = "curl -s icanhazip.com";
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
        
        # Source external env if exists
        [ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
        
        # Source AI functions
        source ${../functions/ai-functions.zsh} > /dev/null 2>&1
      ''
    ];
  };
}
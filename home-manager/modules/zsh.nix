{ config, pkgs, lib, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    # Use cached compinit - only regenerate once per day
    completionInit = ''
      autoload -Uz compinit
      if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
        compinit
      else
        compinit -C
      fi
    '';

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
      RUSTC_WRAPPER = "sccache";
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
      gll = "git log --oneline";
      gd = "git diff";
      gco = "git checkout";

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

      # ai 
      ai = "y-cli chat";

      # Tool aliases
      cat = "bat --style=plain --paging=never";
      l = "eza --color=always --group-directories-first";
      ll = "eza -la --color=always --group-directories-first";
      lt = "eza --tree";
      
      # Networking
      myip = "curl -s icanhazip.com";

      # venv
      venv = "source .venv/bin/activate";
    };
    
    # Zsh-specific configuration
    initContent = lib.mkMerge [
      # Early setup (PATH is handled by sessionPath in home.nix)
      (lib.mkBefore ''
        export GPG_TTY="$(tty)"
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
        
        # Lazy-load AI functions for faster shell startup
        _ai_functions_loaded=0
        _load_ai_functions() {
          if [ "$_ai_functions_loaded" -eq 0 ]; then
            source ${../functions/ai-functions.sh} > /dev/null 2>&1
            _ai_functions_loaded=1
          fi
        }

        # Create lazy-loading wrappers for AI commands
        gcai() {
          _load_ai_functions
          git_ai_commit "$@"
        }

        gprai() {
          _load_ai_functions
          gprai "$@"
        }

        # Source local machine-specific configs 
        [ -f "$HOME/.zshrc.local" ] && . "$HOME/.zshrc.local"
      ''
    ];
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      command_timeout = 500;
      aws.disabled = true;
      gcloud.disabled = true;
      git_status.disabled = true;
    };
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };
}

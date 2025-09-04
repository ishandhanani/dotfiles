{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    
    # User information
    userName = "Ishan Dhanani";  # Update with your name
    userEmail = "your.email@example.com";  # Update with your email
    
    # Core settings
    extraConfig = {
      core = {
        editor = "vim";
        autocrlf = "input";
        whitespace = "trailing-space,space-before-tab";
      };
      
      init = {
        defaultBranch = "main";
      };
      
      pull = {
        rebase = false;  # Set to true if you prefer rebase
        ff = "only";
      };
      
      push = {
        default = "simple";
        autoSetupRemote = true;
      };
      
      merge = {
        tool = "vimdiff";
        conflictstyle = "diff3";
      };
      
      diff = {
        tool = "vimdiff";
        colorMoved = "default";
      };
      
      rerere = {
        enabled = true;
        autoUpdate = true;
      };
      
      color = {
        ui = "auto";
        branch = "auto";
        diff = "auto";
        status = "auto";
      };
      
      # Better diff output
      "color \"diff\"" = {
        meta = "yellow";
        frag = "magenta bold";
        old = "red bold";
        new = "green bold";
        whitespace = "red reverse";
      };
      
      # URL shortcuts
      "url \"git@github.com:\"" = {
        insteadOf = "gh:";
      };
      
      "url \"git@gitlab.com:\"" = {
        insteadOf = "gl:";
      };
    };
    
    # Git aliases - declaratively managed
    aliases = {
      # Status and info
      st = "status -sb";
      s = "status -s";
      
      # Branches
      br = "branch -vv";
      bra = "branch -vva";
      branches = "branch -a";
      
      # Checkout
      co = "checkout";
      cob = "checkout -b";
      
      # Commits
      ci = "commit";
      cm = "commit -m";
      ca = "commit --amend";
      can = "commit --amend --no-edit";
      
      # Diff
      d = "diff";
      dc = "diff --cached";
      ds = "diff --stat";
      
      # Logging
      l = "log --oneline --graph --decorate";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      ll = "log --pretty=format:'%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]' --decorate --numstat";
      last = "log -1 HEAD --stat";
      
      # Working with remotes
      f = "fetch";
      fa = "fetch --all --prune";
      pl = "pull";
      ps = "push";
      psu = "push -u origin HEAD";
      
      # Reset and clean
      unstage = "reset HEAD --";
      uncommit = "reset --soft HEAD~1";
      discard = "checkout --";
      
      # Stash
      ss = "stash save";
      sl = "stash list";
      sp = "stash pop";
      sa = "stash apply";
      
      # Working with history
      undo = "reset --soft HEAD~1";
      redo = "reset 'HEAD@{1}'";
      
      # Show useful info
      contributors = "shortlog --summary --numbered";
      aliases = "config --get-regexp alias";
      
      # Find things
      find-merge = "!sh -c 'commit=$0 && branch=\${1:-HEAD} && (git rev-list $commit..$branch --ancestry-path | cat -n; git rev-list $commit..$branch --first-parent | cat -n) | sort -k2 -s | uniq -f1 -d | sort -n | tail -1 | cut -f2'";
      find-branch = "!f() { git branch -a --contains $1; }; f";
      find-tag = "!f() { git describe --always --contains $1; }; f";
      
      # Cleanup
      cleanup = "!git branch --merged | grep -v '\\*\\|main\\|master\\|develop' | xargs -n 1 git branch -d";
      prune-branches = "!git remote prune origin && git branch -vv | grep ': gone]' | awk '{print $1}' | xargs -r git branch -D";
    };
    
    # Git ignore patterns
    ignores = [
      # OS generated files
      ".DS_Store"
      ".DS_Store?"
      "._*"
      ".Spotlight-V100"
      ".Trashes"
      "Thumbs.db"
      "ehthumbs.db"
      
      # Editor files
      "*.swp"
      "*.swo"
      "*~"
      ".idea/"
      ".vscode/"
      "*.sublime-project"
      "*.sublime-workspace"
      
      # Dependencies
      "node_modules/"
      "vendor/"
      
      # Build outputs
      "*.pyc"
      "__pycache__/"
      "*.class"
      "target/"
      "dist/"
      "build/"
      
      # Environment files
      ".env"
      ".env.local"
      ".env.*.local"
      
      # Log files
      "*.log"
      "npm-debug.log*"
      "yarn-debug.log*"
      "yarn-error.log*"
    ];
    
    # Delta for better diffs (optional)
    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        line-numbers = true;
        side-by-side = false;
        syntax-theme = "Dracula";
      };
    };
    
    # Git Large File Storage (optional)
    lfs = {
      enable = false;  # Set to true if you use Git LFS
    };
    
    # Signing commits (optional)
    signing = {
      key = null;  # Set your GPG key ID here if you sign commits
      signByDefault = false;  # Set to true to sign all commits
    };
  };
  
  # GitHub CLI
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      editor = "vim";
      
      aliases = {
        co = "pr checkout";
        pv = "pr view";
        pc = "pr create";
        pl = "pr list";
        rv = "repo view";
      };
    };
  };
  
  # Gitui - Terminal UI for git (optional)
  programs.gitui = {
    enable = true;
    keyConfig = ''
      # Custom key bindings for gitui can go here
    '';
  };
}
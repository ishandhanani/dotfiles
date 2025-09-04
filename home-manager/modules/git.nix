{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    
    # User information
    userName = "Ishan Dhanani";  # Update with your name
    userEmail = "ishandhanani@gmail.com";  # Update with your email
    
    # Core settings
    extraConfig = {
      core = {
        editor = "vim";
      };
      
      init = {
        defaultBranch = "main";
      };
      
      pull = {
        rebase = false;
      };
      
      push = {
        default = "simple";
      };
    };
    
    # Basic git aliases
    aliases = {
      # Status and info
      st = "status";
      s = "status -s";
      
      # Branches
      br = "branch";
      co = "checkout";
      
      # Commits
      ci = "commit";
      cm = "commit -m";
      
      # Diff
      d = "diff";
      dc = "diff --cached";
      
      # Logging
      l = "log --oneline --graph --decorate";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      last = "log -1 HEAD";
      
      # Common operations
      unstage = "reset HEAD --";
      uncommit = "reset --soft HEAD~1";
    };
    
    # Basic ignore patterns
    ignores = [
      ".DS_Store"
      "*.swp"
      "*~"
      ".env"
      "node_modules/"
      "__pycache__/"
      "*.pyc"
    ];
  };
}
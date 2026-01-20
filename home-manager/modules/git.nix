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

      commit.gpgsign = true;
      gpg.format = "ssh";
      user.signingkey = "~/.ssh/id_ed2551.pub";
      
      url = {
        "git@github.com:" = {
          insteadOf = "https://github.com/";
        };
      };
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

  programs.git.delta = {
    enable = true;  # Better git diffs
    options = {
      navigate = true;
      line-numbers = true;
      side-by-side = true;
    };
  };

  programs.gh-dash = {
    enable = true;  # GitHub CLI
  };
}
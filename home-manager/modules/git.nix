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
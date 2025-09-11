{ config, pkgs, lib, ... }:

{
  programs.ssh = {
    enable = true;
    
    # Disable default config to avoid warnings
    enableDefaultConfig = false;
    
    # SSH client configuration
    extraConfig = ''
      UseKeychain yes
      AddKeysToAgent yes
      IdentitiesOnly yes
    '';
    
    # Default key configuration
    matchBlocks = {
      "*" = {
        identityFile = "~/.ssh/id_ed25519";
        addKeysToAgent = "yes";
        extraOptions = lib.mkIf pkgs.stdenv.isDarwin {
          UseKeychain = "yes";
        };
      };
      
      # GitHub specific (optional but recommended)
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519";
        extraOptions = lib.mkIf pkgs.stdenv.isDarwin {
          UseKeychain = "yes";
        };
      };
    };
  };

  # SSH Agent service (Linux only - macOS handles this automatically)
  services.ssh-agent = {
    enable = pkgs.stdenv.isLinux;
  };
}
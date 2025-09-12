{ config, pkgs, lib, ... }:

{
  programs.ssh = {
    enable = true;
    
    # SSH client configuration that includes your existing config
    extraConfig = ''
      # Include your existing SSH config first
      Include ~/.ssh/config.local
      
      # Home Manager managed settings
      UseKeychain yes
      AddKeysToAgent yes
      IdentitiesOnly yes
    '';
  };

  # SSH Agent service (Linux only - macOS handles this automatically)
  services.ssh-agent = {
    enable = pkgs.stdenv.isLinux;
  };
}
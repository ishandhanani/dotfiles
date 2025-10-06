{ config, pkgs, lib, ... }:

{
  # Enable SSH support
  programs.ssh = {
    enable = true;

    # Drop the default Host * block that Home-Manager inserts
    matchBlocks = { };

    # Add just what you want in your config
    extraConfig = ''
      Include ~/.ssh/config.local
      Include ~/.brev/ssh_config
    '';
  };

  # macOS doesn’t need ssh-agent service — only enable on Linux
  services.ssh-agent.enable = pkgs.stdenv.isLinux;
}


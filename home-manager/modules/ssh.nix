{ config, pkgs, lib, ... }:

{
  programs.ssh = {
    enable = true;
    matchBlocks = { };
    extraConfig = ''
      Host *
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
        ${lib.optionalString pkgs.stdenv.isDarwin "UseKeychain yes"}
      Include ~/.ssh/config.local
      Include ~/.brev/ssh_config
    '';
  };

  # Enable ssh-agent only on Linux
  services.ssh-agent.enable = pkgs.stdenv.isLinux;

  # macOS-specific helper: automatically add key to agent/keychain
  home.activation.sshAddKey = lib.mkIf pkgs.stdenv.isDarwin ''
    /usr/bin/ssh-add --apple-use-keychain ~/.ssh/id_ed25519 || true
  '';

  # Linux: add your key automatically on login if agent is running
  home.activation.sshAddKeyLinux = lib.mkIf pkgs.stdenv.isLinux ''
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
    ssh-add -l >/dev/null 2>&1 || ssh-add ~/.ssh/id_ed25519 >/dev/null 2>&1 || true
  '';
}


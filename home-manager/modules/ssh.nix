{ config, pkgs, lib, ... }:

{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
      };
    };
    extraConfig = ''
      Host *
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
        IdentitiesOnly yes
        PreferredAuthentications publickey
        PubkeyAuthentication yes
        PasswordAuthentication no
        ${lib.optionalString pkgs.stdenv.isDarwin "UseKeychain yes"}
      Include ~/.ssh/config.local
      Include ~/.brev/ssh_config
    '';
  };

  # Enable ssh-agent only on Linux
  services.ssh-agent.enable = pkgs.stdenv.isLinux;

  # macOS-specific helper: automatically add key to agent/keychain
  home.activation.sshAddKey = lib.mkIf pkgs.stdenv.isDarwin ''
    if [ -f ~/.ssh/id_ed25519 ]; then
      /usr/bin/ssh-add --apple-use-keychain ~/.ssh/id_ed25519 2>/dev/null || true
    fi
  '';

  # Linux: add your key automatically on login if agent is running
  home.activation.sshAddKeyLinux = lib.mkIf pkgs.stdenv.isLinux ''
    if [ -f ~/.ssh/id_ed25519 ]; then
      eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
      ssh-add -l >/dev/null 2>&1 || ssh-add ~/.ssh/id_ed25519 >/dev/null 2>&1 || true
    fi
  '';
}


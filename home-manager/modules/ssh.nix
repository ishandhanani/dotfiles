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
        addKeysToAgent = "yes";
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
        ServerAliveInterval 60
        ${lib.optionalString pkgs.stdenv.isDarwin "UseKeychain yes"}
      Include ~/.ssh/config.local
      Include ~/.brev/ssh_config
    '';
  };

  # Enable ssh-agent only on Linux
  services.ssh-agent.enable = pkgs.stdenv.isLinux;

  # macOS-specific helper: automatically add key to agent/keychain if not already present
  home.activation.sshAddKey = lib.mkIf pkgs.stdenv.isDarwin ''
    if [ -f ~/.ssh/id_ed25519 ]; then
      # Only add key if it's not already in the agent
      if ! /usr/bin/ssh-add -l 2>/dev/null | grep -q id_ed25519; then
        /usr/bin/ssh-add --apple-use-keychain ~/.ssh/id_ed25519 2>/dev/null || true
      fi
    fi
  '';

  # Linux: add your key automatically on login if agent is running and key not already loaded
  home.activation.sshAddKeyLinux = lib.mkIf pkgs.stdenv.isLinux ''
    if [ -f ~/.ssh/id_ed25519 ]; then
      # Check if agent is running and key is not already loaded
      if ! ssh-add -l >/dev/null 2>&1 | grep -q id_ed25519; then
        eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
        ssh-add ~/.ssh/id_ed25519 >/dev/null 2>&1 || true
      fi
    fi
  '';
}


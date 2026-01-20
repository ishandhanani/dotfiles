{ config, pkgs, lib, ... }:

{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed2551";
        identitiesOnly = true;
        addKeysToAgent = "yes";
      };
    };
    extraConfig = ''
      Host *
        IdentityFile ~/.ssh/id_ed2551
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

  # macOS-specific helper: automatically add key to agent/keychain
  home.activation.sshAddKey = lib.mkIf pkgs.stdenv.isDarwin ''
    /usr/bin/ssh-add --apple-use-keychain ~/.ssh/id_ed2551 || true
  '';

  # Linux: add your key automatically on login if agent is running
  home.activation.sshAddKeyLinux = lib.mkIf pkgs.stdenv.isLinux ''
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
    if [ -f ~/.ssh/id_ed2551 ]; then
      ssh-add -l >/dev/null 2>&1 || ssh-add ~/.ssh/id_ed2551 >/dev/null 2>&1 || true
    fi
  '';
}


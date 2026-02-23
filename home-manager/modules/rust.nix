{ config, lib, pkgs, ... }:

# Install Rust via rustup (not Nix) so we get the full toolchain manager.
# Shell profiles already source ~/.cargo/env (see bash.nix, zsh.nix),
# so we use --no-modify-path to avoid writing to nix-managed dotfiles.

{
  home.activation.installRust = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    if [ -f "$HOME/.cargo/bin/rustup" ]; then
      echo "rustup already installed, skipping"
    else
      echo "Installing Rust via rustup..."
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
      echo "Rust installed successfully"
    fi
  '';
}

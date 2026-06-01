{ config, lib, pkgs, ... }:

# Install Go via the official tarball from go.dev (not Nix) so we get the
# upstream toolchain and can swap versions with `go install golang.org/dl/...`.
# Installs to $HOME/.local/go; PATH is set via home.sessionPath in home.nix.

{
  home.activation.installGo = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    if [ -x "$HOME/.local/go/bin/go" ]; then
      echo "go already installed at $HOME/.local/go, skipping"
    else
      echo "Installing Go from go.dev..."
      export PATH="${pkgs.curl}/bin:${pkgs.coreutils}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:$PATH"

      os="$(uname -s | tr '[:upper:]' '[:lower:]')"
      arch="$(uname -m)"
      case "$arch" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
      esac

      version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
      tarball="$version.$os-$arch.tar.gz"

      tmpdir="$(mktemp -d)"
      curl -fsSL "https://go.dev/dl/$tarball" -o "$tmpdir/$tarball"
      mkdir -p "$HOME/.local"
      rm -rf "$HOME/.local/go"
      tar -C "$HOME/.local" -xzf "$tmpdir/$tarball"
      rm -rf "$tmpdir"
      echo "Go installed successfully to $HOME/.local/go"
    fi
  '';
}

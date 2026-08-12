{ config, lib, pkgs, ... }:

# User-facing CLIs that are distributed outside nixpkgs.

{
  home.activation.installCLIs = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    export PATH="$HOME/.local/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin:${pkgs.gzip}/bin:${pkgs.gnutar}/bin:${pkgs.git}/bin:$PATH"
    export CI=1
    set -eo pipefail

    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"

    install_brev() {
      source_dir="''${BREV_CLI_SOURCE_DIR:-$HOME/Desktop/brev-cli}"
      if [ -d "$source_dir" ] && [ -f "$source_dir/go.mod" ]; then
        echo "Building Brev from $source_dir..."
        version="dev-$(git -C "$source_dir" rev-parse --short HEAD)"
        ${pkgs.go}/bin/go build -o "$INSTALL_DIR/brev" \
          -ldflags "-X github.com/brevdev/brev-cli/pkg/cmd/version.Version=$version" \
          "$source_dir"
        chmod 0755 "$INSTALL_DIR/brev"
        echo "Brev built from source"
        return 0
      fi

      if command -v brev >/dev/null 2>&1; then
        echo "Brev already installed, skipping"
        return 0
      fi

      echo "Brev source checkout not found at $source_dir" >&2
      case "$(uname -s)" in
        Darwin)
          if ! command -v brew >/dev/null 2>&1; then
            echo "Homebrew is required to install Brev on macOS" >&2
            return 1
          fi
          brew install brevdev/homebrew-brev/brev
          ;;
        Linux)
          curl -fsSL https://raw.githubusercontent.com/brevdev/brev-cli/main/bin/install-latest.sh | ${pkgs.bash}/bin/bash
          ;;
        *)
          echo "Unsupported operating system for Brev: $(uname -s)" >&2
          return 1
          ;;
      esac
    }

    install_brev
    echo "CLI check complete"
  '';
}

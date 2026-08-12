{ config, lib, pkgs, ... }:

# CLIs that are distributed outside nixpkgs

{
  home.activation.installAgentCLIs = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
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

    install_claude() {
      if command -v claude >/dev/null 2>&1; then
        echo "✅ Claude already installed, skipping"
        return 0
      fi

      echo "📦 Installing Claude..."
      curl -fsSL https://claude.ai/install.sh | ${pkgs.bash}/bin/bash
    }

    install_devin() {
      if command -v devin >/dev/null 2>&1; then
        echo "✅ Devin already installed, skipping"
        return 0
      fi

      echo "📦 Installing Devin..."
      curl -fsSL https://cli.devin.ai/install.sh | ${pkgs.bash}/bin/bash
    }

    install_cursor() {
      if command -v cursor >/dev/null 2>&1; then
        echo "✅ Cursor already installed, skipping"
        return 0
      fi

      echo "📦 Installing Cursor..."
      curl https://cursor.com/install -fsS | ${pkgs.bash}/bin/bash
    }

    install_codex() {
      if command -v codex >/dev/null 2>&1; then
        echo "✅ Codex already installed, skipping"
        return 0
      fi

      if [ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]; then
        echo "⚠️ Codex from Aphoh/codex is only built for Linux x86-64, skipping"
        return 0
      fi

      echo "📦 Installing Codex from Aphoh/codex..."

      asset_suffix="linux-x86-64"
      tags_output=$(git ls-remote --tags --sort=-v:refname https://github.com/Aphoh/codex 'refs/tags/enforce-us-v*')

      if [ -z "$tags_output" ]; then
        echo "❌ No Codex releases found"
        exit 1
      fi

      tmp=$(mktemp -d)
      downloaded=0
      while IFS=$'\t' read -r sha ref; do
        tag=''${ref#refs/tags/}
        tag_stripped=''${tag#enforce-us-v}
        version=$(echo "$tag_stripped" | cut -d- -f1)
        suffix=$(echo "$tag_stripped" | cut -s -d- -f2)
        suffix_part=''${suffix:+-$suffix}
        asset_name="codex-''${version}-enforce-us''${suffix_part}-''${asset_suffix}.tar.gz"
        url="https://github.com/Aphoh/codex/releases/download/$tag/$asset_name"

        echo "📦 Trying $asset_name..."
        if curl -fsSL "$url" -o "$tmp/codex.tar.gz" 2>/dev/null; then
          downloaded=1
          break
        fi
      done <<< "$tags_output"

      if [ "$downloaded" -ne 1 ]; then
        echo "❌ No Codex asset found for $asset_suffix"
        rm -rf "$tmp"
        exit 1
      fi

      tar -xzf "$tmp/codex.tar.gz" -C "$tmp"

      codex_bin=$(find "$tmp" -maxdepth 2 -type f -name "codex" | head -n1)
      if [ -z "$codex_bin" ]; then
        echo "❌ codex binary not found in archive"
        rm -rf "$tmp"
        exit 1
      fi
      cp "$codex_bin" "$INSTALL_DIR/codex"
      chmod +x "$INSTALL_DIR/codex"

      host_bin=$(find "$tmp" -maxdepth 2 -type f -name "codex-code-mode-host" | head -n1)
      if [ -n "$host_bin" ]; then
        cp "$host_bin" "$INSTALL_DIR/codex-code-mode-host"
        chmod +x "$INSTALL_DIR/codex-code-mode-host"
      fi

      rm -rf "$tmp"
      echo "✅ Codex $version installed"
    }

    install_brev
    install_claude
    install_devin
    install_cursor
    install_codex

    echo "✅ Agent CLIs check complete"
  '';
}

{ config, lib, pkgs, ... }:

# AI agent CLIs that are distributed outside nixpkgs

{
  home.activation.installAgentCLIs = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    export PATH="$HOME/.local/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin:${pkgs.gzip}/bin:${pkgs.gnutar}/bin:${pkgs.git}/bin:$PATH"
    export CI=1
    set -eo pipefail

    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"

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

    install_claude
    install_devin
    install_cursor
    install_codex

    echo "✅ Agent CLIs check complete"
  '';
}

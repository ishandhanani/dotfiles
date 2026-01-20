{ config, lib, pkgs, ... }:

# Tools that I want to specifically install with uvx

let
  # List of uv tools you want installed
  uvxTools = [ "llm" "y-cli" ];
in
{
  home.activation.installUvTools = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    echo "🔧 Checking uv tools..."
    mkdir -p "$HOME/.local/bin"

    if [ -f "$HOME/.nix-profile/bin/uv" ]; then
      for tool in ${builtins.concatStringsSep " " uvxTools}; do
        # Check if tool is already installed and working
        if ! "$HOME/.nix-profile/bin/uv" tool list 2>/dev/null | grep -q "^$tool "; then
          echo "📦 Installing $tool..."
          "$HOME/.nix-profile/bin/uv" tool install "$tool"
        else
          echo "✅ $tool already installed, skipping"
        fi
      done
      echo "✅ uv tools check complete"
    else
      echo "❌ uv not found at $HOME/.nix-profile/bin/uv, skipping uv tool installs"
    fi
  '';
}

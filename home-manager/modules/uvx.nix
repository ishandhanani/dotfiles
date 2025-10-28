{ config, lib, pkgs, ... }:

# Tools that I want to specifically install with uvx

let
  # List of uv tools you want installed
  uvxTools = [ "llm" "y-cli" ];
in
{
  home.activation.installUvTools = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    echo "🔧 Running uv tools activation script..."
    mkdir -p "$HOME/.local/bin"

    if [ -f "$HOME/.nix-profile/bin/uv" ]; then
      echo "✅ uv found, installing tools: ${builtins.concatStringsSep " " uvxTools}"
      for tool in ${builtins.concatStringsSep " " uvxTools}; do
        echo "📦 Installing $tool..."
        "$HOME/.nix-profile/bin/uv" tool install "$tool" --force
      done
      echo "✅ uv tools installation complete"
    else
      echo "❌ uv not found at $HOME/.nix-profile/bin/uv, skipping uv tool installs"
    fi
  '';
}

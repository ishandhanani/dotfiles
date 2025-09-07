{ config, lib, pkgs, ... }:

# GH extensions

let
  ghExts = [ "dlvhdr/gh-dash" ];
in
{
  home.activation.installUvTools = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    if [ -f "$HOME/.nix-profile/bin/gh" ]; then
      echo "✅ gh found, installing tools: ${builtins.concatStringsSep " " ghExts}"
      for tool in ${builtins.concatStringsSep " " ghExts}; do
        echo "📦 Installing $tool..."
        "$HOME/.nix-profile/bin/gh" extension install "$tool" --force
      done
      echo "✅ gh tools installation complete"
    else
      echo "❌ gh not found at $HOME/.nix-profile/bin/gh, skipping gh tool installs"
    fi
  '';
}

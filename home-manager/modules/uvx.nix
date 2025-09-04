{ config, lib, pkgs, ... }:

# Tools that I want to specifically install with uvx

let
  # List of uvx tools you want installed
  uvxTools = [ "llm" ];
in
{
  home.activation.installUvTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/bin"

    if command -v uvx >/dev/null 2>&1; then
      echo "Installing uvx tools: ${builtins.concatStringsSep " " uvxTools}"
      for tool in ${builtins.concatStringsSep " " uvxTools}; do
        uvx tool install "$tool" --force
      done
    else
      echo "uvx not found in PATH, skipping uvx tool installs"
    fi
  '';
}

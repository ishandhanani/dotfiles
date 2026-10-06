{ lib, pkgs, ... }:

let
  tools = [ "llm" "y-cli" "ty" "prek" ];
in {
  home.activation.installUvTools = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:${pkgs.coreutils}/bin:$PATH"
    installed_tools="$(${pkgs.uv}/bin/uv tool list)"
    for tool in ${lib.escapeShellArgs tools}; do
      if printf '%s\n' "$installed_tools" | ${pkgs.gnugrep}/bin/grep -q "^$tool "; then
        echo "$tool already installed, skipping"
      else
        run ${pkgs.uv}/bin/uv tool install "$tool"
      fi
    done
  '';
}

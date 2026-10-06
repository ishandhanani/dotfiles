{ config, lib, pkgs, ... }:

# Tools that I want to specifically install with uvx

let
  # List of uv tools you want installed
  uvxTools = [ "llm" "y-cli" "ty" "prek" ];
in
{
  home.activation.installUvTools = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    echo "Checking uv tools..."
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:${pkgs.uv}/bin:${pkgs.curl}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"
    mkdir -p "$HOME/.local/bin"

    resolve_uv() {
      for candidate in \
        "$HOME/.local/bin/uv" \
        "$HOME/.cargo/bin/uv" \
        "$HOME/.nix-profile/bin/uv" \
        "/etc/profiles/per-user/${config.home.username}/bin/uv" \
        "${pkgs.uv}/bin/uv"
      do
        if [ -x "$candidate" ]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done

      command -v uv 2>/dev/null || return 1
    }

    uv_bin="$(resolve_uv || true)"
    if [ -z "$uv_bin" ]; then
      echo "Installing uv before installing uv tools..."
      ${pkgs.bash}/bin/bash ${../scripts/install-uv.sh}
      uv_bin="$(resolve_uv || true)"
    fi

    if [ -z "$uv_bin" ]; then
      echo "uv not found after installer, skipping uv tool installs"
    else
      for tool in ${builtins.concatStringsSep " " uvxTools}; do
        if ! "$uv_bin" tool list 2>/dev/null | grep -q "^$tool "; then
          echo "Installing $tool..."
          "$uv_bin" tool install "$tool"
        else
          echo "$tool already installed, skipping"
        fi
      done
      echo "uv tools check complete"
    fi
  '';
}

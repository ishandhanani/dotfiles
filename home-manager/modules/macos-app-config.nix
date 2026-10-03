{ config, lib, pkgs, ... }:

let
  inherit (lib) hm mkIf;

  rectangleConfig = ../../rectangle/rectangle.json;
in
{
  config = mkIf pkgs.stdenv.isDarwin {
    home.file."Library/Application Support/Cursor/User/settings.json".source = ../../cursor/settings.json;

    home.activation.rectangleDefaults = hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

      rectangle_config=${rectangleConfig}
      domain="$(${pkgs.jq}/bin/jq -r '.bundleId' "$rectangle_config")"

      ${pkgs.jq}/bin/jq -r '.defaults | to_entries[] | @base64' "$rectangle_config" | while IFS= read -r row; do
        entry() {
          printf '%s' "$row" | base64 --decode | ${pkgs.jq}/bin/jq -r "$1"
        }

        key="$(entry '.key')"
        kind="$(entry '
          .value
          | if has("bool") then "bool"
            elif has("int") then "int"
            elif has("float") then "float"
            elif has("string") then "string"
            elif has("keyCode") and has("modifierFlags") then "keyCombo"
            elif type == "object" and length == 0 then "emptyDict"
            else "skip"
            end
        ')"

        case "$kind" in
          bool)
            defaults write "$domain" "$key" -bool "$(entry '.value.bool')"
            ;;
          int)
            defaults write "$domain" "$key" -int "$(entry '.value.int')"
            ;;
          float)
            defaults write "$domain" "$key" -float "$(entry '.value.float')"
            ;;
          string)
            defaults write "$domain" "$key" -string "$(entry '.value.string')"
            ;;
          keyCombo)
            defaults write "$domain" "$key" -dict \
              keyCode -int "$(entry '.value.keyCode')" \
              modifierFlags -int "$(entry '.value.modifierFlags')"
            ;;
          emptyDict)
            defaults write "$domain" "$key" -dict
            ;;
        esac
      done
    '';
  };
}

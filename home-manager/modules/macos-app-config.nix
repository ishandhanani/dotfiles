{ config, lib, pkgs, ... }:

let
  rectangle = builtins.fromJSON (builtins.readFile ../../rectangle/rectangle.json);
  unwrap = value:
    if value ? float then value.float + 0.0
    else if value == { } then { }
    else builtins.head (builtins.attrValues value);
  preferences = lib.mapAttrs (_: unwrap) rectangle.defaults // rectangle.shortcuts;
  writePreference = key: value:
    "run /usr/bin/defaults write ${lib.escapeShellArg rectangle.bundleId} ${lib.escapeShellArg key} ${lib.escapeShellArg (lib.generators.toPlist { escape = true; } value)}";
in {
  config = lib.mkIf pkgs.stdenv.isDarwin {
    home.file."Library/Application Support/Cursor/User/settings.json".source = ../../cursor/settings.json;
    xdg.configFile."ghostty/config".text = builtins.replaceStrings
      [ "/Users/ishandhanani" ] [ config.home.homeDirectory ]
      (builtins.readFile ../../ghostty/config);

    # Write individual keys so unrelated app preferences survive an apply.
    home.activation.rectangleDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ]
      (lib.concatStringsSep "\n" (lib.mapAttrsToList writePreference preferences));
  };
}

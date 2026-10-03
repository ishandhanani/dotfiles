{ homeDirectory, inputs, lib, pkgs, user, ... }:

let
  disableSymbolicHotkey = id: value:
    let
      encodedValue = lib.escapeShellArg value;
    in ''
      launchctl asuser "$(id -u -- "$primary_user")" sudo --user="$primary_user" -- \
        defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
        -dict-add ${toString id} ${encodedValue}
    '';
in
{
  system.primaryUser = user;
  system.stateVersion = 7;
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  users.users.${user}.home = homeDirectory;

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  # This machine uses Determinate Nix. Keep nix-darwin from taking over the
  # daemon, /etc/nix/nix.conf, or Nix upgrades.
  nix.enable = false;

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleInterfaceStyleSwitchesAutomatically = false;
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      "com.apple.trackpad.enableSecondaryClick" = true;
      "com.apple.trackpad.scaling" = 2.5;
    };

    dock = {
      magnification = true;
      show-recents = false;
      tilesize = 47;
    };

    finder = {
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = false;
      ShowRemovableMediaOnDesktop = true;
    };

    menuExtraClock = {
      ShowAMPM = true;
      ShowDate = 0;
      ShowDayOfWeek = true;
    };

    trackpad = {
      ActuateDetents = true;
      Clicking = true;
      DragLock = false;
      Dragging = false;
      FirstClickThreshold = 1;
      ForceSuppressed = false;
      SecondClickThreshold = 1;
      TrackpadCornerSecondaryClick = 0;
      TrackpadFourFingerHorizSwipeGesture = 2;
      TrackpadFourFingerPinchGesture = 2;
      TrackpadFourFingerVertSwipeGesture = 2;
      TrackpadMomentumScroll = true;
      TrackpadPinch = true;
      TrackpadRightClick = true;
      TrackpadRotate = true;
      TrackpadThreeFingerDrag = false;
      TrackpadThreeFingerHorizSwipeGesture = 2;
      TrackpadThreeFingerTapGesture = 0;
      TrackpadThreeFingerVertSwipeGesture = 2;
      TrackpadTwoFingerDoubleTapGesture = true;
      TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
    };

    CustomUserPreferences = {
      "com.raycast.macos" = {
        raycastGlobalHotkey = "Command-49";
        raycastPreferredWindowMode = "default";
        raycastShouldFollowSystemAppearance = true;
      };
    };

    WindowManager = {
      EnableTiledWindowMargins = false;
      EnableTilingByEdgeDrag = false;
      EnableTilingOptionAccelerator = false;
      EnableTopTilingByEdgeDrag = false;
      HideDesktop = true;
      StageManagerHideWidgets = false;
      StandardHideWidgets = true;
    };
  };

  system.activationScripts.spotlightHotkeys.text = ''
    primary_user=${lib.escapeShellArg user}

    echo "disabling Spotlight hotkeys..." >&2
    ${disableSymbolicHotkey 64 "{ enabled = 0; value = { parameters = (32, 49, 1048576); type = standard; }; }"}
    ${disableSymbolicHotkey 65 "{ enabled = 0; value = { parameters = (32, 49, 1572864); type = standard; }; }"}
  '';
}

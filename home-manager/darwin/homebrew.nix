{ config, user, ... }:

{
  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = false;
    enableRosetta = false;
    mutableTaps = true;
  };

  homebrew = {
    enable = true;
    user = user;

    caskArgs = {
      appdir = "/Applications";
    };

    onActivation = {
      autoUpdate = false;
      cleanup = "none";
      upgrade = false;
    };

    global = {
      autoUpdate = false;
    };

    casks = [
      "cursor"
      "iterm2"
      "raycast"
      "rectangle"
      "thebrowsercompany-dia"
    ];
  };
}

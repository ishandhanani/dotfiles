{
  description = "Ishan's dotfiles and macOS setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nix-darwin, ... }@inputs:
    let
      # Make supplies the local account and checkout; dependencies stay locked.
      user = builtins.getEnv "DOTFILES_USER";
      homeDirectory = builtins.getEnv "DOTFILES_HOME";
      sourceDirectory = builtins.getEnv "DOTFILES_ROOT";
      system = builtins.currentSystem;
      pkgs = nixpkgs.legacyPackages.${system};
      localAccount = assert user != "" && user != "root" && homeDirectory != "" && sourceDirectory != "";
        { inherit user homeDirectory sourceDirectory; };
    in {
      homeConfigurations.default = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
        extraSpecialArgs = localAccount;
      };

      darwinConfigurations.macos = nix-darwin.lib.darwinSystem {
        system = if pkgs.stdenv.isDarwin then system else "aarch64-darwin";
        specialArgs = localAccount // { inherit inputs; };
        modules = [ ./darwin/system.nix ];
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}

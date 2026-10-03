{
  description = "Ishan's Home Manager and nix-darwin configuration";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # System-wide macOS configuration.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, ... }@inputs:
    let
      # System types
      darwinSystem = "aarch64-darwin";  # Apple Silicon
      linuxSystem = "x86_64-linux";

      mkHomeConfiguration = system: user: homeDirectory:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./home.nix ];
          extraSpecialArgs = {
            inherit user homeDirectory;
          };
        };

      mkDarwinConfiguration = user: homeDirectory:
        nix-darwin.lib.darwinSystem {
          system = darwinSystem;
          specialArgs = {
            inherit inputs user homeDirectory;
          };
          modules = [
            ./darwin/system.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = {
                inherit user homeDirectory;
              };
              home-manager.users.${user} = import ./home.nix;
            }
          ];
        };
    in
    {
      # nix-darwin system configurations for macOS.
      darwinConfigurations = {
        "work" = mkDarwinConfiguration "idhanani" "/Users/idhanani";
        "home" = mkDarwinConfiguration "ishandhanani" "/Users/ishandhanani";
      };

      # Home Manager configurations
      homeConfigurations = {
        # macOS configuration
        "home" = mkHomeConfiguration darwinSystem "ishandhanani" "/Users/ishandhanani";

        "work" = mkHomeConfiguration darwinSystem "idhanani" "/Users/idhanani";
        
        "brev-vm" = mkHomeConfiguration linuxSystem "ubuntu" "/home/ubuntu";

        "brev-vm-gpu" = mkHomeConfiguration linuxSystem "nvidia" "/home/nvidia";

        "simbox" = mkHomeConfiguration linuxSystem "ishan" "/home/ishan";
        
        "work-desktop" = mkHomeConfiguration linuxSystem "idhanani" "/home/idhanani";

        "brev-vm-arm" = mkHomeConfiguration "aarch64-linux" "ubuntu" "/home/ubuntu";
      };

      formatter = {
        ${darwinSystem} = nixpkgs.legacyPackages.${darwinSystem}.nixpkgs-fmt;
        ${linuxSystem} = nixpkgs.legacyPackages.${linuxSystem}.nixpkgs-fmt;
      };

      apps.${darwinSystem}.install-homebrew = {
        type = "app";
        program = "${./scripts/install-homebrew.sh}";
      };
    };
}

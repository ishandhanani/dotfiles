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

    # Homebrew bootstrap for nix-darwin's declarative cask management.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew/5108f0846cde2080aaeb1c7b08e3bd7d27f33b57";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, ... }@inputs:
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
            nix-homebrew.darwinModules.nix-homebrew
            ./darwin/system.nix
            ./darwin/homebrew.nix
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
    };
}

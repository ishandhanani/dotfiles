{
  description = "Ishan's minimal Home Manager configuration";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      # System types
      darwinSystem = "aarch64-darwin";  # Apple Silicon
      linuxSystem = "x86_64-linux";
    in
    {
      # Home Manager configurations
      homeConfigurations = {
        # macOS configuration
        "ishandhanani@macbook" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${darwinSystem};
          modules = [ ./home.nix ];
        };
        
        # Linux configuration (if you also use Linux)
        "ishandhanani@linux" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${linuxSystem};
          modules = [ ./home.nix ];
        };
      };
    };
}
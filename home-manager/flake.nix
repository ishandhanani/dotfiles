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
        "home" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${darwinSystem};
          modules = [ ./home.nix ];
          extraSpecialArgs = {
            user = "ishandhanani";
            homeDirectory = "/Users/ishandhanani";
          };
        };

        "work" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${darwinSystem};
          modules = [ ./home.nix ];
          extraSpecialArgs = {
            user = "idhanani";
            homeDirectory = "/Users/idhanani";
          };
        };
        
        "brev-vm" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${linuxSystem};
          modules = [ ./home.nix ];  # Use the same file with conditionals
          extraSpecialArgs = {
            user = "ubuntu";
            homeDirectory = "/home/ubuntu";
          };
        };

        "simbox" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${linuxSystem};
          modules = [ ./home.nix ];  # Use the same file with conditionals
          extraSpecialArgs = {
            user = "ishan";
            homeDirectory = "/home/ishan";
          };
        };
        
        "brev-vm-arm" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages."aarch64-linux";
          modules = [ ./home.nix ];  # Use the same file with conditionals
          extraSpecialArgs = {
            user = "ubuntu";
            homeDirectory = "/home/ubuntu";
          };
        };
      };

      formatter = {
        ${darwinSystem} = nixpkgs.legacyPackages.${darwinSystem}.nixpkgs-fmt;
        ${linuxSystem} = nixpkgs.legacyPackages.${linuxSystem}.nixpkgs-fmt;
      };
    };
}

{
  description = "Ishan's Home Manager configuration";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Darwin support for macOS
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, home-manager, darwin, flake-utils, ... }@inputs:
    let
      # System types
      darwinSystem = "aarch64-darwin";  # Apple Silicon
      # darwinSystem = "x86_64-darwin";  # Intel Mac
      linuxSystem = "x86_64-linux";
      
      # Helper function to create home configuration
      mkHomeConfiguration = system: modules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = modules ++ [
            {
              # Make inputs available to modules
              _module.args = { inherit inputs; };
              
              # Ensure nix settings
              nix = {
                package = nixpkgs.legacyPackages.${system}.nix;
                settings = {
                  experimental-features = [ "nix-command" "flakes" ];
                  warn-dirty = false;
                };
              };
            }
          ];
        };
    in
    {
      # Home Manager configurations
      homeConfigurations = {
        # macOS configuration
        "ishandhanani@macbook" = mkHomeConfiguration darwinSystem [
          ./home.nix
          {
            # Override username and home directory if needed
            home = {
              username = "ishandhanani";
              homeDirectory = "/Users/ishandhanani";
            };
          }
        ];
        
        # Linux configuration (if you also use Linux)
        "ishandhanani@linux" = mkHomeConfiguration linuxSystem [
          ./home.nix
          {
            home = {
              username = "ishandhanani";
              homeDirectory = "/home/ishandhanani";
            };
          }
        ];
      };
      
      # Darwin system configuration (optional, for system-wide macOS settings)
      darwinConfigurations = {
        "macbook" = darwin.lib.darwinSystem {
          system = darwinSystem;
          modules = [
            # System configuration
            ({ pkgs, ... }: {
              # System packages
              environment.systemPackages = with pkgs; [
                vim
                git
              ];
              
              # Auto-upgrade nix and daemon service
              services.nix-daemon.enable = true;
              nix = {
                package = pkgs.nix;
                settings = {
                  experimental-features = [ "nix-command" "flakes" ];
                  trusted-users = [ "root" "ishandhanani" ];
                };
              };
              
              # macOS system preferences
              system.defaults = {
                dock = {
                  autohide = true;
                  orientation = "left";
                  show-recents = false;
                  minimize-to-application = true;
                };
                
                finder = {
                  ShowPathbar = true;
                  ShowStatusBar = true;
                  FXEnableExtensionChangeWarning = false;
                  AppleShowAllExtensions = true;
                };
                
                NSGlobalDomain = {
                  AppleKeyboardUIMode = 3;  # Full keyboard access
                  ApplePressAndHoldEnabled = false;  # Key repeat
                  InitialKeyRepeat = 15;
                  KeyRepeat = 2;
                  NSAutomaticCapitalizationEnabled = false;
                  NSAutomaticDashSubstitutionEnabled = false;
                  NSAutomaticPeriodSubstitutionEnabled = false;
                  NSAutomaticQuoteSubstitutionEnabled = false;
                  NSAutomaticSpellingCorrectionEnabled = false;
                };
              };
              
              # Used for backwards compatibility
              system.stateVersion = 4;
            })
            
            # Home Manager as a Darwin module
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.ishandhanani = import ./home.nix;
              };
            }
          ];
        };
      };
      
      # Development shells for different purposes
      devShells = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              home-manager
              git
              vim
            ];
            
            shellHook = ''
              echo "Home Manager development shell"
              echo "Run 'home-manager switch --flake .#ishandhanani@macbook' to apply configuration"
            '';
          };
        });
      
      # Templates for creating new configurations
      templates = {
        default = {
          path = ./.;
          description = "A complete Home Manager configuration with flakes";
        };
      };
    };
}
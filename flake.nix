{
  description = "music-brain88's dotfiles - Nix/Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Neovim plugins and ecosystem
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, neovim-nightly-overlay, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          neovim-nightly-overlay.overlays.default
        ];
      };
    in
    {
      # Home Manager configuration
      homeConfigurations = {
        # Default configuration for archie
        "archie" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./home.nix
          ];

          extraSpecialArgs = {
            inherit inputs;
          };
        };
      };

      # Development shell for testing
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nil # Nix language server
          nixpkgs-fmt # Nix formatter
          nix-tree # Nix dependency tree viewer
        ];

        shellHook = ''
          echo "Nix development environment loaded"
          echo "Available tools: nil, nixpkgs-fmt, nix-tree"
        '';
      };
    };
}

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
          # neovim-nightly-overlay disabled: waiting for upstream fix for nixpkgs lua argument removal
          # neovim-nightly-overlay.overlays.default
          # Fix for CI: some package tests are flaky in GitHub Actions environment
          (final: prev: {
            # rustup tests fail in sandboxed CI due to socks_proxy_request needing network
            rustup = prev.rustup.overrideAttrs (old: {
              doCheck = false;
            });

            python311Packages = prev.python311Packages.override {
              overrides = pfinal: pprev: {
                websockets = pprev.websockets.overridePythonAttrs (old: {
                  doCheck = false;
                });
                # cbor2 tests fail in sandboxed CI due to tmp_path fixture issues
                cbor2 = pprev.cbor2.overridePythonAttrs (old: {
                  doCheck = false;
                });
              };
            };
          })
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

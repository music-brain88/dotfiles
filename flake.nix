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

    # herdr 用の新しめ nixpkgs: メインの locked nixpkgs には herdr が未収録。
    # 全体を update せず、この input だけで herdr を供給する (バイナリキャッシュ有効)。
    # Newer nixpkgs pin for herdr only: the main locked nixpkgs predates herdr.
    # Avoids a full nixpkgs bump while keeping Hydra's binary cache.
    nixpkgs-herdr.url = "github:nixos/nixpkgs/nixos-unstable";
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
          # Bump github-copilot-cli to latest release (nixpkgs lags behind npm)
          (final: prev: {
            github-copilot-cli = prev.github-copilot-cli.overrideAttrs (old:
              let
                copilotVersion = "1.0.65";
              in
              {
                version = copilotVersion;
                # 1.0.5x 以降、npm registry の tgz は npm-loader.js のみになり
                # 本体 (index.js + ネイティブバイナリ) はプラットフォーム別の
                # GitHub Release アセットに分離された。x86_64-linux 用を使う。
                # The npm tarball now only ships a loader; the real index.js
                # and native binaries live in the platform-specific release asset.
                src = prev.fetchzip {
                  url = "https://github.com/github/copilot-cli/releases/download/v${copilotVersion}/github-copilot-${copilotVersion}-linux-x64.tgz";
                  hash = "sha256-4Af5u4K5xg76RCLu3jHY1+IxWMosu7d8fmwJy0zgwB4=";
                };
                # 同梱ネイティブバイナリ (.node, ripgrep) を patchelf する
                # Patch the bundled native binaries for the Nix store.
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.autoPatchelfHook ];
                buildInputs = (old.buildInputs or [ ]) ++ [
                  prev.stdenv.cc.cc.lib
                  prev.glib
                  prev.libsecret
                ];
                # GUI/メディア機能用のライブラリは CLI 利用では不要なので無視
                # These GUI/media libs are only for screen-capture/input features.
                autoPatchelfIgnoreMissingDeps = [
                  "libX11.so.6"
                  "libXtst.so.6"
                  "libjpeg.so.8"
                  "libpng16.so.16"
                  "libpipewire-0.3.so.0"
                  "libei.so.1"
                ];
                # npm version may not match internal binary version string
                doInstallCheck = false;
              });
          })
          # herdr を専用 pin の nixpkgs から供給 (メインの locked nixpkgs には未収録)
          # Provide herdr from its dedicated nixpkgs pin (absent from the main lock)
          (final: prev: {
            herdr = inputs.nixpkgs-herdr.legacyPackages.${system}.herdr;
          })
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

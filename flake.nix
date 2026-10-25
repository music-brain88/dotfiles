{
  description = "music-brain88's dotfiles - Nix/Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # herdr 用の新しめ nixpkgs: メインの locked nixpkgs には herdr が未収録。
    # 全体を update せず、この input だけで herdr を供給する (バイナリキャッシュ有効)。
    # Newer nixpkgs pin for herdr only: the main locked nixpkgs predates herdr.
    # Avoids a full nixpkgs bump while keeping Hydra's binary cache.
    nixpkgs-herdr.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          # 自作ツール: standalone-check (配布文書の自立可読性チェッカー、Rust)。
          # ソースは tools/standalone-check/、配布は nix/modules/dev-tools.nix の home.packages。
          # In-repo tool: standalone-check (Rust). Source in tools/standalone-check/,
          # shipped via home.packages in nix/modules/dev-tools.nix.
          (final: prev: {
            standalone-check = final.callPackage ./tools/standalone-check/package.nix { };
          })
          # Bump github-copilot-cli to latest release (nixpkgs lags behind npm)
          (final: prev: {
            github-copilot-cli = prev.github-copilot-cli.overrideAttrs (old:
              let
                copilotVersion = "1.0.91";
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
                  hash = "sha256-bdwIZLSTNitGMcw/oWrHDHQqXUBkRBUi61rYPJ6QUi4=";
                };
                # nixpkgs 側の derivation が npm tarball 前提の sourceRoot = "package" を
                # 設定するようになったが、GitHub Release アセットはルート直下にファイルを
                # 置くため上書きして戻す (fetchzip の展開ディレクトリ名は "source")。
                # The nixpkgs derivation now sets sourceRoot = "package" for the npm
                # tarball layout; the GitHub release asset is flat, so point back at
                # the fetchzip output directory ("source").
                sourceRoot = "source";
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
                  # v1.0.78 で追加された webview 機能 (@webviewjs/webview) 用の GTK/WebKit
                  # スタック。CLI 利用では webview 機能を使わないため無視する。
                  # GTK/WebKit stack for the webview feature (@webviewjs/webview) added
                  # in v1.0.78. Unused in CLI usage, so ignore it.
                  "libwebkit2gtk-4.1.so.0"
                  "libgtk-3.so.0"
                  "libgdk-3.so.0"
                  "libcairo.so.2"
                  "libgdk_pixbuf-2.0.so.0"
                  "libsoup-3.0.so.0"
                  "libjavascriptcoregtk-4.1.so.0"
                  "libwayland-client.so.0"
                  "libdbus-1.so.3"
                  "libxdo.so.3"
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
          # herdr 公式の Claude Code 用フック (Issue #755)。herdr は、このフックが報告した
          # session ID で、server の再起動後に Claude Code の pane を `claude --resume <id>` で
          # 再開する。公式インストーラは ~/.claude/settings.json に書き込もうとするが、この
          # ファイルは home-manager の読み取り専用の symlink なので、利用者の環境では失敗する。
          # そこでインストーラをビルド時の生成器として使い、上の herdr と同じ版のスクリプトを作る。
          # $out/hooks/herdr-agent-state.sh は nix/modules/herdr.nix が ~/.claude/hooks/ に置く。
          # $out/settings.json はどこにも置かず、checks.herdr-claude-hook-entries が
          # .config/claude/settings.json の手書きのエントリと比べるためだけに使う。
          # herdr's official Claude Code hook (Issue #755). herdr resumes a Claude Code pane
          # after a server restart with `claude --resume <id>`, using the session ID this hook
          # reports. The official installer writes ~/.claude/settings.json, which is a read-only
          # home-manager symlink here, so it fails on the live machine. Run it as a build-time
          # generator instead, so the script always matches the herdr pinned above.
          # nix/modules/herdr.nix links $out/hooks/herdr-agent-state.sh into ~/.claude/hooks/.
          # $out/settings.json is not deployed; checks.herdr-claude-hook-entries only compares
          # it with the hand-written entry in .config/claude/settings.json.
          (final: prev: {
            herdr-claude-hook = prev.runCommand "herdr-claude-hook-${final.herdr.version}"
              {
                nativeBuildInputs = [ final.herdr ];
              } ''
              # 出力先のディレクトリが無いと、インストーラは "claude directory not found" で失敗する
              # The installer fails with "claude directory not found" unless the directory exists
              mkdir -p "$out"
              CLAUDE_CONFIG_DIR="$out" herdr integration install claude
              # フックは python3 が PATH に無いと何も言わずに終わるので、Nix の python3 に固定する。
              # --replace-fail は、herdr がスクリプトの形を変えたときにビルドを落として知らせる。
              # The hook silently exits when python3 is not on PATH, so pin Nix's python3.
              # --replace-fail breaks the build if herdr changes the shape of the script.
              substituteInPlace "$out/hooks/herdr-agent-state.sh" \
                --replace-fail 'command -v python3 ' 'command -v ${final.python3}/bin/python3 ' \
                --replace-fail 'python3 - <<' '${final.python3}/bin/python3 - <<'
            '';
          })
          # terminal-browser (zenbu-labs/terminal-browser、MIT): Electron の画面外の描画で
          # ページを描き、kitty graphics で端末へ送るブラウザ。device-auth の承認ページを
          # herdr の pane で開くために使う (Issue #701)。nixpkgs には無いので、GitHub の
          # release の linux-x64 tarball を版と hash で固定して包む。配るのは native 機だけ
          # (nix/modules/terminal-browser.nix)。詳細は docs/reference/terminal-browser.md。
          # terminal-browser (zenbu-labs/terminal-browser, MIT): renders pages with Electron's
          # offscreen rendering and streams them to the terminal over kitty graphics. Used to
          # open device-auth approval pages in a herdr pane (Issue #701). Not in nixpkgs, so the
          # linux-x64 release tarball is pinned by version and hash here. Shipped on the native
          # machine only (nix/modules/terminal-browser.nix). See docs/reference/terminal-browser.md.
          (final: prev: {
            terminal-browser = prev.stdenv.mkDerivation (finalAttrs: {
              pname = "terminal-browser";
              version = "0.13.4";
              src = prev.fetchurl {
                url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${finalAttrs.version}/terminal-browser-linux-x64.tar.gz";
                hash = "sha256-YnfaqrqxZxGrPxlhzf+tnvrF5wrFXVB24shkltZJ06Q=";
              };
              # tarball の中身は terminal-browser/ の下にまとまっている
              # The tarball keeps everything under terminal-browser/
              sourceRoot = "terminal-browser";

              nativeBuildInputs = [ prev.autoPatchelfHook prev.makeWrapper ];
              # electron/pixel (Electron 本体)、chrome_crashpad_handler、ネイティブモジュール
              # pixel.node、同梱の .so が NEEDED に書いている共有ライブラリ。
              # Shared libraries listed as NEEDED by electron/pixel (the Electron binary),
              # chrome_crashpad_handler, the pixel.node native module, and the bundled .so files.
              buildInputs = with prev; [
                stdenv.cc.cc.lib
                glib
                nspr
                nss
                at-spi2-core
                cups
                dbus
                cairo
                gtk3
                pango
                libx11
                libxcomposite
                libxdamage
                libxext
                libxfixes
                libxrandr
                libxcb
                libxkbcommon
                libgbm
                expat
                systemd
                alsa-lib
              ];
              # Electron は GPU と Vulkan のライブラリを NEEDED ではなく dlopen で読むので、
              # rpath に足しておく (nixpkgs の electron の electronLibPath と同じ考え方)。
              # LD_LIBRARY_PATH にしないのは、terminal-browser が起動する herdr や ps に漏らさないため。
              # Electron dlopen()s its GPU and Vulkan libraries instead of listing them as NEEDED,
              # so add them to the rpath (same idea as electronLibPath in nixpkgs' electron).
              # Not LD_LIBRARY_PATH, which would leak into herdr, ps and friends it spawns.
              runtimeDependencies = with prev; [
                libGL
                vulkan-loader
                libdrm
                pciutils
                (lib.getLib systemd)
              ];

              dontConfigure = true;
              dontBuild = true;
              # 配布元が strip 済みの巨大な ELF をさらに strip しない
              # Don't re-strip the upstream, already-stripped Electron binaries
              dontStrip = true;

              # 起動スクリプト bin/terminal-browser は自分の置き場所を symlink を辿って求め、
              # その親ディレクトリを TERMINAL_BROWSER_DIST_ROOT にして electron/pixel を起動する。
              # 構成を崩さずに libexec の下へ丸ごと置き、bin にはそれを呼ぶラッパーだけを置く。
              # tty と ps は herdr のアダプタが pane と tty の対応を引くのに使うので、PATH の
              # 末尾に足しておく (利用者の PATH の優先順位は変えない)。
              # The bin/terminal-browser launcher resolves its own location through symlinks
              # and starts electron/pixel with the parent as TERMINAL_BROWSER_DIST_ROOT. Keep
              # the layout intact under libexec and only put a wrapper in bin. tty and ps are
              # used by the herdr adapter to map panes to ttys, so append them to PATH as a
              # fallback without changing the user's PATH precedence.
              installPhase = ''
                runHook preInstall
                mkdir -p $out/libexec/terminal-browser $out/bin
                cp -a . $out/libexec/terminal-browser/
                makeWrapper $out/libexec/terminal-browser/bin/terminal-browser $out/bin/terminal-browser \
                  --suffix PATH : ${prev.lib.makeBinPath [ prev.coreutils prev.procps ]}
                runHook postInstall
              '';

              meta = {
                description = "Browser that renders web pages inside the terminal with kitty graphics";
                homepage = "https://github.com/zenbu-labs/terminal-browser";
                license = prev.lib.licenses.mit;
                mainProgram = "terminal-browser";
                platforms = [ "x86_64-linux" ];
                sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
              };
            });
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
      # Home Manager configurations — per-host profile 分割
      # 環境差分 (GUI の有無・Windows 連携) は暗黙のドリフトではなく構造で表現する
      # Per-host profiles: environment differences (GUI, Windows interop)
      # are expressed in structure, not left to implicit drift.
      homeConfigurations =
        let
          mkHome = profile: home-manager.lib.homeManagerConfiguration {
            inherit pkgs;

            modules = [
              ./home.nix
            ];

            extraSpecialArgs = {
              inherit inputs profile;
            };
          };
        in
        {
          # Native Arch Linux (Hyprland) — 既存運用を変えないため名前は archie のまま
          # Keeps the historical name so the native machine's workflow is unchanged
          "archie" = mkHome "native";

          # Windows 11 + WSL2 (Arch) — GUI は host 側、シェルから内側を管理する
          # GUI lives on the Windows host; we own everything from the shell inward
          "archie-wsl" = mkHome "wsl";
        };

      packages.${system} = {
        # 自作ツールを `nix build .#standalone-check` で単体ビルドできるように出す
        # Expose the in-repo tool so `nix build .#standalone-check` works on its own
        standalone-check = pkgs.standalone-check;
        # herdr の Claude Code 用フックを `nix build .#herdr-claude-hook` で単体ビルドして確かめられるように出す
        # Expose the generated herdr hook so `nix build .#herdr-claude-hook` can inspect it on its own
        herdr-claude-hook = pkgs.herdr-claude-hook;
      };

      # `nix flake check` (`mise run nix:check`) で走る検査。CI の check ジョブは
      # `nix flake check --no-build` なので、評価だけして中身は実行しない。
      # Checks run by `nix flake check` (`mise run nix:check`). The CI check job uses
      # `nix flake check --no-build`, which evaluates them without running them.
      checks.${system}.herdr-claude-hook-entries = pkgs.runCommand "herdr-claude-hook-entries"
        {
          nativeBuildInputs = [ pkgs.jq ];
        } ''
        # 手書きのエントリが、herdr のインストーラが生成したエントリとずれていないかを見る (Issue #755)
        # Fail when the hand-written entry drifts from the one herdr's installer generates (Issue #755)
        bash ${./nix/checks/herdr_claude_hook_entries.sh} \
          ${pkgs.herdr-claude-hook}/settings.json \
          ${./.config/claude/settings.json}
        touch "$out"
      '';

      # shellcheck の入口: CI と mise の lint:shellcheck の両方がこれを呼ぶ (#665)。
      # 版の正は flake.lock の nixpkgs。runner や手元の PATH の shellcheck は使わない。
      # Single shellcheck entry point shared by CI and `mise run lint:shellcheck` (#665).
      # The version comes from the locked nixpkgs, never from whatever is on PATH.
      apps.${system}.shellcheck = {
        type = "app";
        meta.description = "Run shellcheck from the locked nixpkgs over every tracked *.sh";
        program = pkgs.lib.getExe (pkgs.writeShellApplication {
          name = "shellcheck-all";
          # git は ls-files にしか使わないので、perl や docs を引き込まない gitMinimal にする
          # git is only used for ls-files; gitMinimal avoids pulling perl and docs into the closure
          runtimeInputs = with pkgs; [ shellcheck gitMinimal findutils ];
          text = ''
            # どのディレクトリから呼ばれても、対象はリポジトリ全体の追跡済み *.sh
            # Always lint every tracked *.sh, wherever we are invoked from
            cd "$(git rev-parse --show-toplevel)"
            # CI のログで版を確かめられるように先に表示する
            # Print the version first so CI logs show which shellcheck ran
            shellcheck --version
            git ls-files '*.sh' | xargs --no-run-if-empty shellcheck
          '';
        });
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

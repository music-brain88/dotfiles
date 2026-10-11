{ config, pkgs, lib, ... }:

let
  # terminal-browser が install ファイルに書く導入先 (TERMINAL_BROWSER_DIST_ROOT の実パス)
  # The install root terminal-browser records in its install file (real path of TERMINAL_BROWSER_DIST_ROOT)
  distRoot = "${pkgs.terminal-browser}/libexec/terminal-browser";
in
{
  # terminal-browser: device-auth の承認ページを herdr の pane で開くブラウザ (Issue #701)。
  # native 機だけで読み込む (home.nix の profile == "native")。WSL 機では ConPTY が
  # kitty graphics のエスケープを通さないので描画できない (Issue #569)。
  # パッケージ本体は flake.nix の overlay。詳細は docs/reference/terminal-browser.md。
  # terminal-browser opens device-auth approval pages in a herdr pane (Issue #701).
  # Imported on the native machine only (profile == "native" in home.nix): on WSL the
  # ConPTY layer strips kitty graphics escapes, so it cannot render (Issue #569).
  # The package itself is the overlay in flake.nix. See docs/reference/terminal-browser.md.
  home.packages = [ pkgs.terminal-browser ];

  # スキルの自動リンクを止める。terminal-browser は初回の起動と、版か導入先が変わった後の
  # 最初の起動で、自分のスキルを ~/.claude/skills などへ symlink する。Nix では版を上げる
  # たびに store のパスが変わるので、止めないと毎回作り直される。このファイルの中身が
  # "no" ならリンクしない (cli/src/setup.ts の skillsDeclined())。
  # Stop the automatic skill links. On first launch, and on the first launch after the
  # version or install root changes, terminal-browser symlinks its skill into
  # ~/.claude/skills and friends. Under Nix the store path changes on every bump, so the
  # links would be recreated each time. A "no" here makes it skip linking
  # (skillsDeclined() in cli/src/setup.ts).
  xdg.stateFile."terminal-browser/skills-choice".text = "no\n";

  # 利用状況とクラッシュの報告 (PostHog) を両方止める (browser の telemetryOptedOutByEnv())。
  # settings.json でも止められるが、アプリが実行中に書き換えるので Nix の symlink にはしない。
  # herdr の pane は herdr サーバーの環境を継承するので、反映には herdr サーバーの再起動が要る。
  # Disable both usage and crash reporting (PostHog) via telemetryOptedOutByEnv() in the
  # browser. settings.json could do it too, but the app rewrites that file at runtime, so it
  # must not be a read-only Nix symlink. herdr panes inherit the herdr server's environment,
  # so restart the herdr server for this to take effect.
  home.sessionVariables.TERMINAL_BROWSER_NO_TELEMETRY = "1";

  # 古いプロファイルの掃除。プロファイルの置き場の名前には、導入先の実パスの sha256 の
  # 先頭 8 桁が付く (shared/src/paths.ts)。置き場は config (Electron のデータと Cookie)、
  # data (データベースと install)、state (ログ)、cache (favicon) の 4 つにできる。
  # 版を上げると名前が変わり、古いプロファイルが Cookie ごと残るので、ここで 4 つとも
  # 消す (版を上げた後は 1 回ログインし直すことになる)。
  # 消すのは次の条件をすべて満たすものだけ:
  #   - 名前が terminal-browser- と 16 進 8 桁だけ (-dev や -interop などは対象外)
  #   - data 側に install があり、そこに書かれた導入先が /nix/store/ で始まる
  #     (store の外の導入先 = 試験の版や手で入れた版のプロファイルは消さない)
  #   - その導入先が今のパッケージの導入先と違う
  # 削除は home-manager の run を通すので、dry-run では何も消さない。
  # Clean up stale profiles. Profile directories carry the first 8 hex digits of the
  # sha256 of the real install root (shared/src/paths.ts). A profile can live in four
  # places: config (Electron data and cookies), data (database and install), state (logs)
  # and cache (favicons). Every version bump changes the name and leaves the old profile
  # behind, cookies included, so remove all four here (the user logs in again once after a
  # bump). Only directories meeting all of these are removed:
  #   - named exactly terminal-browser-<8 hex digits> (-dev, -interop, ... are left alone)
  #   - the data dir has an install file whose install root starts with /nix/store/
  #     (profiles of installs outside the store, e.g. a trial or manual install, are kept)
  #   - that install root differs from the current package's
  # Deletion goes through home-manager's run, so a dry run removes nothing.
  home.activation.cleanTerminalBrowserProfiles = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    tb_current=${lib.escapeShellArg distRoot}
    for tb_data in ${lib.escapeShellArg config.xdg.dataHome}/terminal-browser-*; do
      tb_name="''${tb_data##*/}"
      [[ "$tb_name" =~ ^terminal-browser-[0-9a-f]{8}$ ]] || continue
      [[ -d "$tb_data" && ! -L "$tb_data" ]] || continue
      # install が無いプロファイルは導入先が分からないので消さない
      # Without an install file the install root is unknown, so keep the profile
      [[ -f "$tb_data/install" ]] || continue
      tb_install="$(< "$tb_data/install")"
      [[ "$tb_install" == /nix/store/* ]] || continue
      [[ "$tb_install" != "$tb_current" ]] || continue
      # data 側 (install を持つ側) を最後に消し、途中で止まっても次の activation で続きを消せるようにする
      # Remove the data dir (which holds install) last, so an interrupted run is finished next time
      for tb_dir in \
        ${lib.escapeShellArg config.xdg.configHome}/"$tb_name" \
        ${lib.escapeShellArg config.xdg.stateHome}/"$tb_name" \
        ${lib.escapeShellArg config.xdg.cacheHome}/"$tb_name" \
        "$tb_data"; do
        if [[ -e "$tb_dir" || -L "$tb_dir" ]]; then
          noteEcho "Removing stale terminal-browser profile $tb_dir (install root: $tb_install)"
          run rm -rf $VERBOSE_ARG -- "$tb_dir"
        fi
      done
    done
    unset tb_current tb_data tb_name tb_install tb_dir
  '';
}

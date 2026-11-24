{ config, lib, pkgs, ... }:

{
  # herdr - agent multiplexer (tmux の後継 / successor to tmux)
  # pkgs.herdr は flake.nix の overlay 経由で新しい nixpkgs から供給される
  # pkgs.herdr comes from a newer nixpkgs pin via the overlay in flake.nix
  home.packages = with pkgs; [
    herdr
    # herdr-ctx: 司令塔と決定者が見る盤面の値を集める計器 (tools/herdr-ctx、Rust、flake overlay で定義)。
    # 各 agent の context 使用率と、決定者宛ての open のレビュー依頼を集める (Issue #784, #805)。
    # herdr に依存する道具なので dev-tools.nix ではなくここで配る (Issue #784)
    # In-repo Rust instrument gathering the board's values: each agent's context usage and the
    # decision maker's open review requests (Issue #784, #805). It depends on herdr, so it ships
    # here rather than in dev-tools.nix (Issue #784)
    herdr-ctx
  ];

  # herdr-ctx watch の常駐。~/.herdr/ctx/agents.json を書き、閾値を跨いだ agent を知らせる (Issue #784)。
  # 別のスレッドで、レビュー依頼を 5 分ごとに ~/.herdr/ctx/reviews.json に書く (Issue #805)。
  # home-manager の service にするのは、systemd.user.startServices の既定で switch のときに起動され、
  # native と wsl の両方に届くから。生の unit ファイルは機械ごとの enable が要り、mount も native だけ。
  # herdr CLI は既定のソケットを見るので、ソケットの env は要らない。
  # PATH の gh はレビュー依頼の取得に使う。認証は gh が keyring から読む。native 機では user service から
  # keyring を読めることを確かめてある。
  # PATH の busctl(systemd)は、keyring がロックされているかを読むのに使う。linger が有効な機械では、この
  # service がログインの前から動く。keyring がロックされたまま gh を呼び続けると、gnome-keyring-daemon が
  # 解錠のダイアログの起動に失敗するたびに記述子を 1 個失い、上限に達すると keyring を開けなくなる。
  # そのため、ロックされている周期は gh を呼ばずに取得を見送る (Issue #823)。
  # keyring の状態を確かめられない機械(Secret Service が無い wsl 機など)では、今までどおり gh を呼ぶ。
  # wsl 機で gh が認証を読めるかは未確認である。どの場合も、agent の一覧と通知は動き続ける。
  # Resident herdr-ctx watch: writes ~/.herdr/ctx/agents.json and notifies on crossings (Issue #784).
  # Another thread writes review requests to ~/.herdr/ctx/reviews.json every 5 minutes (Issue #805).
  # A home-manager service starts on switch through the systemd.user.startServices default and
  # reaches both native and wsl; a raw unit file needs a per-machine enable and mounts on native only.
  # The herdr CLI finds its default socket by itself, so no socket env is needed.
  # gh on PATH fetches the review requests and reads its token from the keyring. A user service can
  # read the keyring on the native machine.
  # busctl (systemd) on PATH reads whether the keyring is locked. With linger enabled this service
  # runs before login. Calling gh over and over against a locked keyring costs gnome-keyring-daemon
  # one descriptor per failed unlock dialog, and at the limit it can no longer open the keyring.
  # So a cycle with a locked keyring skips gh (Issue #823).
  # Where the keyring's state cannot be checked (e.g. wsl without a Secret Service), gh is called as
  # before. Whether gh can read its token on wsl is unverified. In every case the agent list and
  # notices keep running.
  systemd.user.services.herdr-ctx-watch = {
    Unit.Description = "herdr-ctx watch: 各 agent の context 使用率を記録して知らせ、レビュー依頼を集める";
    Service = {
      ExecStart = "${pkgs.herdr-ctx}/bin/herdr-ctx watch";
      Environment = [ "PATH=${lib.makeBinPath [ pkgs.herdr pkgs.gh pkgs.systemd ]}" ];
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # herdr config symlink (keybind は旧 tmux 設定互換 / tmux-compatible keybindings)
  home.file.".config/herdr/config.toml".source = ../../.config/herdr/config.toml;

  # herdr 公式の Claude Code 用フック (Issue #755)。スクリプトは flake.nix の overlay が
  # ビルド時に公式インストーラで生成する (pkgs.herdr-claude-hook)。呼び出すエントリは
  # .config/claude/settings.json の SessionStart に手書きしてあり、ずれは
  # checks.herdr-claude-hook-entries (`mise run nix:check`) が見つける。
  # home.nix の ".claude" の recursive マウントの下に、statusline-command.sh と同じ形の個別エントリで足す。
  # .config/claude/ には hooks/ が無いので、recursive マウントとは衝突しない。
  # herdr's official Claude Code hook (Issue #755). The overlay in flake.nix generates the
  # script with the official installer at build time (pkgs.herdr-claude-hook). The entry that
  # calls it is hand-written under SessionStart in .config/claude/settings.json, and
  # checks.herdr-claude-hook-entries (`mise run nix:check`) catches drift between the two.
  # Added under the recursive ".claude" mount in home.nix as an individual entry, same pattern
  # as statusline-command.sh. .config/claude/ has no hooks/, so it does not collide with the mount.
  home.file.".claude/hooks/herdr-agent-state.sh".source =
    "${pkgs.herdr-claude-hook}/hooks/herdr-agent-state.sh";

  # device-auth 承認 URL を、herdr の中では terminal-browser の pane に開く $BROWSER ラッパー
  # (Issue #523, #701)。terminal-browser は native 機だけに入る (nix/modules/terminal-browser.nix)。
  # 見つからない機械ではラッパーが GUI ブラウザへフォールバックする。
  # $BROWSER wrapper that opens device-auth approval URLs in a terminal-browser pane inside
  # herdr (Issue #523, #701). terminal-browser is installed on the native machine only
  # (nix/modules/terminal-browser.nix); elsewhere the wrapper falls back to the GUI browser.
  home.file.".local/bin/device_auth_browser" = {
    source = ../../.config/herdr/scripts/device_auth_browser.sh;
    executable = true;
  };
}

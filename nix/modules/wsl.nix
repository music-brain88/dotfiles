{ config, pkgs, lib, ... }:

let
  # Windows 側 Alacritty 用の設定を base + windows 差分のマージで生成する。
  # コメントは落ちるが、配布物は生成物なのでソース (リポジトリ側 TOML) が真実。
  # Generate the Windows-side Alacritty config by merging base + windows overrides.
  # Comments are dropped, but the deployed file is an artifact; the repo TOMLs are the truth.
  tomlFormat = pkgs.formats.toml { };
  alacrittyBase = builtins.fromTOML (builtins.readFile ../../.config/alacritty/alacritty.toml);
  alacrittyOverrides = builtins.fromTOML (builtins.readFile ../../.config/alacritty/windows.toml);
  alacrittyForWindows = tomlFormat.generate "alacritty-windows.toml"
    (lib.recursiveUpdate alacrittyBase alacrittyOverrides);

  # Windows 側のパスは cmd.exe から動的に検出する (Windows ユーザー名をリポジトリに焼き込まない)。
  # interop 無効などで検出に失敗しても activation 全体は落とさず、警告して skip する。
  # Detect Windows-side paths via cmd.exe at activation time (no Windows username in the repo).
  # If detection fails (e.g. interop disabled), warn and skip instead of failing activation.
  winEnvSnippet = ''
    win_env() {
      /mnt/c/Windows/System32/cmd.exe /C "echo %$1%" 2>/dev/null | ${pkgs.coreutils}/bin/tr -d "\r" || true
    }
  '';
in
{
  # WSL でも Alacritty は WSLg 経由の Linux 版を主とする。
  # Windows 版 Alacritty は ConPTY 読み取りの取りこぼしで herdr の画面切り替え時に
  # 描画破損が起きるため (alacritty/alacritty#8057)、PTY を Linux ネイティブに保つ。
  # パッケージは native と同じく pacman 管理 (Nix の EGL は WSLg の GL スタックと
  # 噛み合わないため)。Nix が持つのはこの設定 symlink だけ。
  # On WSL the primary Alacritty is the Linux build via WSLg. The Windows build
  # corrupts rendering on herdr screen switches due to dropped ConPTY updates
  # (alacritty/alacritty#8057), so keep the PTY Linux-native.
  # The package comes from pacman as on the native machine (nixpkgs' EGL does not
  # bind to WSLg's GL stack); Nix only owns this config symlink.
  home.file.".config/alacritty" = {
    source = ../../.config/alacritty;
    recursive = true;
  };

  # Windows 側ショートカットから呼ぶランチャー。Xwayland 固定 (wslg#1386 回避) と
  # fcitx5 (XIM) の起動をまとめる。alacritty / fcitx5 本体は pacman 管理。
  # Launcher invoked from the Windows-side shortcut. Pins Xwayland (avoids
  # wslg#1386) and starts fcitx5 (XIM). alacritty / fcitx5 come from pacman.
  home.file.".local/bin/wslg-alacritty" = {
    source = ../../.config/wsl/scripts/wslg-alacritty;
    executable = true;
  };

  # Obsidian vault: 実体は Windows 側 (Cowork / Obsidian Sync の都合)。
  # WSL からは正規パス ~/Documents/Obsidian を symlink で成立させ、
  # session-log 等のスキルを無変更で両環境動作させる。
  # The Obsidian vault lives on the Windows side (Cowork / Obsidian Sync).
  # A symlink provides the canonical path ~/Documents/Obsidian inside WSL,
  # so skills like session-log work unchanged on both machines.
  home.activation.linkObsidianVault = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    ${winEnvSnippet}
    win_home_raw="$(win_env USERPROFILE)"
    win_home=""
    if [ -n "$win_home_raw" ]; then
      # wslpath 自体の不在・失敗でも activation を落とさない (警告して skip)
      # Never abort activation on missing/failing wslpath; warn and skip instead
      win_home="$(/usr/bin/wslpath "$win_home_raw" 2>/dev/null || true)"
    fi
    if [ -z "$win_home" ]; then
      echo "wsl.nix: could not resolve %USERPROFILE%; skipping Obsidian vault symlink" >&2
    else
      vault="$win_home/Documents/music.brain88"
      link="$HOME/Documents/Obsidian"
      if [ ! -d "$vault" ]; then
        echo "wsl.nix: vault not found at $vault; skipping Obsidian vault symlink" >&2
      elif [ -e "$link" ] && [ ! -L "$link" ]; then
        # 実ディレクトリを上書きすると ln -sfn が中に入れ子リンクを作るため手を出さない
        # Never touch a real directory: ln -sfn would create a nested link inside it
        echo "wsl.nix: $link exists and is not a symlink; refusing to replace it" >&2
      else
        mkdir -p "$HOME/Documents"
        ln -sfn "$vault" "$link"
      fi
    fi
  '';

  # fcitx5 の入力メソッド構成 (US キーボード + Mozc) のシード。
  # fcitx5 は実行時に profile を書き換えるため symlink にせず「無ければコピー」する
  # (home.nix の seedCopilotConfig と同じパターン)。
  # Seed the fcitx5 input-method profile (US keyboard + Mozc). fcitx5 rewrites
  # this file at runtime, so copy-if-absent instead of symlinking
  # (same pattern as seedCopilotConfig in home.nix).
  home.activation.seedFcitx5Profile = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.config/fcitx5/profile"
    if [ ! -f "$target" ] || [ -L "$target" ]; then
      mkdir -p "$(dirname "$target")"
      rm -f "$target"
      cp ${../../.config/fcitx5/profile} "$target"
      chmod 644 "$target"
    fi
  '';

  # Windows 版 Alacritty はフォールバックとして残し、設定だけを switch 時に
  # 配布してドリフトを防ぐ (live_config_reload で即反映)。
  # The Windows-native Alacritty is kept as a fallback; only its config is
  # deployed on switch to prevent drift (live_config_reload applies it).
  home.activation.deployAlacrittyConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    ${winEnvSnippet}
    appdata_raw="$(win_env APPDATA)"
    appdata=""
    if [ -n "$appdata_raw" ]; then
      # 解決失敗のまま進むと target が "/alacritty/..." になり mkdir がルート直下を叩く
      # An unresolved path would make target "/alacritty/..." and mkdir hit the root dir
      appdata="$(/usr/bin/wslpath "$appdata_raw" 2>/dev/null || true)"
    fi
    if [ -z "$appdata" ]; then
      echo "wsl.nix: could not resolve %APPDATA%; skipping Alacritty config deploy" >&2
    else
      target="$appdata/alacritty/alacritty.toml"
      mkdir -p "$appdata/alacritty"
      if ! ${pkgs.diffutils}/bin/cmp -s ${alacrittyForWindows} "$target"; then
        cp -f ${alacrittyForWindows} "$target"
        chmod 644 "$target"
        echo "wsl.nix: deployed Alacritty config to $target"
      fi
    fi
  '';
}

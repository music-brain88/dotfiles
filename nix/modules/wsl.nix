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
  # Obsidian vault: 実体は Windows 側 (Cowork / Obsidian Sync の都合)。
  # WSL からは正規パス ~/Documents/Obsidian を symlink で成立させ、
  # session-log 等のスキルを無変更で両環境動作させる。
  # The Obsidian vault lives on the Windows side (Cowork / Obsidian Sync).
  # A symlink provides the canonical path ~/Documents/Obsidian inside WSL,
  # so skills like session-log work unchanged on both machines.
  home.activation.linkObsidianVault = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    ${winEnvSnippet}
    win_home_raw="$(win_env USERPROFILE)"
    if [ -z "$win_home_raw" ]; then
      echo "wsl.nix: could not detect %USERPROFILE%; skipping Obsidian vault symlink" >&2
    else
      win_home="$(/usr/bin/wslpath "$win_home_raw")"
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

  # Alacritty は「ピクセルは host」方針で Windows ネイティブのまま。
  # 設定だけを switch 時に配布してドリフトを防ぐ (live_config_reload で即反映)。
  # Alacritty stays Windows-native ("pixels belong to the host").
  # Only the config is deployed on switch to prevent drift (live_config_reload applies it).
  home.activation.deployAlacrittyConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    ${winEnvSnippet}
    appdata_raw="$(win_env APPDATA)"
    if [ -z "$appdata_raw" ]; then
      echo "wsl.nix: could not detect %APPDATA%; skipping Alacritty config deploy" >&2
    else
      appdata="$(/usr/bin/wslpath "$appdata_raw")"
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

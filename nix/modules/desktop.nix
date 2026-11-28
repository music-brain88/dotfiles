{ config, pkgs, ... }:

{
  # ネイティブ Arch (Hyprland) 専用の GUI 設定群。WSL profile では import されない。
  # GUI configs for native Arch (Hyprland) only; not imported by the WSL profile.
  home.file = {
    # Hyprland config
    ".config/hypr" = {
      source = ../../.config/hypr;
      recursive = true;
    };

    # systemd user units (Hyprland session target)
    ".config/systemd/user" = {
      source = ../../.config/systemd/user;
      recursive = true;
    };

    # Waybar config
    ".config/waybar" = {
      source = ../../.config/waybar;
      recursive = true;
    };

    # Alacritty config (併存期間中のフォールバック。WSL では Windows 側 Alacritty に配布する。nix/modules/wsl.nix 参照)
    # Alacritty config (fallback during the WezTerm migration; on WSL this is deployed to the Windows side, see nix/modules/wsl.nix)
    ".config/alacritty" = {
      source = ../../.config/alacritty;
      recursive = true;
    };

    # WezTerm config (native Arch のメインターミナル。wezterm.lua は両マシン共通の真実、Windows 側は wsl.nix が配布)
    # WezTerm config (primary terminal on native Arch; wezterm.lua is the single source of truth shared with Windows, distributed there by wsl.nix)
    ".config/wezterm" = {
      source = ../../.config/wezterm;
      recursive = true;
    };

    # Wofi config
    ".config/wofi" = {
      source = ../../.config/wofi;
      recursive = true;
    };

    # Mako config
    ".config/mako" = {
      source = ../../.config/mako;
      recursive = true;
    };

    # MPD config
    ".config/mpd" = {
      source = ../../.config/mpd;
      recursive = true;
    };

    # ncmpcpp config
    ".config/ncmpcpp" = {
      source = ../../.config/ncmpcpp;
      recursive = true;
    };

    # fontconfig
    ".config/fontconfig" = {
      source = ../../.config/fontconfig;
      recursive = true;
    };

    # 壁紙 (Issue #840)。tools/wallpaper/ の SVG から Nix が描いた PNG を固定パスに置く。
    # .config/hypr/hyprpaper.conf はストアのパスではなくこの固定パスを指す。
    # Wallpaper (Issue #840): the PNG Nix renders from tools/wallpaper/ is placed at a fixed path,
    # which .config/hypr/hyprpaper.conf points to instead of a store path.
    ".local/share/wallpapers/mocha_arch.png".source = "${pkgs.mocha-arch-wallpaper}/mocha_arch.png";
  };
}

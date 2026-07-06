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

    # Alacritty config (WSL では Windows 側 Alacritty に配布する。nix/modules/wsl.nix 参照)
    # Alacritty config (on WSL this is deployed to the Windows side; see nix/modules/wsl.nix)
    ".config/alacritty" = {
      source = ../../.config/alacritty;
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
  };
}

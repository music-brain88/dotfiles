{ config, pkgs, ... }:

{
  # Base system packages
  # Minimal set - other packages are in specialized modules
  # curl, wget, unzip: dev-tools.nix
  # git: git.nix
  # cmake, gnumake: dev-tools.nix
  # htop: dev-tools.nix
  home.packages = with pkgs; [
    # Core utilities (not duplicated elsewhere)
    gnutar
    gzip

    # Build tools (pkg-config, protobuf not in other modules)
    pkg-config
    protobuf

    # Notification system
    mako
    libnotify

    # Wayland utilities / Wayland ユーティリティ
    wl-clipboard # wl-copy / wl-paste (clipboard CLI) / クリップボード操作コマンド
    cliphist # clipboard history / クリップボード履歴
    hypridle # idle daemon (auto-lock, screen off) / アイドル時の自動ロック・画面消灯

    # Additional utilities
    tree
    which
    file
  ];
}

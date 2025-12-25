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

    # Additional utilities
    tree
    which
    file
  ];
}

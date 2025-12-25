{ config, pkgs, ... }:

{
  # Base system packages
  # Replaces setup_base.sh functionality
  home.packages = with pkgs; [
    # Core utilities
    curl
    wget
    git
    gnutar
    gzip
    unzip

    # Build tools
    cmake
    pkg-config
    protobuf

    # Notification system
    mako
    libnotify

    # Additional utilities
    htop
    tree
    which
    file
    gnumake
  ];
}

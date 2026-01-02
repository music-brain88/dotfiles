{ config, pkgs, ... }:

{
  # Font packages
  home.packages = with pkgs; [
    # Programming font (monospace) - for terminal and editors
    hackgen-nf-font

    # System UI font (sans-serif) - for browser and desktop
    source-han-sans
  ];
}

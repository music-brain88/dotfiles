{ config, pkgs, ... }:

{
  # Font packages
  home.packages = with pkgs; [
    hackgen-nf-font
  ];
}

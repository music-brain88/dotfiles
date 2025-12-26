{ config, pkgs, inputs, ... }:

{
  # CI用の最小構成
  home.username = "archie";
  home.homeDirectory = "/home/archie";
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;

  # Import only base module for minimal profile
  imports = [
    ../modules/base.nix
  ];

  nixpkgs.config.allowUnfree = true;
  xdg.enable = true;
}

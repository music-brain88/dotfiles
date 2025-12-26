{ config, pkgs, inputs, ... }:

{
  # CI用: Shell toolsのみをテスト
  home.username = "archie";
  home.homeDirectory = "/home/archie";
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;

  imports = [
    ../modules/base.nix
    ../modules/shell.nix
  ];

  nixpkgs.config.allowUnfree = true;
  xdg.enable = true;
}

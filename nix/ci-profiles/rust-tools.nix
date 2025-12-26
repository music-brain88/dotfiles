{ config, pkgs, inputs, ... }:

{
  # CI用: Rust toolsのみをテスト
  home.username = "archie";
  home.homeDirectory = "/home/archie";
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;

  imports = [
    ../modules/base.nix
    ../modules/rust-tools.nix
  ];

  nixpkgs.config.allowUnfree = true;
  xdg.enable = true;
}

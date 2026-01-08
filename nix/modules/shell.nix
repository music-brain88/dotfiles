{ config, pkgs, lib, ... }:

{
  # Fish shell - package only, config via symlinks
  home.packages = with pkgs; [
    fish
    starship
    fishPlugins.done
    fishPlugins.forgit
    fishPlugins.z
    fishPlugins.bass
  ];

  # Fish config symlinks (matching deploy.sh)
  home.file.".config/fish/config.fish".source = ../../.config/fish/config.fish;
  home.file.".config/fish/functions/fish_user_key_bindings.fish".source = ../../.config/fish/functions/fish_user_key_bindings.fish;
  home.file.".config/fish/completions" = {
    source = ../../.config/fish/completions;
    recursive = true;
  };

  # Starship config symlink
  xdg.configFile."starship.toml".source = ../../.config/starship/starship.toml;
}

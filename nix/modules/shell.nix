{ config, pkgs, lib, ... }:

{
  # Fish shell configuration
  # Use existing fish config files from dotfiles
  programs.fish = {
    enable = true;
  };

  # Link existing fish config files (use mkForce to override programs.fish generated config)
  xdg.configFile."fish/config.fish".source = lib.mkForce ../../.config/fish/config.fish;
  xdg.configFile."fish/completions".source = ../../.config/fish/completions;
  xdg.configFile."fish/functions".source = ../../.config/fish/functions;

  # Starship prompt configuration
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    # Use existing starship config file from dotfiles
  };

  # Link existing starship config
  xdg.configFile."starship.toml".source = ../../.config/starship/starship.toml;

  # Fisher (Fish plugin manager) - using Home Manager's fish plugin system instead
  # Fisher functionality is now handled by Home Manager's programs.fish.plugins

  # Additional shell packages
  home.packages = with pkgs; [
    # Fish-related tools
    fish
    fishPlugins.done
    fishPlugins.fzf-fish
    fishPlugins.forgit
  ];
}

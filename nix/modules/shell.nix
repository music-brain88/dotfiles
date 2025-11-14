{ config, pkgs, ... }:

{
  # Fish shell configuration
  # Replaces setup_fish.sh functionality
  programs.fish = {
    enable = true;

    # Fish plugins using Home Manager
    plugins = [
      # z - directory jumper
      {
        name = "z";
        src = pkgs.fetchFromGitHub {
          owner = "jethrokuan";
          repo = "z";
          rev = "85f863f20f24faf675827fb00f3a4e15c7838d76";
          sha256 = "sha256-+FUBM7CodtZrYKqU542fQD+ZDGrd2438trKM0tIESs0=";
        };
      }

      # bass - use bash utilities in fish
      {
        name = "bass";
        src = pkgs.fetchFromGitHub {
          owner = "edc";
          repo = "bass";
          rev = "df4a1ebf8c0536e861bb4ec0c0c0f78bb6e8c391";
          sha256 = "sha256-FL8P9kqcPvJw1hSMhfwGEA3MgHjKx9vJ+ea0/HXnuVI=";
        };
      }
    ];

    # Fish shell initialization
    interactiveShellInit = ''
      # Disable fish greeting
      set fish_greeting

      # Aliases
      alias ls='eza'
      alias ll='eza -l'
      alias la='eza -la'
      alias cat='bat'
      alias find='fd'
      alias ps='procs'
      alias du='dust'
      alias grep='rg'

      # Git aliases
      alias g='git'
      alias gs='git status'
      alias ga='git add'
      alias gc='git commit'
      alias gp='git push'
      alias gl='git log --oneline --graph'
      alias gd='git diff'

      # Set default editor
      set -gx EDITOR nvim
      set -gx VISUAL nvim
    '';

    # Fish functions
    functions = {
      # Custom fish functions can be added here
    };
  };

  # Starship prompt configuration
  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    # Starship settings (can be customized)
    settings = {
      # Load existing starship config if present
      # Or use inline configuration
      add_newline = true;

      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };

      # AWS module configuration
      aws = {
        format = "on [$symbol($profile )(\\($region\\) )]($style)";
        symbol = "☁️ ";
      };

      # Git branch
      git_branch = {
        symbol = " ";
        truncation_length = 20;
      };

      # Git status
      git_status = {
        conflicted = "🏳";
        ahead = "🏎💨";
        behind = "😰";
        diverged = "😵";
        untracked = "🤷";
        stashed = "📦";
        modified = "📝";
        staged = "[++\\($count\\)](green)";
        renamed = "👅";
        deleted = "🗑";
      };

      # Directory
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };

      # Language versions
      nodejs = {
        format = "via [ $version](bold green) ";
      };

      python = {
        format = "via [ $version](bold blue) ";
      };

      rust = {
        format = "via [ $version](bold red) ";
      };
    };
  };

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

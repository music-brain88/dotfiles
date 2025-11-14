{ config, pkgs, ... }:

{
  # Tmux configuration
  # Replaces setup_tmux.sh functionality
  programs.tmux = {
    enable = true;

    # Use tmux 3.x
    terminal = "screen-256color";

    # Set prefix to Ctrl-a (like screen)
    prefix = "C-a";

    # Start window numbering at 1
    baseIndex = 1;

    # Enable mouse support
    mouse = true;

    # Increase scrollback buffer size
    historyLimit = 10000;

    # Enable focus events
    focusEvents = true;

    # Escape time for neovim
    escapeTime = 0;

    # Additional tmux configuration
    extraConfig = ''
      # True color support
      set -ga terminal-overrides ",*256col*:Tc"
      set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'

      # Pane navigation with vim-like keys
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Pane resizing with vim-like keys
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Split panes using | and -
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Reload config file
      bind r source-file ~/.config/tmux/tmux.conf \; display "Tmux config reloaded!"

      # Enable vi mode
      setw -g mode-keys vi

      # Copy mode vim-like bindings
      bind-key -T copy-mode-vi 'v' send -X begin-selection
      bind-key -T copy-mode-vi 'y' send -X copy-selection-and-cancel

      # Status bar configuration
      set -g status-position bottom
      set -g status-justify left
      set -g status-style 'bg=colour234 fg=colour137'
      set -g status-left ""
      set -g status-right '#[fg=colour233,bg=colour241,bold] %Y-%m-%d #[fg=colour233,bg=colour245,bold] %H:%M:%S '
      set -g status-right-length 50
      set -g status-left-length 20

      # Window status
      setw -g window-status-current-style 'fg=colour81 bg=colour238 bold'
      setw -g window-status-current-format ' #I#[fg=colour250]:#[fg=colour255]#W#[fg=colour50]#F '
      setw -g window-status-style 'fg=colour138 bg=colour235'
      setw -g window-status-format ' #I#[fg=colour237]:#[fg=colour250]#W#[fg=colour244]#F '

      # Pane borders
      set -g pane-border-style 'fg=colour238'
      set -g pane-active-border-style 'fg=colour81'

      # Message style
      set -g message-style 'fg=colour232 bg=colour166 bold'
    '';

    # Tmux plugins using Home Manager
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      resurrect
      continuum
      vim-tmux-navigator
    ];
  };

  # Symlink existing tmux config if it exists
  # This allows using existing .tmux.conf alongside Nix configuration
  home.file.".config/tmux/tmux.conf.local" = {
    source = if builtins.pathExists ../../.tmux.conf
      then ../../.tmux.conf
      else pkgs.writeText "empty-tmux-conf" "";
    recursive = false;
  };
}

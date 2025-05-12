#!/bin/bash

set -euo pipefail


echo "Creating symlinks..."

DOTFILES_DIR="$HOME/dotfiles"

# XDG_CONFIG_HOMEが設定されていたら
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"


# Create necessary directories
mkdir -p "${XDG_CONFIG_HOME}/nvim"
mkdir -p "${XDG_CONFIG_HOME}/claude"
mkdir -p "${XDG_CONFIG_HOME}/fish"
mkdir -p "${XDG_CONFIG_HOME}/alacritty"
mkdir -p "${XDG_CONFIG_HOME}/starship"
mkdir -p "${XDG_CONFIG_HOME}/eww"
mkdir -p "${XDG_CONFIG_HOME}/hypr/scripts"

# Create symlinks
ln -snfv "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
ln -snfv "$DOTFILES_DIR/.config/nvim/init.lua" "$HOME/.config/nvim/init.lua"
ln -snfv "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

ln -snfv "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

ln -snfv "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
ln -snfv "$DOTFILES_DIR/.config/starship/starship.toml" "$HOME/.config/starship.toml"
ln -snfv "$DOTFILES_DIR/.config/fish/config.fish" "$HOME/.config/fish/config.fish"

ln -snfv "$DOTFILES_DIR/.config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"


# eww
ln -snfv "$DOTFILES_DIR/.config/eww/eww.yuck" "$HOME/.config/eww/eww.yuck"
ln -snfv "$DOTFILES_DIR/.config/eww/eww.scss" "$HOME/.config/eww/eww.scss"

# hypr
ln -snfv "$DOTFILES_DIR/.config/hypr/scripts/notifications.sh" "$HOME/.config/hypr/scripts/notifications.sh"
ln -snfv "$DOTFILES_DIR/.config/hypr/scripts/window-switcher.py" "$HOME/.config/hypr/scripts/window-switcher.py"

echo "Symlinks created."

#!/bin/bash

set -euo pipefail


echo "Creating symlinks..."

DOTFILES_DIR="$HOME/dotfiles"

# XDG_CONFIG_HOMEが設定されていたら
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"


# Create necessary directories
mkdir -p "${XDG_CONFIG_HOME}/nvim"
mkdir -p "${XDG_CONFIG_HOME}/fish"
mkdir -p "${XDG_CONFIG_HOME}/alacritty"
mkdir -p "${XDG_CONFIG_HOME}/starship"

# Create symlinks
ln -snfv "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
ln -snfv "$DOTFILES_DIR/.config/nvim/init.lua" "$HOME/.config/nvim/init.lua"
ln -snfv "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

ln -snfv "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
ln -snfv "$DOTFILES_DIR/.config/starship/starship.toml" "$HOME/.config/starship.toml"
ln -snfv "$DOTFILES_DIR/.config/fish/config.fish" "$HOME/.config/fish/config.fish"

ln -snfv "$DOTFILES_DIR/.config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

echo "Symlinks created."

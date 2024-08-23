#!/bin/bash

set -euo pipefail


echo "Creating symlinks..."

DOTFILES_DIR="$HOME/dotfiles"

# 必要なディレクトリを作成
mkdir -p ~/.config/nvim
mkdir -p ~/.config/fish
mkdir -p ~/.config/alacritty
mkdir -p ~/.config/starship
mkdir -p ~/.config/rofi
mkdir -p ~/.config/i3
mkdir -p ~/.config/polybar
mkdir -p ~/.config/mpd
mkdir -p ~/.config/ncmpcpp

# Create symlinks
ln -snfv "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
ln -snfv "$DOTFILES_DIR/.config/nvim/init.lua" "$HOME/.config/nvim/init.lua"
ln -snfv "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

ln -snfv "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
ln -snfv "$DOTFILES_DIR/.config/starship/starship.toml" "$HOME/.config/starship.toml"
ln -snfv "$DOTFILES_DIR/.config/fish/config.fish" "$HOME/.config/fish/config.fish"

ln -snfv "$DOTFILES_DIR/.config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

echo "Symlinks created."

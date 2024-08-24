#!/bin/bash

set -euo pipefail


echo "Creating symlinks..."

DOTFILES_DIR="$HOME/dotfiles"


# Create symlinks
ln -snfv "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
ln -snfv "$DOTFILES_DIR/.config/nvim/init.lua" "$HOME/.config/nvim/init.lua"
ln -snfv "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

ln -snfv "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
ln -snfv "$DOTFILES_DIR/.config/starship/starship.toml" "$HOME/.config/starship.toml"
ln -snfv "$DOTFILES_DIR/.config/fish/config.fish" "$HOME/.config/fish/config.fish"

ln -snfv "$DOTFILES_DIR/.config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

echo "Symlinks created."

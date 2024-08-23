#!/bin/bash

set -euo pipefail


echo "Setting up Neovim..."


NVIM_CONFIG_DIR="$HOME/.config/nvim"
DEIN_DIR="$HOME/.cache/dein"
DEIN_INSTALLER="$DEIN_DIR/installer.sh"

# Ensure Neovim is installed
if ! command -v nvim &> /dev/null; then
    echo "Neovim not found. Please install Neovim first."
    exit 1
fi

# Create Neovim config directory if it doesn't exist

mkdir -p "$NVIM_CONFIG_DIR"


# Install dein if not already installed
if [ ! -d "$DEIN_DIR" ]; then
    echo "Installing dein..."
    curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > "$DEIN_INSTALLER"
    sh "$DEIN_INSTALLER" "$DEIN_DIR"
    rm "$DEIN_INSTALLER"
fi

# Deno install
if command -v deno > /dev/null 2>&1; then
  cargo install deno --locked
else
  echo "Deno not found. Checking for Cargo..."
  # deno install
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing Deno..."
    cargo install deno --locked
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi

# Install plugins using dein
nvim --headless +"call dein#install()" +qall

echo "Neovim setup completed."

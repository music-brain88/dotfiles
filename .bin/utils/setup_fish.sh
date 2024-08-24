#!/bin/bash

set -euo pipefail


echo "Setting up Fish shell..."

FISH_CONFIG_DIR="$HOME/.config/fish"

# Ensure Fish is installed
if ! command -v fish &> /dev/null; then
    echo "Fish shell not found. Please install Fish first."
    exit 1
  else
    echo "Fish shell found. Skipping..."
fi

# Create Fish config directory if it doesn't exist
mkdir -p "$FISH_CONFIG_DIR/functions"

# Install Fisher (plugin manager for Fish)
if command -v fisher &> /dev/null; then
    echo "Fisher already installed. Skipping..."
else
    echo "Installing Fisher..."
    curl https://git.io/fisher --create-dirs -sLo ~/.config/fish/functions/fisher.fish
    echo "Fisher installed."
fi

# Install Fish plugins (add your preferred plugins here)
fish -c "fisher install jethrokuan/z"
fish -c "fisher install edc/bass"

# starship install
if command -v cargo > /dev/null 2>&1; then
  cargo install starship
else
  echo "Cargo not found. Please install Rust first."
fi



echo "Fish shell setup completed."

#!/bin/bash

set -euo pipefail


echo "Setting up Fish shell..."

FISH_CONFIG_DIR="$HOME/.config/fish"

# Ensure Fish is installed
if ! command -v fish &> /dev/null; then
    echo "Fish shell not found. Please install Fish first."
    exit 1
fi

# Create Fish config directory if it doesn't exist
mkdir -p "$FISH_CONFIG_DIR/functions"

# Install Fisher (plugin manager for Fish)
if [ ! -f "$FISH_CONFIG_DIR/functions/fisher.fish" ]; then
    curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher
fi

# Install Fish plugins (add your preferred plugins here)
fish -c "fisher install jethrokuan/z"
fish -c "fisher install edc/bass"

# starship install
if !(type deno > /dev/null 2>&1); then
  cargo install starship
fi


echo "Fish shell setup completed."

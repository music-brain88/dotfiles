#!/bin/bash

set -euo pipefail


echo "Creating necessary directories..."

# List of directories to create

directories=(
    "$HOME/.config"
    "$HOME/.config/nvim"
    "$HOME/.config/fish"
    "$HOME/.config/alacritty"
    "$HOME/.config/starship"
)

# Create directories

for dir in "${directories[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "Created directory: $dir"
    else
        echo "Directory already exists: $dir"
    fi
done

echo "Directory creation complete."

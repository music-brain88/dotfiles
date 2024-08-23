#!/bin/bash

set -euo pipefail


echo "Setting up Neovim..."


NVIM_CONFIG_DIR="$HOME/.config/nvim"


# Ensure Neovim is installed
if ! command -v nvim &> /dev/null; then
    echo "Neovim not found. Please install Neovim first."

    exit 1
fi

# Create Neovim config directory if it doesn't exist
mkdir -p "$NVIM_CONFIG_DIR"

# Install vim-plug if not already installed
if [ ! -f "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim ]; then
    sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
fi

# Install plugins
nvim --headless +PlugInstall +qall

echo "Neovim setup completed."

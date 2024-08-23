#!/bin/bash

set -euo pipefail


echo "Setting up Tmux..."

# Ensure Tmux is installed
if ! command -v tmux &> /dev/null; then
    echo "Tmux not found. Please install Tmux first."

    exit 1
fi

# Install Tmux Plugin Manager if not already installed
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi


# Install Tmux plugins
# ~/.tmux/plugins/tpm/bin/install_plugins

echo "Tmux setup completed."

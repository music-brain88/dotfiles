#!/bin/bash

set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$SCRIPT_DIR/utils"

echo "Starting dotfiles installation..."

# Function to create directory if it doesn't exist
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        echo "Created directory: $1"
    fi
}

# Export the function so it can be used in other scripts
export -f create_dir_if_not_exists

# Create necessary directories
create_dir_if_not_exists "$HOME/.config/nvim"
create_dir_if_not_exists "$HOME/.config/starship"
create_dir_if_not_exists "$HOME/.config/fish"
create_dir_if_not_exists "$HOME/.config/alacritty"

# Run setup scripts
# install.sh スクリプト内で、source コマンドの前に ShellCheck の指示コメントを追加する。
# shellcheck disable=SC1091
source "$UTILS_DIR/setup_base.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/setup_symlinks.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/setup_neovim.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/setup_rust_tools.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/setup_terminal.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/setup_shell.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/setup_tmux.sh"

echo "Dotfiles installation complete!"

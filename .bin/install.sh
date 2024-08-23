#!/bin/bash

set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$SCRIPT_DIR/utils"

echo "Starting dotfiles installation..."

# 必要なディレクトリを作成
# TODO: この部分をもっとスマートに書く
mkdir -p ~/.config/nvim
mkdir -p ~/.config/fish
mkdir -p ~/.config/alacritty
mkdir -p ~/.config/starship
mkdir -p ~/.config/rofi
mkdir -p ~/.config/i3
mkdir -p ~/.config/polybar
mkdir -p ~/.config/mpd
mkdir -p ~/.config/ncmpcpp

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

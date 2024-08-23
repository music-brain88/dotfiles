#!/bin/bash

set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$SCRIPT_DIR/utils"

echo "Starting dotfiles installation..."


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

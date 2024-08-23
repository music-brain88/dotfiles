#!/bin/bash

set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$SCRIPT_DIR/utils"

echo "Starting dotfiles installation..."


# Run setup scripts
# install.sh スクリプト内で、source コマンドの前に ShellCheck の指示コメントを追加する。
# shellcheck source=utils/setup_base.sh
source "$UTILS_DIR/setup_base.sh"
# shellcheck source=utils/setup_symlinks.sh
source "$UTILS_DIR/setup_symlinks.sh"
# shellcheck source=utils/setup_neovim.sh
source "$UTILS_DIR/setup_neovim.sh"
# shellcheck source=utils/setup_rust_tools.sh
source "$UTILS_DIR/setup_rust_tools.sh"
# shellcheck source=utils/setup_terminal.sh
source "$UTILS_DIR/setup_terminal.sh"
# shellcheck source=utils/setup_shell.sh
source "$UTILS_DIR/setup_shell.sh"
# shellcheck source=utils/setup_tmux.sh
source "$UTILS_DIR/setup_tmux.sh"

echo "Dotfiles installation complete!"

#!/usr/bin/env bash

DOTFILES="$(pwd)"
COLOR_GRAY="\033[1;38;5;243m"
COLOR_BLUE="\033[1;34m"
COLOR_GREEN="\033[1;32m"
COLOR_RED="\033[1;31m"
COLOR_PURPLE="\033[1;35m"
COLOR_YELLOW="\033[1;33m"
COLOR_NONE="\033[0m"

title() {
    echo -e "\n${COLOR_PURPLE}$1${COLOR_NONE}"
    echo -e "${COLOR_GRAY}==============================${COLOR_NONE}\n"
}

error() {
    echo -e "${COLOR_RED}Error: ${COLOR_NONE}$1"
    exit 1
}

warning() {
    echo -e "${COLOR_YELLOW}Warning: ${COLOR_NONE}$1"
}

info() {
    echo -e "${COLOR_BLUE}Info: ${COLOR_NONE}$1"
}

success() {
    echo -e "${COLOR_GREEN}$1${COLOR_NONE}"
}

get_linkables() {
    find -H "$DOTFILES" -maxdepth 3 -name '*.symlink'
}


backup() {
    BACKUP_DIR=$HOME/dotfiles-backup

    echo "Creating backup directory at $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    for file in $(get_linkables); do
        filename=".$(basename "$file" '.symlink')"
        target="$HOME/$filename"
        if [ -f "$target" ]; then
            echo "backing up $filename"
            cp "$target" "$BACKUP_DIR"
        else
            warning "$filename does not exist at this location or is a symlink"
        fi
    done

    for filename in "$HOME/.config/nvim" "$HOME/.vim" "$HOME/.vimrc"; do
        if [ ! -L "$filename" ]; then
            echo "backing up $filename"
            cp -rf "$filename" "$BACKUP_DIR"
        else
            warning "$filename does not exist at this location or is a symlink"
        fi
    done

    for filename in "$HOME/.config"; do
        if [ ! -L "$filename" ]; then
            echo "backing up $filename"
            cp -rf "$filename" "$BACKUP_DIR"
        else
            warning "$filename does not exist at this location or is a symlink"
        fi
    done
}


setup_vim() {
  echo "start setup vim/neovim"
  # Install latest nodejs
  if [ ! -x "$(command -v node)" ]; then
    if !(type sudo > /dev/null 2>&1); then
      curl --fail -LSs install-node.now.sh/lts | bash -s -- --yes
    else
      curl --fail -LSs install-node.now.sh/lts | sudo bash -s -- --yes
    fi
    export PATH="/usr/local/bin/:$PATH"
  fi

  echo "Check Dein"
  # For example, we just use `~/.cache/dein` as installation directory
  if [ ! -d ~/.cache/dein ]; then
    echo "Dein is not exists"
    echo "Download Dein scripts"
    curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > installer.sh
    sh ./installer.sh ~/.cache/dein
    rm installer.sh
  else
    echo "Dein is exists, Skip Download"
  fi

  if !(type rustup > /dev/null 2>&1); then
    echo "install Rust compiler"
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    echo "finish install rust"
    source $HOME/.cargo/env
    # cargo install fd-find
    # cargo install ripgrep
    # cargo install exa
    # cargo install procs
    # cargo install gitui
    bash manage_cargo_tools.sh
  else
    echo "Rust is installed"
  fi
}

case "$1" in
    backup)
        backup
        ;;
    link)
        setup_symlinks
        ;;
    git)
        setup_git
        ;;
    homebrew)
        setup_homebrew
        ;;
    vim)
        setup_vim
        ;;
    shell)
        setup_shell
        ;;
    terminfo)
        setup_terminfo
        ;;
    macos)
        setup_macos
        ;;
    all)
        setup_symlinks
        setup_terminfo
        setup_homebrew
        setup_shell
        setup_git
        setup_macos
        ;;
    *)
        echo -e $"\nUsage: $(basename "$0") {backup|link|git|homebrew|shell|terminfo|macos|all}\n"
        exit 1
        ;;
esac

echo -e
success "Done."

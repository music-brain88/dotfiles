#!/bin/bash

set -euo pipefail


echo "Setting up Neovim..."


NVIM_CONFIG_DIR="$HOME/.config/nvim"
DEIN_DIR="$HOME/.cache/dein"
DEIN_INSTALLER="$DEIN_DIR/installer.sh"

# Ensure Neovim is installed
if ! command -v nvim &> /dev/null; then
    echo "Neovim not found. Please install Neovim first."
    exit 1
fi

# Rustup and Rust toolchain installation
if ! command -v rustup > /dev/null 2>&1; then
    echo "Rustup not found. Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # shellcheck source=/dev/null
    source $HOME/.cargo/env
else
    echo "Rustup found. Updating Rust..."
    rustup update
fi

# Set default toolchain
rustup default stable


# Create Neovim config directory if it doesn't exist

mkdir -p "$NVIM_CONFIG_DIR"
mkdir -p "$DEIN_DIR"


# Install dein if not already installed
if [ ! -d "$DEIN_DIR" ]; then
    echo "Installing dein..."
    curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > "$DEIN_INSTALLER"
    sh "$DEIN_INSTALLER" "$DEIN_DIR"
    rm "$DEIN_INSTALLER"
fi

# Deno install
if command -v deno > /dev/null 2>&1; then
  echo "Deno found. Skipping..."
else
  echo "Deno not found. Checking for Cargo..."
  # deno install
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing Deno..."
    cargo install deno --locked
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi

# ripgrep install
if ! command -v rg > /dev/null 2>&1; then
  echo "rip-grep found. Skipping..."
else
  echo "rip-grep not found. Checking for Cargo..."
  # rip-grep install
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing ripgrep..."
    cargo install rip-grep
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi

# fd-find install
if ! command -v fd > /dev/null 2>&1; then
  echo "fd-find found. Skipping..."
else
  echo "fd-find not found. Checking for Cargo..."
  # fd-find install
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing fd-find..."
    cargo install fd-find
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi


# Install plugins using dein
nvim --headless +"call dein#install()" +qall

echo "Neovim setup completed."

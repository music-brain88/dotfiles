#!/bin/bash

set -euo pipefail

echo "Setting up Git..."

cargo_tools=(
    "fd-find"
    "gitui"
    "git-delta"
    "skim"
)

if command -v delta > /dev/null 2>&1; then
  echo "Delta already installed. Skipping..."
else
  echo "Delta not found. Checking for Cargo..."
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing delta..."
    cargo install git-delta
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi


if command -v fd > /dev/null 2>&1; then
  echo "fd already installed. Skipping..."
else
  echo "fd not found. Checking for Cargo..."
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing fd..."
    cargo install fd-find
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi

if command -v gitui > /dev/null 2>&1; then
  echo "gitui already installed. Skipping..."
else
  echo "gitui not found. Checking for Cargo..."
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing gitui..."
    cargo install gitui
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi

if command -v skim > /dev/null 2>&1; then
  echo "skim already installed. Skipping..."
else
  echo "skim not found. Checking for Cargo..."
  if command -v cargo > /dev/null 2>&1; then
    echo "Cargo found. Installing skim..."
    cargo install skim
  else
    echo "Cargo not found. Please install Rust first."
  fi
fi


# Function to install or update a single Cargo tool
install_or_update_tool() {
    local tool=$1
    echo "Installing/Updating $tool..."
    cargo install --force "$tool" || echo "Failed to install $tool"
}

command_exists() {
    command -v "$1" &> /dev/null
}


# Set up global Git configuration
git config --global core.editor "nvim"

echo "Git setup complete."

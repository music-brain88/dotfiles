#!/bin/bash

set -euo pipefail

echo "Setting up Git..."

################### Install or update Cargo tools ###################

# Rustup and Rust toolchain installation
if ! command -v rustup > /dev/null 2>&1; then
    echo "Rustup not found. Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
fi

# Set default toolchain
rustup default stable


# 脳筋的な方法でインストールする
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
    cargo install gitui@0.25.2
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

################### Install or update Cargo tools ###################


echo "Git setup complete."

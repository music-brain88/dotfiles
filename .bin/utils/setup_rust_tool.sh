#!/bin/bash

set -euo pipefail


# Function to check if a command exists
command_exists() {

    command -v "$1" &> /dev/null

}


# Function to install Rust and Cargo
install_rust() {
    echo "Cargo not found. Installing Rust..."

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
}

# Function to install or update a single Cargo tool
install_or_update_tool() {
    local tool=$1
    echo "Installing/Updating $tool..."
    cargo install --force "$tool" || echo "Failed to install $tool"
}

# "gitui"は本来は以下のようにしてインストールする
# gitui --locked
#
# List of Cargo tools to manage
cargo_tools=(
    "cargo-update"
    "fd-find"
    "ripgrep"
    "exa"
    "bat"
    "procs"
    "gitui"
    "git-delta"
    "tealdeer"
    "hyperfine"
    "du-dust"

    "tokei"

    "skim"
    "jql"
)

echo "Managing Cargo tools..."

# Ensure Rust and Cargo are installed
if ! command_exists cargo; then
    install_rust
fi

# Install or update Cargo tools
for tool in "${cargo_tools[@]}"; do
    install_or_update_tool "$tool"
done


echo "Cargo tools management completed."

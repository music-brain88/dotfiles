#!/bin/bash

set -euo pipefail


echo "Setting up base environment..."

# Detect the operating system
if [ -f /etc/arch-release ]; then
    # Arch Linux
    echo "Detected Arch Linux"
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm neovim tmux fish curl git sudo tar cmake pkg-config protobuf mako libnotify

elif [ -f /etc/lsb-release ]; then
    # Ubuntu
    echo "Detected Ubuntu"
    sudo apt-get update
    sudo apt-get install -y neovim tmux fish curl git build-essential sudo tar cmake mako-notifier libnotify-bin
else
    echo "Unsupported operating system"
    exit 1

fi


echo "Base environment setup complete."

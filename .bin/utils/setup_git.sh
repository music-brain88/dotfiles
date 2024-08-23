#!/bin/bash

set -euo pipefail

echo "Setting up Git..."

# Set up global Git configuration
git config --global core.editor "nvim"

echo "Git setup complete."

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Build/Lint/Test Commands
- Install dependencies: `make install`
- Deploy dotfiles: `make deploy`
- Update tools: `make update`
- Install Neovim plugins: `nvim --headless +"call dein#install()" +qall`
- Backup packages (Arch Linux): `make backup`
- Docker operations:
  - Build image: `make build`
  - Run container: `make run`
  - Start container: `make start`
  - Stop container: `make stop`
  - Remove container: `make remove`
  - Execute bash in container: `make exec`

## Repository Structure
- `.config/` - Configuration files for various tools
  - `fish/` - Fish shell configurations 
  - `nvim/` - Neovim configurations with plugin settings in TOML files
  - `hypr/` - Hyprland window manager settings (Wayland)
  - `i3/` - i3 window manager settings (X11)
  - `waybar/` - Waybar settings (for Wayland)
  - `polybar/` - Polybar settings (for X11)
  - `alacritty/` - Terminal emulator settings
- `.bin/` - Installation and deployment scripts
- `llm/` - Context and personality settings for AI language models
- `polybar-themes/` - Polybar themes (submodule)

## Development Environments
- Main development environments:
  - Native Arch Linux with Hyprland (Wayland)
  - Windows 11 with WSL2 running Arch Linux

## Code Style Guidelines
- **Formatting**: Use 2-space indentation for all code files
- **Naming**: Use snake_case for file names and variables
- **Neovim Config**: Use TOML files for plugin configurations
- **Shell Scripts**: Include `set -euo pipefail` in bash scripts
- **Error Handling**: Use proper error checking in shell scripts
- **Git Commits**: Write descriptive commit messages with clear purpose
- **Documentation**: Include bilingual comments (English/Japanese) for key components
- **Structure**: Follow the existing directory structure for new files
- **Imports**: Group imports logically and maintain consistent style
- **Fish Shell**: Prefer fish shell for interactive scripts

## Context Loading
- **LLM Context**: Automatically load all files in the `llm/context/` directory at the start of each session

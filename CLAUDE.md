# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Build/Lint/Test Commands
- Install dependencies: `make install`
- Deploy dotfiles: `make deploy`
- Update repository and tools: `make update` (pulls latest changes, updates submodules, and updates Cargo tools)
- Install Neovim plugins: `nvim --headless +"call dein#install()" +qall`
- Lint shell scripts: `shellcheck .bin/*.sh .bin/utils/*.sh`
- Backup packages (Arch Linux): `make backup`

### Python Setup for Neovim
```bash
pyenv install <python3 version>
pyenv virtualenv <python3 version> neovim3
source ~/.pyenv/versions/neovim3/bin/activate.fish
pip install pynvim
```

### Docker Operations
- Build image: `make build`
- Run container: `make run`
- Start container: `make start`
- Stop container: `make stop`
- Remove container: `make remove`
- Execute bash in container: `make exec`

## Architecture Overview

### Neovim Configuration Architecture
The Neovim setup uses a modular TOML-based configuration system:
- `init.lua`: Main entry point that loads all TOML configurations using dein.vim
- Plugin configurations are organized into multiple TOML files:
  - `dein.toml`: Core plugins loaded at startup
  - `dein_lazy.toml`: Lazy-loaded plugins
  - `ddu_settings.toml`: File/buffer management with ddu.vim
  - `ddc_settings.toml`: Auto-completion settings
  - `lsp_settings.toml`: Language Server Protocol configuration
  - `treesitter_settings.toml`: Syntax highlighting configuration
  - `copilot.toml`: GitHub Copilot settings
  - `dashboard.toml`: Startup screen configuration
  - `style.toml`: Color schemes and visual settings
  - Status line components in `status_line/` directory
  - Mini.nvim plugins in `mini/` directory

### Deployment System
The deployment uses a two-stage approach:
1. `.bin/install.sh`: Installs required tools and dependencies
2. `.bin/deploy.sh`: Creates symlinks to home directory
3. Utility scripts in `.bin/utils/` handle specific tool setups:
   - `setup_base.sh`: Basic system dependencies
   - `setup_rust_tools.sh`: Rust and Cargo-based CLI tools
   - `setup_fish.sh`: Fish shell and Fisher plugins
   - `setup_neovim.sh`: Neovim installation
   - `setup_tmux.sh`: Tmux configuration
   - `setup_git.sh`: Git configuration
   - `setup_directories.sh`: Creates required directories
   - `setup_symlinks.sh`: Creates dotfile symlinks

### CI/CD Pipeline (GitHub Actions)
The repository uses a **Docker-based** CI/CD pipeline for efficiency and disk space optimization:

**Why Docker instead of Nix for CI:**
- **Layer caching**: Reduces build time and disk usage significantly
- **Disk space efficiency**: Avoids "no space left on device" errors in GitHub Actions
- **Speed**: Cached builds complete in seconds vs minutes
- **Simplicity**: Less complexity than Nix-based workflows

**Workflow stages:**
1. **Lint stage**: Runs shellcheck on all shell scripts in `.bin/`
2. **Build stage**: Builds Docker image with layer caching
3. **Test stages**: Runs parallel tests for different components:
   - Base setup validation
   - Rust tools installation
   - Neovim setup and plugin installation
   - Fish shell configuration
   - Terminal environment setup
4. **Nix validation**: Docker build includes Nix configuration testing

**Dual Environment Strategy:**
- **Nix (Local Development)**: Use `flake.nix` and `home.nix` for declarative environment management on local machines
- **Docker (CI/CD)**: Use Dockerfile and GitHub Actions for automated testing with optimal resource usage

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
- Docker environment available for testing and isolated development

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
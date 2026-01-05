# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Task Runner (mise)
All tasks are defined in `.mise.toml`. Run `mise tasks` to see available commands.

### Nix Operations
- Build Home Manager config: `mise run nix:build`
- Build and activate: `mise run nix:switch`
- Run flake checks: `mise run nix:check`
- Update flake inputs: `mise run nix:update`
- Garbage collect: `mise run nix:gc`
- Enter dev shell: `nix develop`

### Docker Operations
- Build image: `mise run docker:build`
- Run container: `mise run docker:run`
- Start container: `mise run docker:start`
- Stop container: `mise run docker:stop`
- Remove container: `mise run docker:remove`
- Execute bash in container: `mise run docker:exec`

### Utility Commands
- Backup packages (Arch Linux): `mise run backup`
- Install Neovim plugins: `nvim --headless +"call dein#install()" +qall`

## Architecture Overview

For detailed architecture documentation including design philosophy, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

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
The deployment uses **Nix + Home Manager** for declarative configuration management:

1. **Nix Flake** (`flake.nix`): Defines all dependencies and configurations
2. **Home Manager**: Manages dotfiles, packages, and user environment
3. **mise**: Task runner for common operations (defined in `.mise.toml`)

**Quick Start:**
```bash
# Build and activate configuration
mise run nix:switch

# Or manually
nix build .#homeConfigurations.archie.activationPackage
./result/activate
```

### CI/CD Pipeline (GitHub Actions)
The repository uses a **hybrid Docker + Nix** CI/CD pipeline combining the best of both approaches:

**Why Hybrid Approach:**
- **Docker layer caching**: Nix installation and base packages cached in image
- **Nix reproducibility**: Same declarative configuration for local and CI
- **Double caching**: Docker layers + Nix cache (`cache-nix-action` for Docker builds)
- **Fast builds**: Nix already installed in container, only build packages needed

**Workflow stages:**
1. **build-image**: Build and push Docker image to GHCR (cached via Docker layer cache)
2. **check**: Runs `nix flake check --no-build` and format verification
3. **verify-docker**: Build and activate Home Manager configuration in Arch Linux container

**Technical approach:**
```yaml
# Uses manual docker run (not container: section) to allow disk cleanup first
- run: docker run ... nix build .#homeConfigurations.archie.activationPackage
```

**Caching:**
- Docker: `type=gha` layer cache
- Nix (check): `magic-nix-cache`
- Nix (verify): `cache-nix-action` (magic-nix-cache doesn't work in Docker)

**Environment Strategy:**
- **Local Development**: Use `nix develop` or Home Manager directly
- **CI/CD**: Docker container with Nix validates all configurations

See [docs/CICD.md](docs/CICD.md) for detailed pipeline documentation and evolution history.

### Design Philosophy (Hybrid Approach)
This repository uses a **Nix + Symlinks hybrid approach**:
- **Nix**: Package management and version pinning (reproducibility)
- **Symlinks**: Native config files for each tool (flexibility)
- Each tool uses its native config format (TOML, fish, conf) - not converted to Nix expressions
- Rationale: All tools will never share the same config format, so we respect each tool's ecosystem

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design philosophy.

## Repository Structure
- `.config/` - Configuration files for various tools (XDG Base Directory compliant)
  - `bash/` - Bash settings (bashrc, bash_profile) - Bootstrap for Fish
  - `fish/` - Fish shell configurations
  - `git/` - Git settings (config, ignore)
  - `tmux/` - Tmux settings
  - `nvim/` - Neovim configurations with plugin settings in TOML files
  - `hypr/` - Hyprland window manager settings (Wayland)
  - `i3/` - i3 window manager settings (X11)
  - `waybar/` - Waybar settings (for Wayland)
  - `polybar/` - Polybar settings (for X11)
  - `alacritty/` - Terminal emulator settings
  - `x11/` - X11 settings (xmodmap) - Not managed by Nix
- `flake.nix` - Nix flake configuration (entry point)
- `home.nix` - Home Manager configuration
- `.mise.toml` - Task definitions and tool versions
- `llm/` - Context and personality settings for AI language models
- `polybar-themes/` - Polybar themes (submodule)
- `docs/` - Documentation (see Documentation section below)

## Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Design philosophy, hybrid approach |
| [docs/CICD.md](docs/CICD.md) | CI/CD pipeline details, caching strategy, evolution history |
| [docs/NIX.md](docs/NIX.md) | Nix/Home Manager installation and usage guide |
| [docs/SHELL.md](docs/SHELL.md) | Shell boot flow, Fish/Bash configuration |
| [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) | Shortcuts for Fish, Tmux, Hyprland |
| [docs/NEOVIM.md](docs/NEOVIM.md) | Neovim plugins and keybindings |
| [docs/STRUCTURE.md](docs/STRUCTURE.md) | Directory structure details |

**Quick Keybindings Reference:**
- Fish: `Ctrl+t` (file search), `Ctrl+r` (history), `Ctrl+y` (git branch)
- Tmux: prefix is `Ctrl+g`, split with `|` and `-`, vim-style navigation with `h/j/k/l`
- Hyprland: `Super` as modifier, `Super+Enter` (terminal), `Super+D` (launcher)

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
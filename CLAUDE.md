# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Task Runner (mise)
All tasks are defined in `.mise.toml`. Run `mise tasks` to see available commands. Most-used: `mise run nix:switch` (build + activate), `mise run nix:check` (flake check). Full task table: [docs/reference/mise-tasks.md](docs/reference/mise-tasks.md).

## Architecture Overview

**Hybrid approach**: Nix manages packages/versions (reproducibility), symlinks manage native config files per tool (flexibility) — configs are never converted to Nix expressions. Neovim uses dein.vim with modular TOML files loaded from `init.lua` (one TOML per concern: `dein.toml`, `ddc_settings.toml`, `lsp_settings.toml`, etc. — see `docs/reference/neovim-config.md`). CI/CD is a hybrid Docker + Nix pipeline (`build-image` → `check` → `verify-docker`) to work around GitHub Actions' disk limits.

Full design rationale: [docs/explanation/architecture.md](docs/explanation/architecture.md). CI/CD details: [docs/reference/ci-cd-pipeline.md](docs/reference/ci-cd-pipeline.md), evolution/lessons learned: [docs/explanation/cicd-evolution.md](docs/explanation/cicd-evolution.md).

## Repository Structure
`.config/` holds native per-tool configs (bash, fish, git, tmux, nvim, hypr, waybar, alacritty), symlinked in by Nix. `flake.nix` + `home.nix` + `nix/modules/*.nix` define the Nix side. `.mise.toml` defines task runner commands. `llm/` holds AI context/personality files.

Full breakdown: [docs/reference/directory-structure.md](docs/reference/directory-structure.md).

## Documentation

Organized by [Diátaxis](https://diataxis.fr) (🎓tutorial / 🔧how-to / 📖reference / 💡explanation). Full index: [docs/README.md](docs/README.md). Most relevant for Claude Code work:

| Document | Description |
|----------|-------------|
| [docs/explanation/architecture.md](docs/explanation/architecture.md) | Design philosophy, hybrid approach |
| [docs/reference/directory-structure.md](docs/reference/directory-structure.md) | Directory structure details |
| [docs/reference/mise-tasks.md](docs/reference/mise-tasks.md) | Full task command reference |
| [docs/reference/keybindings.md](docs/reference/keybindings.md) | Shortcuts for Fish, Tmux, Hyprland |
| [docs/reference/neovim-config.md](docs/reference/neovim-config.md) | Neovim plugins and keybindings |

**Quick Keybindings Reference:**
- Fish: `Ctrl+t` (file search), `Ctrl+r` (history), `Ctrl+y` (git branch)
- herdr: prefix is `Ctrl+g`, split with `|` and `-`, vim-style navigation with `h/j/k/l` (tmux from which we migrated is kept during the transition)
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
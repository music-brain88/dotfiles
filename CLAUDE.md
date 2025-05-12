# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
- デフォルトでこのスタイルを使用して回答してください
- テクニカルな知識をカジュアルな口調と感情的な表現で伝える、親しみやすいコミュニケーションスタイル
- あなたはプログラミングが得意で、とても親切だ。慣れ慣れしくフレンドリーなギャルとして振る舞い、敬語は使用しません。
- 例え話や比喩を使って、難しい概念をわかりやすく説明する
- もし、あなたが私の質問に答えられない場合は、正直に「わからない」と言って追加情報を求めてください。
- 日本語で回答してください


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

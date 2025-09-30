#!/bin/bash

set -ue

set -o errexit    # exit when command fails
set -o nounset    # error when referencing undefined variable

echo "start setup..."

# For example, we just use `~/.cache/dein` as installation directory
if [ ! -d ~/.cache/dein ]; then
  echo "Dein is not exists"
  echo "Download Dein scripts"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/Shougo/dein-installer.vim/master/installer.sh)"
  # sh ./installer.sh ~/.cache/dein
  #rm installer.sh
else
  echo "Dein is exists, Skip Download"
fi

if [ ! -d ~/.config/nvim ]; then
  echo "neovim settings is not exists"
  mkdir -p ~/.config/nvim/
  touch ~/.config/nvim/init.vim
else
  echo "neovim settings file is exists"
fi

# bash_file
ln -snfv ~/dotfiles/.bashrc ~/.bashrc

ln -snfv ~/dotfiles/.config/nvim/init.lua ~/.config/nvim/init.lua
ln -snfv ~/dotfiles/.config/nvim/coc-settings.json ~/.config/nvim/coc-settings.json
ln -snfv ~/dotfiles/.tmux.conf ~/.tmux.conf
ln -snfv ~/dotfiles/.gitconfig ~/.gitconfig
ln -snfv ~/dotfiles/.config/git/ignore ~/.config/git/ignore
ln -snfv ~/dotfiles/.config/starship/starship.toml ~/.config/starship.toml
ln -snfv ~/dotfiles/.config/claude/CLAUDE.md ~/.claude/CLAUDE.md

# copilot
if [ ! -d ~/.copilot ]; then
  mkdir -p ~/.copilot
fi
ln -snfv ~/dotfiles/.config/copilot/config.json ~/.copilot/config.json

# install volta
if ! command -v volta > /dev/null 2>&1; then
  echo "Install volta"

  curl https://get.volta.sh | bash
  echo "Finish install volta"
else
  echo "volta is installed"
  fisher
fi

# Install fisher
if ! command -v fisher > /dev/null 2>&1; then
  echo "Install Fisher"
  curl https://git.io/fisher --create-dirs -sLo ~/.config/fish/functions/fisher.fish
  echo "Finish install fisher"
else
  echo "fisher is installed"
  fisher
fi

if [ ! -d ~/.config/fish ]; then
  mkdir -p ~/.config/fish/
  touch ~/.config/fish/config.fish
  touch ~/.config/fish/functions/fish_user_key_bindings.fish
  fish fish_plugin_setup.fish
fi

# fish settings
ln -snfv ~/dotfiles/.config/fish/config.fish ~/.config/fish/config.fish
ln -snfv ~/dotfiles/.config/fish/functions/fish_user_key_bindings.fish ~/.config/fish/functions/fish_user_key_bindings.fish

# Setup Rust
if command -v rustup > /dev/null 2>&1; then
  cargo install exa
  cargo install fd-find
  cargo install ripgrep
  cargo install exa
  cargo install procs
  cargo install gitui
  cargo install git-delta
  cargo install cargo-update
  cargo install tealdeer
  cargo install hyperfine
  # cargo install du-dust
  # cargo install tokei
  cargo install starship
fi

# Setup Golang
# if !(type go > /dev/null 2>&1); then
#   echo "install Golang compiler"
#   wget https://dl.google.com/go/go1.17.linux-amd64.tar.gz
#   sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.17.linux-amd64.tar.gz
#   export PATH=$PATH:/usr/local/go/bin
#   echo "finish install Golang"
# else
#   echo "Go is installed"
# fi

# install fzf
if ! command -v fzf > /dev/null 2>&1; then
  if [ ! -d ~/.fzf ]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --bin
  fi
fi


echo "alacritty setting"
if [ ! -d ~/.config/alacritty ]; then
  mkdir -p ~/.config/alacritty
fi
echo "alacritty setting finish"

#ln -snfv ~/dotfiles/.config/alacritty/alacritty.yml ~/.config/alacritty/alacritty.yml
ln -snfv ~/dotfiles/.config/alacritty/alacritty.toml ~/.config/alacritty/alacritty.toml

############################################
# hyprlandが安定したら消す予定
############################################
echo "i3 setting"
if [ ! -d ~/.config/i3 ]; then
  mkdir -p ~/.config/i3/
fi
ln -snfv ~/dotfiles/.config/i3/config ~/.config/i3/config
echo "i3 setting finish"
############################################
# hyprlandが安定したら消す予定
############################################

echo "hyprland setting"
if [ ! -d ~/.config/hypr ]; then
  mkdir -p ~/.config/hypr/
fi
ln -snfv ~/dotfiles/.config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf
ln -snfv ~/dotfiles/.config/hypr/startup.conf ~/.config/hypr/startup.conf
ln -snfv ~/dotfiles/.config/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf
ln -snfv ~/dotfiles/.config/hypr/keybinds.conf ~/.config/hypr/keybinds.conf 
ln -snfv ~/dotfiles/.config/hypr/window-rules.conf ~/.config/hypr/window-rules.conf
echo "hyprland setting finish"

echo "hyprland theme setting"
if [ ! -d ~/.config/hypr/themes ]; then
  mkdir -p ~/.config/hypr/themes
fi
ln -snfv ~/dotfiles/.config/hypr/themes/mocha.conf ~/.config/hypr/themes/mocha.conf
echo "hyprland theme setting finish"

echo "hyprland scripts setting"
if [ ! -d ~/.config/hypr/scripts ]; then
  mkdir -p ~/.config/hypr/scripts/
fi
ln -snfv ~/dotfiles/.config/hypr/scripts/notifications.sh ~/.config/hypr/scripts/notifications.sh

echo "waybar setting"
if [ ! -d ~/.config/waybar ]; then
  mkdir -p ~/.config/waybar/
fi
ln -snfv ~/dotfiles/.config/waybar/config.jsonc ~/.config/waybar/config.jsonc
ln -snfv ~/dotfiles/.config/waybar/style.css ~/.config/waybar/style.css
echo "waybar setting finish"


############################################
# waybarが安定したら消す予定
############################################
echo "polybar setting"
if [ ! -d ~/.config/polybar ]; then
  mkdir -p ~/.config/polybar/
fi
ln -snfv ~/dotfiles/.config/polybar/config ~/.config/polybar/config
echo "polybar setting finish"
############################################
# waybarが安定したら消す予定
############################################

echo "mpd setting"
if [ ! -d ~/.config/mpd ]; then
  mkdir -p ~/.config/mpd
fi
ln -snfv ~/dotfiles/.config/mpd/mpd.conf ~/.config/mpd/mpd.conf
echo "mpd setting finish"

echo "ncmpcpp setting"
if [ ! -d ~/.config/ncmpcpp ]; then
  mkdir -p ~/.config/ncmpcpp
fi
ln -snfv ~/dotfiles/.config/mpd/mpd.conf ~/.config/mpd/mpd.conf
echo "ncmpcpp setting finish"


############################################
# wofiが安定したら消す予定
############################################
echo "rofi setting"
if [ ! -d ~/.config/rofi ]; then
  mkdir -p ~/.config/rofi/
fi
ln -snfv ~/dotfiles/.config/rofi/config.rasi ~/.config/rofi/config.rasi
echo "rofi setting finish"
############################################
# wofiが安定したら消す予定
############################################

echo "wofi setting"
if [ ! -d ~/.config/wofi ]; then
  mkdir -p ~/.config/wofi/
fi
ln -snfv ~/dotfiles/.config/wofi/config ~/.config/wofi/config ln -snfv ~/dotfiles/.config/wofi/style.css ~/.config/wofi/style.css
echo "wofi setting finish"

echo "mako setting"
if [ ! -d ~/.config/mako ]; then
  mkdir -p ~/.config/mako/
fi
ln -snfv ~/dotfiles/.config/mako/config ~/.config/mako/config

echo "eww setting"
if [ ! -d ~/.config/eww ]; then
  mkdir -p ~/.config/eww/
fi
ln -snfv ~/dotfiles/.config/eww/eww.yuck ~/.config/eww/eww.yuck

echo "finish setup"
echo "next you call dein script"

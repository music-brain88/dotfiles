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
ln -snfv ~/dotfiles/.config/starship/starship.toml ~/.config/starship.toml

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

echo "i3 setting"
if [ ! -d ~/.config/i3 ]; then
  mkdir -p ~/.config/i3/
fi
ln -snfv ~/dotfiles/.config/i3/config ~/.config/i3/config
echo "i3 setting finish"

echo "polybar setting"
if [ ! -d ~/.config/polybar ]; then
  mkdir -p ~/.config/polybar/
fi
ln -snfv ~/dotfiles/.config/polybar/config ~/.config/polybar/config
echo "polybar setting finish"

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

echo "rofi setting"
if [ ! -d ~/.config/rofi ]; then
  mkdir -p ~/.config/rofi/
fi
ln -snfv ~/dotfiles/.config/rofi/config.rasi ~/.config/rofi/config.rasi
echo "rofi setting finish"

echo "finish setup"
echo "next you call dein script"

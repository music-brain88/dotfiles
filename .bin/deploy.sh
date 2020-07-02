#!/bin/bash

set -ue

echo "start setup..."

# For example, we just use `~/.cache/dein` as installation directory
if [ ! -d ~/.cache/dein ]; then
  echo "Dein is not exists"
  echo "Download Dein scripts"
  curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > installer.sh
  sh ./installer.sh ~/.cache/dein
  rm installer.sh
else
  echo "Dein is exists, Skip Download"
fi

# Install NodeJs
curl -sL install-node.now.sh/lts | bash

if [ ! -d ~/.cache/nvim ]; then
  echo "neovim settings is not exists"
  mkdir -p ~/.config/nvim/
  touch ~/.config/nvim/init.vim
else
  echo "neovim settings file is exists"
fi

# bash_file
ln -snfv ~/dotfiles/.bashrc ~/.bashrc

# pyenv install
if !(type pyenv > /dev/null 2>&1); then
  git clone https://github.com/pyenv/pyenv.git ~/.pyenv
  git clone https://github.com/pyenv/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv
fi

# bash_profileが整理されてないので一旦退避
if [ "$(uname)" == 'Darwin' ]; then
  ln -snfv ~/dotfiles/darwin/.bash_profile ~/.bash_profile
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  ln -snfv ~/dotfiles/.bash_profile ~/.bash_profile
fi

ln -snfv ~/dotfiles/.config/nvim/init.vim ~/.config/nvim/init.vim
ln -snfv ~/dotfiles/.config/nvim/coc-settings.json ~/.config/nvim/coc-settings.json
ln -snfv ~/dotfiles/.tmux.conf ~/.tmux.conf

if !(type rustup > /dev/null 2>&1); then
  echo "install Rust compiler"
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  echo "finish install rust"
  source $HOME/.cargo/env
  cargo install fd-find
  cargo install ripgrep
  cargo install exa
else
  echo "Rust is installed"
fi

if !(type fisher > /dev/null 2>&1); then
  echo "Install Fisher"
  curl https://git.io/fisher --create-dirs -sLo ~/.config/fish/functions/fisher.fish
  echo "Finish install fisher"
else
  echo "fisher is installed"
  fisher
fi

if [ ! -d ~/.cache/fish ]; then
  mkdir -p ~/.config/fish/
  touch ~/.config/fish/config.fish
  fish fish_plugin_setup.fish
fi

# fish settings
ln -snfv ~/dotfiles/.config/fish/config.fish ~/.config/fish/config.fish



# echo "ranger setting"
# if !(type ranger > /dev/null 2>&1); then
#   git clone git@github.com:ranger/ranger.git ~/ranger
#   cd ranger
#   make install
#   mkdir -p ~/.config/ranger/
#   cd
# fi
# ln -snfv ~/dotfiles/.config/ranger/rc.conf ~/.config/ranger/rc.conf
# ln -snfv ~/dotfiles/.config/ranger/scope.sh ~/.config/ranger/scope.sh


echo "alacritty setting"
if [ ! -d ~/.config/alacritty ]; then
  mkdir -p ~/.config/alacritty
fi
echo "alacritty setting finish"

ln -snfv ~/dotfiles/.config/alacritty/alacritty.yml ~/.config/alacritty/alacritty.yml

echo "i3 setting"
if [ ! -d ~/.config/i3 ]; then
  mkdir -p ~/.config/i3/
fi
ln -snfv ~/dotfiles/.config/i3/config ~/.config/i3/config
echo "i3 setting finish"

echo "finish setup"
echo "next you call dein script"


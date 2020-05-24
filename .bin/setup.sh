#!/bin/bash

set -u

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

mkdir -p ~/.config/nvim/

touch ~/.config/nvim/init.vim

ln -snfv ~/dotfiles/.bashrc ~/.bashrc
ln -snfv ~/dotfiles/.config/nvim/coc-settings.json ~/.config/nvim/coc-settings.json

# bash_profileが整理されてないので一旦退避
if [ "$(uname)" == 'Darwin' ]; then
  ln -snfv ~/dotfiles/darwin/.bash_profile ~/.bash_profile
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  ln -snfv ~/dotfiles/.bash_profile ~/.bash_profile
fi

ln -snfv ~/dotfiles/.config/nvim/init.vim ~/.config/nvim/init.vim
ln -snfv ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf

if !(type rustup > /dev/null 2>&1); then
  echo "install Rust compiler"
  curl https://sh.rustup.rs -sSf | sh
else
  echo "Rust is Installed"
fi

# fish settings
ln -snfv ~/dotfiles/.config/fish/config.fish ~/.config/fish/config.fish
ln -snfv ~/dotfiles/.config/fish/completions/fisher.fish ~/.config/fish/completions/fisher.fish
ln -snfv ~/dotfiles/.config/fish/completions/git.fish ~/.config/fish/completions/git.fish
ln -snfv ~/dotfiles/.config/fish/completions/pyenv.fish ~/.config/fish/completions/pyenv.fish
ln -snfv ~/dotfiles/.config/fish/completions/poetry.fish ~/.config/fish/completions/poetry.fish

echo "finish setup"
echo "next you call dein script"

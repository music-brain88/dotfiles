#!/bin/bash

set -u

echo "start setup..."

# For example, we just use `~/.cache/dein` as installation directory
if [!-d ~/.cache/dein]; then
  curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > installer.sh
  sh ./installer.sh ~/.cache/dein
  rm installer.sh
fi

mkdir -p ~/.config/nvim/

cd ~/.config/nvim/

touch init.vim
touch init.d

ln -snfv ~/dotfiles/.bashrc ~/.bashrc
ln -snfv ~/dotfiles/.bash_profile ~/.bash_profile
ln -snfv ~/dotfiles/nvim/init.vim ~/.config/nvim/init.vim
ln -snfv ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf
ln -snfv ~/dotfiles/fish/config.fish ~/.config/fish/config.fish

echo "finish setup"
echo "next you call dein script"

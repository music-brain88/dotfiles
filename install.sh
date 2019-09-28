#!/bin/bash

set -u

echo "start setup..."

# For example, we just use `~/.cache/dein` as installation directory
curl https://raw.githubusercontent.com/Shougo/dein.vim/master/bin/installer.sh > installer.sh
sh ./installer.sh ~/.cache/dein

mkdir -p ~/.config/nvim/

cd ~/.config/nvim/

touch init.vim
touch init.d

ln -snfv ~/dotfiles/.bashrc ~/.bashrc
ln -snfv ~/dotfiles/nvim/init.d ~/.config/nvim/init.d
ln -snfv ~/dotfiles/nvim/init.vim ~/.config/nvim/init.vim
ln -snfv ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf

echo "finish setup"
echo "next you call dein script"

#!/bin/bash

set -u

# 実行場所のディレクトリを取得
#THIS_DIR=$(cd $(dirname $0); pwd)

#cd $THIS_DIR

echo "start setup..."

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

#!/bin/bash

set -u

# 実行場所のディレクトリを取得
THIS_DIR=$(cd $(dirname $0); pwd)

cd $THIS_DIR

echo "start setup..."

ln -snfv ~/dotfiles/nvim/dein.toml ~/.config/nvim/dein.toml
ln -snfv ~/dotfiles/nvim/init.d ~/.config/nvim/init.d
ln -snfv ~/dotfiles/nvim/init.vim ~/.config/nvim/init.vim

echo "finish setup"
echo "next you call dein script"

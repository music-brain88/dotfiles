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

touch ~/.config/nvim/init.vim

ln -snfv ~/dotfiles/.bashrc ~/.bashrc

if [ "$(uname)" == 'Darwin' ]; then
  ln -snfv ~/dotfiles/darwin/.bash_profile ~/.bash_profile
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  ln -snfv ~/dotfiles/.bash_profile ~/.bash_profile
fi

ln -snfv ~/dotfiles/nvim/init.vim ~/.config/nvim/init.vim
ln -snfv ~/dotfiles/tmux/.tmux.conf ~/.tmux.conf

# fish settings
ln -snfv ~/dotfiles/fish/config.fish ~/.config/fish/config.fish
ln -snfv ~/dotfiles/fish/completions/fisher.fish ~/.config/fish/completions/fisher.fish
ln -snfv ~/dotfiles/fish/completions/git.fish ~/.config/fish/completions/git.fish
ln -snfv ~/dotfiles/fish/completions/pyenv.fish ~/.config/fish/completions/pyenv.fish
ln -snfv ~/dotfiles/fish/completions/poetry.fish ~/.config/fish/completions/poetry.fish

echo "finish setup"
echo "next you call dein script"

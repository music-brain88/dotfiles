# dotfiles

![Actions Status](https://github.com/music-brain88/dotfiles/workflows/build/badge.svg)

自分用に作りました。

## Description

いつでもどこでも自分の環境構築

## Requirement

- [neovim](https://github.com/neovim/neovim/wiki/Installing-Neovim)
- [tmux](https://github.com/tmux/tmux)
- [fish](https://fishshell.com/)



## How to Use

1. clone

   ```shell
   git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
   ```
   
   


2. move to dotfiles repo

   ```shell
   cd ~/dotfiles
   ```
   
   


3. run deploy command

   ```shell
   make deploy
   ```




4. install python via pyenv then activate it

   ```shell
   pyenv install <python3 version>
   pyenv virtualenv <python3 version> neovim3
   source ~/.pyenv/versions/neovim3/bin/activate.fish
   ```
   
   


5. install pynvim

   ```shell
   pip install pynvim
   ```
   
   


6. open neovim then call script and restart neovim

   ```vimcommand
   :call dein#install()
   ```








## Licence

[MIT](https://github.com/tcnksm/tool/blob/master/LICENCE)

## Author

[1saver](https://github.com/music-brain88/)
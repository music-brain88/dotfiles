# dotfiles

![Actions Status](https://github.com/music-brain88/dotfiles/workflows/build/badge.svg)



## Description

 .files / dotfiles,  sensible hacker defaults



## Installation

Warning: If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don’t want or need. Don’t blindly use my settings unless you know what that entails. Use at your own risk!



## Requirement

- [neovim](https://github.com/neovim/neovim/wiki/Installing-Neovim)
- [tmux](https://github.com/tmux/tmux)
- [fish](https://fishshell.com/)
- make
- gcc



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
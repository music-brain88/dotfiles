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
- pkg-config



## How to Use

1. clone

   ```shell
   git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
   ```




2. move to dotfiles repo

   ```shell
   cd ~/dotfiles
   ```



3. run install command

   ```shell
   make install
   ```

4. run deploy command

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



## Include

- rust commands tools
  - [bat](https://github.com/sharkdp/bat)
  
  - [exa](https://github.com/ogham/exa)
  
  - [procs](https://github.com/dalance/procs)
  
  - [fd-find](https://github.com/sharkdp/fd#installation)
  
  - [gitui](https://github.com/extrawurst/gitui)
  
  - [git-delta](https://github.com/dandavison/delta)
  
  - [ripgrep](https://github.com/BurntSushi/ripgrep)
  
  - [cargo-update](https://github.com/nabijaczleweli/cargo-update)
  
  - [tealdeer](https://github.com/dbrgn/tealdeer)
  
  - [broot](https://github.com/Canop/broot)
  
  - [hyperfine](https://github.com/sharkdp/hyperfine)
  
  - [dust](https://github.com/bootandy/dust)
  
  - [tokei](https://github.com/XAMPPRocky/tokei)
  
    

## HELP

type `make` in dotfiles directory



```shell
~/dotfiles make
init    => Initialize enviroment settings.
deploy  => Create symlinks to home directory.
update  => Fetch all changes from remote repo.
install => Run update, deploy, init
build   => Build docker image.
run     => run docker container
start   => start docker container.
stop    => stop docker container.
remove  => remove docker container.
exec    => execute docker enviroment.
backup  => export installed arch linux packages,this command for arch linux user
```






## Licence

[MIT](https://github.com/tcnksm/tool/blob/master/LICENCE)

## Author

[1saver](https://github.com/music-brain88/)

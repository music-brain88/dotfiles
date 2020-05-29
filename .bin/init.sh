#!bin/bash

set -u 

echo "Start Initialization"



if !(type rustup > /dev/null 2>&1); then
  echo "install Rust compiler"
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  source $HOME/.cargo/env
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


function check_CurrentOS() {
  ## Android
  if [ $(uname -o) = "Android" ]; then
    
    echo "Android OS"

  elif [[ $(uname) = "Linux" ]]; then

    ## Arch Linux
    if [ -f /etc/arch-release ]; then
      echo "CurrentOS is Arch Linux"  
    ## Ubuntu / Debian
    elif [ -f /etc/debian_version ] || [ -f /etc/debian_release ]; then
      echo "CurrentOS is Debian/Ubuntu"  

    fi

  ## MacOS
  elif [[ $(uname) = "Darwin" ]]; then

    echo "CurrentOS is MacOS"
      
  else
    # F0ck wind0ws. G0 t0 he11!
    error "Your platform ($(uname -a)) is not supported."
    exit 1
  fi
}

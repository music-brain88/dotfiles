#!bin/bash

set -u 

echo "Start Initialization"

command_list=("rustup" "fish" "fisher" "nvim" "npm" "awk")

OS=''
command_exists_flag=''

install() {
  if [ $OS = 'Arch' ];then
    if [ "`whoami`" != "root" ]; then
      echo "Require root privilege"
    fi
    echo "root!"
  elif [ $OS = 'Ubuntu' ];then
   echo "sample" 
  elif [ $OS = 'Darwin' ];then
    echo "sample"
  fi
}

check_command_list() {
  for i in ${command_list[@]};
  do
    echo is_exists $i
  done
}

# check command
is_exists() {
  if !(type $1 > /dev/null 2>&1); then
    echo "install `$1`"
    install
  else
    echo "`$1` is exists"
    install
  fi
}

install_rust() {
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  source $HOME/.cargo/env
}

install_fisher() {
  curl https://git.io/fisher --create-dirs -sLo ~/.config/fish/functions/fisher.fish
}
if [ $(uname -o) = "Android" ]; then

  echo "Android OS"

elif [[ $(uname) = "Linux" ]]; then

  ## Arch Linux
  if [ -f /etc/arch-release ]; then
    echo "CurrentOS is Arch Linux"  
    OS=`echo "Arch"`
    check_command_list
  ## Ubuntu / Debian
  elif [ -f /etc/debian_version ] || [ -f /etc/debian_release ]; then
    echo "CurrentOS is Debian/Ubuntu"  
    OS=`echo "Ubuntu"`
    check_command_list
  fi
## MacOS
elif [[ $(uname) = "Darwin" ]]; then
  echo "CurrentOS is MacOS"
    OS=`echo "Darwin"`
    check_command_list
else
  # F0ck wind0ws. G0 t0 he11!
  error "Your platform ($(uname -a)) is not supported."
  exit 1
fi

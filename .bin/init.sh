#!bin/bash

set -ue

echo "Start Initialization"

mkdir -p /tmp/source-code-pro

command_list=("rustup" "fish" "fisher" "nvim" "npm" "awk")

OS=''
command_exists_flag=''

# check command
is_exists() {
  echo "run exists"
  if !(type `$1` > /dev/null 2>&1); then
    echo "install `$1`"
    # install
  else
    echo "`$1` is exists"
  fi
}

check_command_list() {
  for i in ${command_list[@]};
  do
    is_exists $i
  done
}

if [ $(uname -o) = "Android" ]; then

  echo "Android OS"

elif [[ $(uname) = "Linux" ]]; then

  ## Arch Linux
  if [ -f /etc/arch-release ]; then
    echo "CurrentOS is Arch Linux"  
    OS=`echo "Arch"`; exit 0;
  ## Ubuntu / Debian
  elif [ -f /etc/debian_version ] || [ -f /etc/debian_release ]; then
    echo "CurrentOS is Debian/Ubuntu"  
    OS=`echo "Ubuntu"`
    exit 0
  fi
## MacOS
elif [[ $(uname) = "Darwin" ]]; then
  echo "CurrentOS is MacOS"
    OS=`echo "Darwin"`
    exit 0
else
  error "Your platform ($(uname -a)) is not supported."
  exit 1
fi

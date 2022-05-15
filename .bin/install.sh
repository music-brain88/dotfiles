#!bin/bash

set -ue

echo "Start Initialization"

# fisher install
if !(type fisher > /dev/null 2>&1); then
  if (type fish > /dev/null 2>&1); then
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
  else
    echo "Please install fish shell"
  fi
fi

# pyenv install
if !(type pyenv > /dev/null 2>&1); then
  if [ ! -d ~/.pyenv ]; then
    git clone https://github.com/pyenv/pyenv.git ~/.pyenv
    git clone https://github.com/pyenv/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv
  fi
  echo "Please set the pyenv path"
fi

# Rust install
if !(type rustup > /dev/null 2>&1); then
  echo "install Rust compiler"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  echo "finish install rust"
  source $HOME/.cargo/env
else
  echo "Rust is installed"
fi

# deno install
if !(type deno > /dev/null 2>&1); then
  cargo install deno --locked
  # curl -fsSL https://deno.land/install.sh | sh
else
  echo "Deno is installed"
  echo "Rust is installed"
fi


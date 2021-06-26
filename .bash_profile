#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc
if [ "$(uname)" == 'Darwin' ]; then
  #OS='Mac'
  export TO_FISH_PATH=$PATH
  export PATH="$HOME/.poetry/bin:$PATH"
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  #OS='Linux'
  if [ -n "$DISPLAY" ]; then
    xmodmap ~/dotfiles/.Xmodmap
  fi
  export LANG="en_US.UTF-8"
  export LC_CTYPE="en_US.UTF-8"
  export GPG_TTY=$(tty)
  # export PYENV_ROOT="$HOME/.pyenv"
  # export PATH="$PYENV_ROOT/bin:$PATH"
  # export TO_FISH_PATH=$PATH
  export EDITOR=nvim
  if command -v pyenv 1>/dev/null 2>&1; then
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
  fi
elif [ "$(expr substr $(uname -s) 1 10)" == 'MINGW32_NT' ]; then
  OS='Cygwin'
else
  echo "Your platform ($(uname -a)) is not supported."
  exit 1
fi

. "$HOME/.cargo/env"

source /home/archie/.config/broot/launcher/bash/br

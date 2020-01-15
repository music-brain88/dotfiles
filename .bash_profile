#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc
export LC_CTYPE='en_US.UTF-8'
# export LC_CTYPE='ja_JP.UTF-8'
if [ "$(uname)" == 'Darwin' ]; then
  OS='Mac'
  export TO_FISH_PATH=$PATH
  export PATH="$HOME/.poetry/bin:$PATH"
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
  exec fish
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  OS='Linux'
  xmodmap ~/dotfiles/.Xmodmap
  export PATH="$HOME/.poetry/bin:$PATH"
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
elif [ "$(expr substr $(uname -s) 1 10)" == 'MINGW32_NT' ]; then
  OS='Cygwin'
else
  echo "Your platform ($(uname -a)) is not supported."
  exit 1
fi


#
# ~/.bashrc
#

alias vim='nvim'
export TERM=xterm-256color
# If not running interactively, don't do anything

alias ls='ls --color=auto'
#PS1='[\u@\h \W]\$ '

if [ "$(uname)" == 'Darwin' ]; then
  OS='Mac'
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  OS='Linux'
elif [ "$(expr substr $(uname -s) 1 10)" == 'MINGW32_NT' ]; then
  OS='Cygwin'
else
  echo "Your platform ($(uname -a)) is not supported."
  exit 1
fi

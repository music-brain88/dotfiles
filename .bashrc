#
# ~/.bashrc
#

[ -z "$PS1" ] && return
alias vim='nvim'
alias rm='rm -i'
export TERM=xterm-256color
# If not running interactively, don't do anything

alias ls='ls --color=auto'
#PS1='[\u@\h \W]\$ '

if [ "$(uname)" == 'Darwin' ]; then
  OS='Mac'
  exec fish
elif [ "$(expr substr $(uname -s) 1 5)" == 'Linux' ]; then
  OS='Linux'
  # if using wsl
    eval "$(ssh-agent -s)"
    export GPG_AGENT_INFO
    export SSH_AUTH_SOCK
    export SSH_AGENT_PID
    export GPG_TTY=$(tty)
  if [[ "$(uname -r)" == *microsoft* ]]; then
    export GPG_TTY=$(tty)
  fi
  exec fish
elif [ "$(expr substr $(uname -s) 1 10)" == 'MINGW32_NT' ]; then
  OS='Cygwin'
else
  echo "Your platform ($(uname -a)) is not supported."
  exit 1
fi

. "$HOME/.cargo/env"
# aliases file check
if [ -f ~/.bash_aliases ]; then
. ~/.bash_aliases
fi

source /home/archie/.config/broot/launcher/bash/br

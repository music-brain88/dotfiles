#                                   d8b                888                       d8b           .d8888b.   .d8888b.  d8b         
#                                   Y8P                888                       Y8P          d88P  Y88b d88P  Y88b 88P         
#                                                      888                                    Y88b. d88P Y88b. d88P 8P          
#   88888b.d88b.  888  888 .d8888b  888  .d8888b       88888b.  888d888  8888b.  888 88888b.   "Y88888"   "Y88888"  "  .d8888b  
#   888 "888 "88b 888  888 88K      888 d88P"          888 "88b 888P"       "88b 888 888 "88b .d8P""Y8b. .d8P""Y8b.    88K      
#   888  888  888 888  888 "Y8888b. 888 888     888888 888  888 888     .d888888 888 888  888 888    888 888    888    "Y8888b. 
#   888  888  888 Y88b 888      X88 888 Y88b.          888 d88P 888     888  888 888 888  888 Y88b  d88P Y88b  d88P         X88 
#   888  888  888  "Y88888  88888P' 888  "Y8888P       88888P"  888     "Y888888 888 888  888  "Y8888P"   "Y8888P"      88888P' 
#                                                                                                                               
#                                                                                                                               
#                                                                                                                               
#   888                        888                                        .d888 d8b                                             
#   888                        888                                       d88P"  Y8P                                             
#   888                        888                                       888                                                    
#   88888b.   8888b.  .d8888b  88888b.         .d8888b  .d88b.  88888b.  888888 888  .d88b.                                     
#   888 "88b     "88b 88K      888 "88b       d88P"    d88""88b 888 "88b 888    888 d88P"88b                                    
#   888  888 .d888888 "Y8888b. 888  888       888      888  888 888  888 888    888 888  888                                    
#   888 d88P 888  888      X88 888  888       Y88b.    Y88..88P 888  888 888    888 Y88b 888                                    
#   88888P"  "Y888888  88888P' 888  888        "Y8888P  "Y88P"  888  888 888    888  "Y88888                                    
#                                                                                        888                                    
#                                                                                   Y8b d88P                                    
#                                                                                    "Y88P"                                     


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


gpgconf --launch gpg-agent
export GPG_TTY=$(tty)
LANG=C gpg-connect-agent updatestartuptty /bye
unset SSH_AGENT_PID
if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
  export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi

if [ -f ~/.dotfiles/submodules/bash-wakatime ]; then
. ~/.dotfiles/submodules/bash-wakatime/bash-wakatime.sh
fi

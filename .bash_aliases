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

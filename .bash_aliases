gpgconf --launch gpg-agent
export GPG_TTY=$(tty)
LANG=C gpg-connect-agent updatestartuptty /bye
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"

if [ -f ~/.dotfiles/submodules/bash-wakatime ]; then
. ~/.dotfiles/submodules/bash-wakatime/bash-wakatime.sh
fi

gpgconf --launch gpg-agent
export GPG_TTY=$(tty)
LANG=C gpg-connect-agent updatestartuptty /bye
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"

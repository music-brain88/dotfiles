#
# ~/.bashrc
# Minimal bootstrap to launch fish shell
#

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# Set up environment variables that need to be inherited by fish
if [ "$(uname -s)" = 'Linux' ]; then
  # Start ssh-agent if not already running
  if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
  fi
  export GPG_TTY=$(tty)
fi

# Launch fish shell
exec fish

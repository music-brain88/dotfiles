#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
EDITOR=/usr/bin/vi

function _update_ps1() {
    PS1="$(~/.local/bin/powerline-shell $?)"
}

if [[ $TERM != linux && ! $PROMPT_COMMAND =~ _update_ps1 ]]; then
    PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
fi

alias vim='nvim'
alias py37='source ~/Documents/envlist/py37/bin/activate'

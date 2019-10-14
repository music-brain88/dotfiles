#
# ~/.bashrc
#

alias vim='nvim'
export TERM=xterm-256color
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
#PS1='[\u@\h \W]\$ '

xmodmap ~/dotfiles/.xmodmap

exec fish

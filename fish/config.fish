set -U FZF_LEGACY_KEYBINDINGS 0

alias vim='nvim'

# bobthefish setting
set -g theme_powerline_fonts no
set -g theme_nerd_fonts yes
set -g theme_display_user ssh
set -g theme_display_date no

# fish git prompt
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate 'yes'
set __fish_git_prompt_showupstream 'yes'
set __fish_git_prompt_color_branch yellow

export TERM=xterm-256color

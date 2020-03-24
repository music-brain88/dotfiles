set -U FZF_LEGACY_KEYBINDINGS 0

alias vim='nvim'
set PATH $TO_FISH_PATH $PATH

# set pyenv path
set PATH $HOME/.pyenv/shims $PATH
eval (pyenv init - | source)

# set cargo path
set PATH $HOME/.cargo/bin $PATH

# set exa path
set PATH $HOME/.cargo/bin $PATH
alias ls='exa --icons'

# set poetry path
# set -U PATH $HOME/.poetry/env $PATH

# if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi
# export PATH="$HOME/.rbenv/bin:$PATH"
# eval $(rbenv init - | source)

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

function reload
  exec fish
end

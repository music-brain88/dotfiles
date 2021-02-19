set -U FZF_LEGACY_KEYBINDINGS 0

alias vim='nvim'
# set PATH $TO_FISH_PATH $PATH

# set pyenv path
set -x PYENV_ROOT $HOME/.pyenv
set -x PATH $PYENV_ROOT/bin $PATH

# set cargo path
set -x PATH $HOME/.cargo/bin $PATH

# set exa alias
alias ls='exa --icons'

# set bat alias
alias cat='bat'
alias ps='procs'
# set poetry path
# set -U PATH $HOME/.poetry/env $PATH

# if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi
# export PATH="$HOME/.rbenv/bin:$PATH"
# eval $(rbenv init - | source)

# bobthefish setting
set -g theme_powerline_fonts no
set -g theme_nerd_fonts yes
set -g theme_display_user ssh
set -g theme_display_date yes

# fish git prompt
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate 'yes' set __fish_git_prompt_showupstream 'yes'
set __fish_git_prompt_color_branch yellow


# set fzf setting
set -x PATH ~/.fzf/bin $PATH
set -x FZF_LEGACY_KEYBINDINGS 0
set -x FZF_REVERSE_ISEARCH_OPTS "--height=50%"

# set GO PATH
set -x GOPATH $HOME/go
set -x PATH $PATH $GOPATH/bin

export TERM=xterm-256color

function reload
  exec fish
end

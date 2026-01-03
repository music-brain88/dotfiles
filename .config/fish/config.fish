set -U FZF_LEGACY_KEYBINDINGS 0

# Locale settings
set -x LANG en_US.UTF-8
set -x LC_CTYPE en_US.UTF-8

# Aliases
alias vim 'nvim'
alias rm 'rm -i'

# set pyenv path
set -x PYENV_ROOT $HOME/.pyenv
set -x PATH $PYENV_ROOT/bin $PATH

# set cargo path
set -x PATH $HOME/.cargo/bin $PATH

# set pulimi path
set -x PATH $HOME/.pulumi/bin $PATH


# set exa alias
if type -q test eza
  alias ls='eza --icons'
end

# set bat alias
if type -q bat
  alias cat='bat'
end

# set procs alias
if type -q procs
  alias ps='procs'
end

# set jql alias
#if type -q jql
#  alias jq='jql'
#end

# fish git prompt
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate 'yes' set __fish_git_prompt_showupstream 'yes'
set __fish_git_prompt_color_branch yellow


# set GO PATH
set -x GOPATH $HOME/go
set -x PATH $PATH $GOPATH/bin

export TERM=xterm-256color

# set skim setting
set -x PATH ~/.skim/bin $PATH
set -x SKIM_DEFAULT_COMMAND 'rg --files --hidden --follow --glob "!.git/*"'


function reload
  exec fish
end

# set startship
starship init fish | source
# set -gx VOLTA_HOME "$HOME/.volta"
# set -gx PATH "$VOLTA_HOME/bin" $PATH

~/.local/bin/mise activate fish | source

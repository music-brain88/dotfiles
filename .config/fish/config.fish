set -U FZF_LEGACY_KEYBINDINGS 0

alias vim='nvim'
# set PATH $TO_FISH_PATH $PATH

# set pyenv path
set -x PYENV_ROOT $HOME/.pyenv
set -x PATH $PYENV_ROOT/bin $PATH

# set cargo path
set -x PATH $HOME/.cargo/bin $PATH

# set pulimi path
set -x PATH $HOME/.pulumi/bin $PATH

# set mise path
~/.local/bin/mise activate fish | source

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

# set poetry path
# set -U PATH $HOME/.poetry/env $PATH

# if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi
# export PATH="$HOME/.rbenv/bin:$PATH"
# eval $(rbenv init - | source)

# fish git prompt
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate 'yes' set __fish_git_prompt_showupstream 'yes'
set __fish_git_prompt_color_branch yellow


# set fzf setting
set -x PATH ~/.fzf/bin $PATH
set -x FZF_LEGACY_KEYBINDINGS 0
set -x FZF_REVERSE_ISEARCH_OPTS "--height=50%"
set -x FZF_DEFAULT_COMMAND 'rg --files --hidden --follow --glob "!.git/*"'

# set GO PATH
set -x GOPATH $HOME/go
set -x PATH $PATH $GOPATH/bin

export TERM=xterm-256color

function fzf-checkout-branch
    set -l branchname (
        env FZF_DEFAULT_COMMAND='git --no-pager branch -a | grep -v HEAD | sed -e "s/^.* //g"' \
            fzf --height 70% --prompt "BRANCH NAME>" \
                --preview "git --no-pager log -20 --color=always {}"
    )
    if test -n "$branchname"
        git checkout (echo "$branchname"| sed "s#remotes/[^/]*/##")
    end
end

function fzf-docker-continer-name-select
    commandline -i (env FZF_DEFAULT_COMMAND="docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Command}}\t{{.RunningFor}}\t{{.Ports}}\t{{.Networks}}'" \
        fzf --no-sort --height 80% --bind='p:toggle-preview' --preview-window=down:70% \
            --preview '
                set -l containername (echo {} | awk -F " " \'{print $2}\');
                if test "$containername" != "ID"
                    docker logs --tail 300 $containername
                end
            ' | \
        awk -F " " '{print $2}')
end

function reload
  exec fish
end

# set startship
starship init fish | source
set -gx VOLTA_HOME "$HOME/.volta"
set -gx PATH "$VOLTA_HOME/bin" $PATH


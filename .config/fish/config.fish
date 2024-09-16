set -U FZF_LEGACY_KEYBINDINGS 0

alias vim='nvim'

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

function skim-checkout-branch
    set -l branchname (
        env SKIM_DEFAULT_COMMAND='git --no-pager branch -a | grep -v HEAD | sed -e "s/^.* //g"' \
            sk --height 70% --prompt "BRANCH NAME>" \
                --preview "git --no-pager log -20 --color=always {}"
    )

    if test -n "$branchname"
        git checkout (echo "$branchname"| sed "s#remotes/[^/]*/##")
    end
end


function skim-docker-container-name-select
    commandline -i (env SKIM_DEFAULT_COMMAND="docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Command}}\t{{.RunningFor}}\t{{.Ports}}\t{{.Networks}}'" \
        sk --no-sort --height 80% --bind='p:toggle-preview' --preview-window=down:70% \
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


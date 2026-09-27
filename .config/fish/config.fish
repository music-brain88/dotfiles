# Home Managerのhome.sessionVariablesはhm-session-vars.sh(bashスクリプト)に出力されるが、
# fishはbashスクリプトを自動で読み込まないため、bassプラグインを使ってsourceする
# Reset flag to ensure latest session variables are always loaded after nix:switch
set -e __HM_SESS_VARS_SOURCED
bass source ~/.nix-profile/etc/profile.d/hm-session-vars.sh
# bass は空文字で export された変数を「未定義」と誤判定し、universal の fish_user_paths='' を global に写す。
# fish のハンドラがその空要素を PATH 先頭に足し、PATH の空要素は '.' に正規化されるので、カレントが PATH に入る (#610)
# set -eg だけでは消えない: ハンドラは前回足した "" を PATH から探すが、PATH 側には '.' で入っていて一致しない
# bass treats empty exported vars as undefined and copies the universal fish_user_paths='' into global scope.
# fish's handler prepends that empty element to PATH, which fish stores as '.', putting cwd on PATH (#610)
# set -eg alone is not enough: the handler looks for "" in PATH, but it is stored as '.', so strip '.' explicitly
set -eg fish_user_paths; set -gx PATH (string match -v -- . $PATH)

# Locale settings
set -x LANG en_US.UTF-8
set -x LC_CTYPE en_US.UTF-8

# Editor settings
set -x EDITOR nvim
set -x VISUAL nvim

# GPG: tell gpg-agent which tty to use for pinentry (interactive shells only)
# gpg-agentにこのシェルのttyを伝える(pinentry用、対話シェルのみ)
if status is-interactive; and isatty stdin
  set -gx GPG_TTY (tty)
  # SSH session: refresh gpg-agent's cached tty so pinentry can reach us
  # SSHセッション時はgpg-agentが保持するttyを更新する
  if set -q SSH_CONNECTION
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
  end
end

# Aliases
alias vim 'nvim'
alias rm 'rm -i'

# PATH は fish_add_path --path で冪等に追加する。入れ子シェルでも重複せず、存在しない dir は無視される (#595)
# --path を外すと universal 変数 fish_user_paths (リポジトリ外の fish_variables) に書き込むので必ず付ける
# Add PATH entries idempotently with fish_add_path --path: no duplicates in nested shells, missing dirs are skipped (#595)
# Always pass --path; without it fish writes to the universal fish_user_paths (fish_variables, outside the repo)

# set pyenv path
set -x PYENV_ROOT $HOME/.pyenv
fish_add_path --path $PYENV_ROOT/bin

# set cargo path (cargo の PATH 宣言はここだけ。rust-tools.nix の home.sessionPath は #595 で削除)
# The only cargo PATH declaration; home.sessionPath in rust-tools.nix was removed in #595
# --append で末尾に置き、Nix 版が常に勝つようにする。~/.cargo/bin は Nix に無い cargo install 専用ツール(deno / zellij / broot 等)だけを拾うフォールバック。Nix と同名の cargo 版は掃除対象 (#611)
# Appended so the Nix-managed version always wins; ~/.cargo/bin is only a fallback for cargo-install-only tools Nix doesn't provide (deno / zellij / broot, etc). Cargo builds that shadow a same-named Nix package are cleanup targets (#611)
fish_add_path --path --append $HOME/.cargo/bin

# set pulumi path
fish_add_path --path $HOME/.pulumi/bin

# set ~/.local/bin path (native installer 管理ツール: claude 等 / native-installer tools such as claude)
# 以前は化石 mise の activate が副作用で入れていた。fish_add_path は冪等なので入れ子シェルでも重複しない (#593)
# Formerly injected as a side effect of the fossil mise activate; fish_add_path is idempotent across nested shells (#593)
# --append で末尾に置き、Nix 版が常に勝つようにする。~/.local/bin は Nix に無いものだけを拾うフォールバック (#596)
# Appended so the Nix-managed version always wins; ~/.local/bin is only a fallback for tools Nix doesn't provide (#596)
fish_add_path --path --append $HOME/.local/bin


# set exa alias
if type -q test eza
  alias ls='eza --icons'
end

# set bat alias
if type -q bat
  alias cat='bat'
end

# procs alias disabled - procs uses -p for --pager, breaks scripts using ps -p
# if type -q procs
#   alias ps='procs'
# end

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
fish_add_path --path --append $GOPATH/bin

export TERM=xterm-256color

# set skim setting (skim 本体は Nix 管理: nix/modules/rust-tools.nix。旧 git clone 版の ~/.skim/bin は #595 で PATH から削除)
# skim itself is Nix-managed (nix/modules/rust-tools.nix); the legacy git-clone ~/.skim/bin was dropped from PATH in #595
set -x SKIM_DEFAULT_COMMAND 'rg --files --hidden --follow --glob "!.git/*"'


function reload
  exec fish
end

# set startship
starship init fish | source
# set -gx VOLTA_HOME "$HOME/.volta"
# set -gx PATH "$VOLTA_HOME/bin" $PATH

mise activate fish | source

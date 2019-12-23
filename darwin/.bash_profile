if [ -f ~/.bashrc ] ; then
. ~/.bashrc
fi


alias ls='ls -G'
alias vim="nvim"
alias vi="nvim"
alias py37='source ~/Documents/python_env/default/bin/activate'
alias expy='source ~/Documents/python_env/venv/bin/activate'

PS1='\e[0;34m[\W ]\e[0;31m\$ \e[0m' 
function _update_ps1() {
   PS1="$(powerline-shell $?)"
}

if [ "$TERM" != "linux" ]; then
    PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
fi

# if [[ $TERM != linux && ! $PROMPT_COMMAND =~ _update_ps1 ]]; then
#    PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
# fi


if [ -f $(brew --prefix)/etc/bash_completion ]; then
  . $(brew --prefix)/etc/bash_completion
fi

export PYENV_ROOT=/usr/local/var/pyenv
if which pyenv > /dev/null; then eval "$(pyenv init -)"; fi
if which pyenv-virtualenv-init > /dev/null; then eval "$(pyenv virtualenv-init -)"; fi
export CFLAGS="-I$(brew --prefix openssl)/include"
export LDFLAGS="-L$(brew --prefix openssl)/lib"
export PYTHON_CONFIGURE_OPTS="--enable-unicode=ucs2"
# export PATH=$PATH:$HOME/.pyenv/shims
if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"
export PATH=$PATH:/usr/local/bin
export PATH="/usr/local/opt/openssl/bin:$PATH"
# Setting PATH for Python 3.6
# The original version is saved in .bash_profile.pysave
# PATH="/Library/Frameworks/Python.framework/Versions/3.6/bin:${PATH}"
export PATH

# export PATH=/Users/arch/Library/Python/2.7/bin:/usr/local/opt/openssl/bin:/usr/local/Cellar/pyenv-virtualenv/1.1.3/shims:/usr/local/var/pyenv/shims:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/opt/openssl/bin:/usr/local/Cellar/pyenv-virtualenv/1.1.3/shims:/usr/local/var/pyenv/shims:/Users/arch/.pyenv/shims:/Users/arch/.pyenv/shims
export PATH="/usr/local/opt/llvm/bin:$PATH"
export BASH_SILENCE_DEPRECATION_WARNING=1
# For compilers to find readline you may need to set:
export LDFLAGS="-L/usr/local/opt/readline/lib"
export CPPFLAGS="-I/usr/local/opt/readline/include"

# For pkg-config to find readline you may need to set:
export PKG_CONFIG_PATH="/usr/local/opt/readline/lib/pkgconfig"
# nodebrew
export PATH=$HOME/.nodebrew/current/bin:$PATH


export PATH="$HOME/.poetry/bin:$PATH"

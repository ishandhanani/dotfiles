# Bash configuration

# Exports
export EDITOR='vim'
export VISUAL='vim'
export GPG_TTY=$(tty) 
export PATH=$PATH:$HOME/go/bin

# History settings
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar 2> /dev/null

# Git aliases
alias ga="git add"
alias gc="git commit"
alias gps="git push"
alias gs="git status"
alias gpl="git pull"
alias gf="git fetch"
alias gcb="git checkout -b"
alias gp="git push"
alias gll="git log"

# Shell aliases
alias editb="vim ~/.bashrc"
alias sourceb="source ~/.bashrc"
alias v="vim ."
alias ll="ls -alh"
alias d="docker"
alias dc="docker compose"
alias k="kubectl"
alias m="make"
alias c="cursor ."
alias speed="speedtest"
alias cat="bat --style=plain"

# Navigation
alias godesk="cd ~/Desktop"
alias godown="cd ~/Downloads"

# brev
alias brs="brev refresh && brev ls"

# eza
alias ls='eza --color=always --group-directories-first'
alias ll='eza -la --color=always --group-directories-first'
alias ltree='eza --tree --level=3 --color=always'

# ip util
alias myip="curl -s icanhazip.com"

# Enable bash completion if available
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
elif [ -f /usr/local/etc/bash_completion ]; then
    . /usr/local/etc/bash_completion
fi

# Initialize starship if installed
command -v starship &>/dev/null && eval "$(starship init bash)"
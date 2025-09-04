# Zsh configuration

# Load edit-cmd-line
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Exports
export EDITOR='vim'
export VISUAL='vim'
export GPG_TTY=$(tty) 
export PATH=$PATH:$HOME/go/bin

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
alias editz="vim ~/.zshrc"
alias sourcez="source ~/.zshrc"
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
alias godesk="cd /Users/$USER/Desktop"
alias godown="cd /Users/$USER/Downloads"

# brev
alias brs="brev refresh && brev ls"

# eza
alias ls='eza --color=always --group-directories-first'
alias ll='eza -la --color=always --group-directories-first'
alias ltree='eza --tree --level=3 --color=always'

# ip util
alias myip="curl -s icanhazip.com"

# Git AI functions
function git_ai_commit() {
    if ! git diff --cached --quiet; then
        commit_msg=$(cgpt --no-history << EOF 2>/dev/null
Generate a semantic commit message following the format: type(scope): description
Common types: feat, fix, docs, style, refactor, test, chore
Here are the staged files:
$(git diff --cached --name-only)
And here are the changes:
$(git diff --cached)
Respond ONLY with the commit message, nothing else. Make it concise and descriptive.
EOF
)
        echo "$commit_msg"
        git commit -m "$commit_msg" > /dev/null 2>&1
    else
        echo "No staged changes"
    fi
}

function gprai() {
  local current_branch base_ref branch_diff changed_files pr_prompt pr_content
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    base_ref=origin/main
  elif git show-ref --verify --quiet refs/heads/main; then
    base_ref=main
  else
    echo "Error: 'main' branch not found locally or on origin."
    return 1
  fi

  branch_diff=$(git diff "$base_ref...$current_branch")
  changed_files=$(git diff --name-only "$base_ref...$current_branch")

  pr_prompt=$(cat <<EOF
Generate a PR title and description based on these changes.
Use semantic format: type(scope): description
Common types: feat, fix, docs, style, refactor, test, chore

Files changed:
$changed_files

Diff:
$branch_diff

Respond *exactly* in this format:

TITLE: <type(scope): concise summary>
DESCRIPTION:
## Overview
<one‐ or two‐sentence high‐level summary>
## Changes Made
- <bullet points of specific changes>
EOF
  )

  pr_content=$(cgpt --no-history <<EOF
$pr_prompt
EOF
  )

  printf "%s\n" "$pr_content"
}

alias gcai="git_ai_commit"

# Source external env if exists
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Initialize atuin if installed
if [ -f "$HOME/.atuin/bin/env" ]; then
    . "$HOME/.atuin/bin/env"
    eval "$(atuin init zsh)"
fi

# Initialize starship if installed
command -v starship &>/dev/null && eval "$(starship init zsh)"
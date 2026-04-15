#!/usr/bin/env bash
# bootstrap.sh - Portable setup for Linux machines without Nix.
# Mirrors the home-manager config as closely as possible using
# plain curl/bash installs and a generated ~/.bashrc.d/ drop-in.
#
# Usage:  curl -fsSL <raw-url> | bash
#    or:  bash bootstrap.sh
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { printf '\033[1;34m=> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m   %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m!! %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Rust (via rustup) -- matches modules/rust.nix
# ---------------------------------------------------------------------------
info "Rust toolchain"
if command -v rustup &>/dev/null; then
  ok "rustup already installed"
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  ok "rustup installed"
fi
# shellcheck source=/dev/null
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# ---------------------------------------------------------------------------
# 2. uv (Python toolchain) -- mirrors home.packages uv
# ---------------------------------------------------------------------------
info "uv"
if command -v uv &>/dev/null; then
  ok "uv already installed"
else
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ok "uv installed"
fi
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# 3. Starship prompt -- mirrors programs.starship
# ---------------------------------------------------------------------------
info "Starship prompt"
if command -v starship &>/dev/null; then
  ok "starship already installed"
else
  curl -sS https://starship.rs/install.sh | sh -s -- -y
  ok "starship installed"
fi

# ---------------------------------------------------------------------------
# 4. Atuin (shell history) -- mirrors programs.atuin
# ---------------------------------------------------------------------------
info "Atuin"
if command -v atuin &>/dev/null; then
  ok "atuin already installed"
else
  curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
  ok "atuin installed"
fi

# ---------------------------------------------------------------------------
# 5. Cargo-installable CLI tools
#    bat, eza, fd, ripgrep, zoxide, delta, yazi, zellij, sccache
# ---------------------------------------------------------------------------
declare -A CARGO_BINS=(
  [bat]="bat"
  [eza]="eza"
  [fd]="fd-find"
  [rg]="ripgrep"
  [zoxide]="zoxide"
  [delta]="git-delta"
  [sccache]="sccache"
  [zellij]="zellij"
  [yazi]="yazi-fm"
)

info "Cargo CLI tools"
for bin in "${!CARGO_BINS[@]}"; do
  if command -v "$bin" &>/dev/null; then
    ok "$bin already installed"
  else
    info "Installing ${CARGO_BINS[$bin]} ..."
    cargo install "${CARGO_BINS[$bin]}"
    ok "$bin installed"
  fi
done

# ---------------------------------------------------------------------------
# 6. fzf (git install -- prebuilt binary)
# ---------------------------------------------------------------------------
info "fzf"
if command -v fzf &>/dev/null; then
  ok "fzf already installed"
else
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --bin --no-update-rc --no-completion --no-key-bindings
  ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
  ok "fzf installed"
fi

# ---------------------------------------------------------------------------
# 7. GitHub CLI (gh)
# ---------------------------------------------------------------------------
info "GitHub CLI (gh)"
if command -v gh &>/dev/null; then
  ok "gh already installed"
else
  GH_VERSION="$(curl -sL https://api.github.com/repos/cli/cli/releases/latest | grep tag_name | cut -d'"' -f4 | sed 's/^v//')"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
  esac
  curl -sL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
    | tar xz --strip-components=2 -C "$HOME/.local/bin" "gh_${GH_VERSION}_linux_${ARCH}/bin/gh"
  ok "gh installed"
fi

# ---------------------------------------------------------------------------
# 8. jq + yq
# ---------------------------------------------------------------------------
info "jq"
if command -v jq &>/dev/null; then
  ok "jq already installed"
else
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  JQ_ARCH="amd64" ;;
    aarch64) JQ_ARCH="arm64" ;;
  esac
  curl -sL "https://github.com/jqlang/jq/releases/latest/download/jq-linux-${JQ_ARCH}" -o "$HOME/.local/bin/jq"
  chmod +x "$HOME/.local/bin/jq"
  ok "jq installed"
fi

info "yq"
if command -v yq &>/dev/null; then
  ok "yq already installed"
else
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  YQ_ARCH="amd64" ;;
    aarch64) YQ_ARCH="arm64" ;;
  esac
  curl -sL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}" -o "$HOME/.local/bin/yq"
  chmod +x "$HOME/.local/bin/yq"
  ok "yq installed"
fi

# ---------------------------------------------------------------------------
# 9. uvx tools -- mirrors modules/uvx.nix
# ---------------------------------------------------------------------------
info "uvx tools (llm, y-cli, ty)"
for tool in llm y-cli ty; do
  if uv tool list 2>/dev/null | grep -q "^$tool "; then
    ok "$tool already installed"
  else
    uv tool install "$tool"
    ok "$tool installed"
  fi
done

# ---------------------------------------------------------------------------
# 10. Shell config drop-in (~/.bashrc.d/dotfiles.bash)
#     Mirrors bash.nix + zsh.nix aliases and env vars
# ---------------------------------------------------------------------------
info "Writing shell config"
mkdir -p "$HOME/.bashrc.d"

cat > "$HOME/.bashrc.d/dotfiles.bash" << 'DOTFILES_BASHRC'
# -- Generated by dotfiles/bootstrap.sh --
# Mirrors home-manager bash.nix / zsh.nix config

# Environment
export EDITOR="nvim"
export VISUAL="nvim"
export RUSTC_WRAPPER="sccache"
export GPG_TTY="$(tty)"
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:$PATH"

# Source Cargo env
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
# Source uv env
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# ---- Aliases (from bash.nix) ----

# Git shortcuts
alias ga="git add"
alias gc="git commit"
alias gps="git push"
alias gs="git status"
alias gpl="git pull"
alias gf="git fetch"
alias gcb="git checkout -b"
alias gp="git push"
alias gll="git log --oneline"
alias gd="git diff"
alias gco="git checkout"

# Basic aliases
alias v="nvim"
alias d="docker"
alias dc="docker compose"
alias k="kubectl"
alias m="make"

# Tool aliases
alias cat="bat --style=plain --paging=never"
alias ls="eza --color=always --group-directories-first"
alias ll="eza -la --color=always --group-directories-first"
alias tree="eza --tree"

# Networking
alias myip="curl -s icanhazip.com"

# venv
alias venv="source .venv/bin/activate"

# ---- Integrations ----

# Starship
eval "$(starship init bash)"

# Atuin
eval "$(atuin init bash)"

# Zoxide
eval "$(zoxide init bash)"

# fzf
[ -f "$HOME/.fzf/bin/fzf" ] && eval "$("$HOME/.fzf/bin/fzf" --bash 2>/dev/null)" || true

# Yazi cd-on-quit wrapper
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# Source local machine-specific overrides
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
DOTFILES_BASHRC

ok "Wrote ~/.bashrc.d/dotfiles.bash"

# ---------------------------------------------------------------------------
# 11. Starship config -- mirrors programs.starship.settings
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config"
cat > "$HOME/.config/starship.toml" << 'STARSHIP_TOML'
command_timeout = 500

[aws]
disabled = true

[gcloud]
disabled = true

[git_status]
disabled = true
STARSHIP_TOML

ok "Wrote ~/.config/starship.toml"

# ---------------------------------------------------------------------------
# 12. Git config extras -- mirrors modules/git.nix
# ---------------------------------------------------------------------------
info "Git config"
git config --global user.name "Ishan Dhanani"
git config --global user.email "ishandhanani@gmail.com"
git config --global core.editor "vim"
git config --global core.fsmonitor true
git config --global core.untrackedCache true
git config --global init.defaultBranch "main"
git config --global pull.rebase false
git config --global push.default "simple"
git config --global core.pager "delta"
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.line-numbers true
git config --global delta.side-by-side true
git config --global url."git@github.com:".insteadOf "https://github.com/"
ok "Git config applied"

# ---------------------------------------------------------------------------
# 13. Wire the drop-in into ~/.bashrc if not already sourced
# ---------------------------------------------------------------------------
BASHRC="$HOME/.bashrc"
HOOK='# dotfiles bootstrap drop-in
for f in "$HOME"/.bashrc.d/*.bash; do [ -r "$f" ] && . "$f"; done'

if ! grep -qF '.bashrc.d' "$BASHRC" 2>/dev/null; then
  info "Adding drop-in loader to ~/.bashrc"
  printf '\n%s\n' "$HOOK" >> "$BASHRC"
  ok "~/.bashrc updated"
else
  ok "~/.bashrc already sources ~/.bashrc.d/"
fi

# ---------------------------------------------------------------------------
echo ""
info "Done! Open a new shell or run:  source ~/.bashrc"

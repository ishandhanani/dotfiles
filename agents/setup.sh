#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"
CLAUDE_SRC="$SOURCE_DIR/CLAUDE.md"
CLAUDE_SETTINGS_SRC="$SOURCE_DIR/claude-settings.json"
CLAUDE_STATUSLINE_SRC="$SOURCE_DIR/statusline-command.sh"
SKILLS_SRC="$SOURCE_DIR/skills"
LOCAL_SKILLS_SRC="$HOME/.local_skills"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [[ $# -gt 0 ]]; then
    echo "setup.sh takes no arguments and always installs Claude, Codex, Cursor, Devin, and Hermes (when present)."
    exit 1
fi

if [[ ! -f "$CLAUDE_SRC" ]]; then
    echo "Missing source file: $CLAUDE_SRC" >&2
    exit 1
fi

if [[ ! -d "$SKILLS_SRC" ]]; then
    echo "Missing skills directory: $SKILLS_SRC" >&2
    exit 1
fi

if [[ ! -f "$CLAUDE_SETTINGS_SRC" ]]; then
    echo "Missing source file: $CLAUDE_SETTINGS_SRC" >&2
    exit 1
fi

if [[ ! -f "$CLAUDE_STATUSLINE_SRC" ]]; then
    echo "Missing source file: $CLAUDE_STATUSLINE_SRC" >&2
    exit 1
fi

backup_if_needed() {
    local target="$1"
    local backup_dir="$2"

    if [[ -L "$target" ]]; then
        rm "$target"
        return
    fi

    if [[ -e "$target" ]]; then
        mkdir -p "$backup_dir"
        mv "$target" "$backup_dir/"
    fi
}

create_link() {
    local src="$1"
    local dest="$2"
    local backup_dir="$3"

    if [[ ! -e "$src" ]]; then
        echo "Source not found: $src" >&2
        return 1
    fi

    backup_if_needed "$dest" "$backup_dir"
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$src" "$dest"
    echo "Linked $dest -> $src"
}

each_skill_dir() {
    local skill_dir
    for skill_dir in "$SKILLS_SRC"/* "$LOCAL_SKILLS_SRC"/*; do
        if [[ -d "$skill_dir" ]]; then
            printf '%s\n' "$skill_dir"
        fi
    done
}

link_skills_into() {
    local label="$1"
    local target_skills_dir="$2"
    local backup_dir="$3"
    local skill_dir skill_name

    mkdir -p "$target_skills_dir"
    while IFS= read -r skill_dir; do
        skill_name="$(basename "$skill_dir")"
        create_link "$skill_dir" "$target_skills_dir/$skill_name" "$backup_dir"
    done < <(each_skill_dir)
}

install_agent() {
    local label="$1"
    local target_dir="$2"
    local primary_instruction="$3"
    local backup_dir="$HOME/.$(basename "$target_dir")-backup-${TIMESTAMP}"

    echo ""
    echo "Setting up ${label} config..."
    echo "-----------------------------"
    mkdir -p "$target_dir"

    create_link "$CLAUDE_SRC" "$target_dir/$primary_instruction" "$backup_dir"
    link_skills_into "$label" "$target_dir/skills" "$backup_dir"

    echo ""
    echo "Installed in $target_dir:"
    echo "  $primary_instruction"
    while IFS= read -r skill_dir; do
        echo "  skills/$(basename "$skill_dir")"
    done < <(each_skill_dir)

    if [[ -d "$backup_dir" ]]; then
        echo ""
        echo "Backed up previous ${label} files to: $backup_dir"
    fi
}

# Skills-only install for agents that discover ~/.…/skills without a CLAUDE.md home.
install_skills_home() {
    local label="$1"
    local target_skills_dir="$2"
    local backup_dir="$HOME/.${label}-backup-${TIMESTAMP}"

    echo ""
    echo "Setting up ${label} skills..."
    echo "-----------------------------"
    link_skills_into "$label" "$target_skills_dir" "$backup_dir"

    echo ""
    echo "Installed in $target_skills_dir:"
    while IFS= read -r skill_dir; do
        echo "  $(basename "$skill_dir")"
    done < <(each_skill_dir)

    if [[ -d "$backup_dir" ]]; then
        echo ""
        echo "Backed up previous ${label} files to: $backup_dir"
    fi
}

install_claude_runtime_files() {
    local target_dir="$1"
    local backup_dir="$HOME/.$(basename "$target_dir")-backup-${TIMESTAMP}"

    create_link "$CLAUDE_SETTINGS_SRC" "$target_dir/claude-settings.json" "$backup_dir"
    create_link "$CLAUDE_STATUSLINE_SRC" "$target_dir/statusline-command.sh" "$backup_dir"

    echo "  claude-settings.json"
    echo "  statusline-command.sh"
}

echo "Agent config setup"
echo "=================="
echo "Source: $SOURCE_DIR"

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

install_agent "claude" "$CLAUDE_DIR" "CLAUDE.md"
install_claude_runtime_files "$CLAUDE_DIR"
install_agent "codex" "${CODEX_HOME:-$HOME/.codex}" "CLAUDE.md"

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
backup_if_needed "$CODEX_DIR/AGENTS.md" "$HOME/.codex-backup-${TIMESTAMP}"
ln -sfn "$CODEX_DIR/CLAUDE.md" "$CODEX_DIR/AGENTS.md"
echo "Linked $CODEX_DIR/AGENTS.md -> $CODEX_DIR/CLAUDE.md"

# Cursor personal skills: ~/.cursor/skills (never ~/.cursor/skills-cursor).
install_skills_home "cursor" "$HOME/.cursor/skills"

# Devin user skills: primary documented global root.
# (~/.agents/skills is also scanned by Devin but is left for third-party /
# shared installs so we do not triple-list against ~/.claude compat.)
install_skills_home "devin" "$HOME/.config/devin/skills"

# Hermes discovers skills natively via skills.external_dirs (no per-skill
# symlinks). Point it at this repo's skills dir if hermes is installed.
configure_hermes() {
    if ! command -v hermes >/dev/null 2>&1; then
        echo ""
        echo "hermes not on PATH -- skipping hermes skills config."
        return
    fi
    echo ""
    echo "Setting up hermes config..."
    echo "-----------------------------"
    hermes config set skills.external_dirs "$SKILLS_SRC"
}

configure_hermes

echo ""
echo "Setup complete."

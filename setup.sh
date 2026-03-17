#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/agents"
COMMON_SRC="$SOURCE_DIR/common.md"
CODEX_SRC="$SOURCE_DIR/codex.md"
CLAUDE_OVERLAY_SRC="$SOURCE_DIR/claude.md"
SKILLS_SRC="$SOURCE_DIR/skills"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [[ $# -gt 0 ]]; then
    echo "setup.sh takes no arguments and always installs both Claude + Codex."
    exit 1
fi

if [[ ! -f "$COMMON_SRC" ]]; then
    echo "Missing source file: $COMMON_SRC" >&2
    exit 1
fi

if [[ ! -f "$CODEX_SRC" ]]; then
    echo "Missing source file: $CODEX_SRC" >&2
    exit 1
fi

if [[ ! -f "$CLAUDE_OVERLAY_SRC" ]]; then
    echo "Missing source file: $CLAUDE_OVERLAY_SRC" >&2
    exit 1
fi

if [[ ! -d "$SKILLS_SRC" ]]; then
    echo "Missing skills directory: $SKILLS_SRC" >&2
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

render_instruction() {
    local common_src="$1"
    local overlay_src="$2"
    local dest="$3"
    local backup_dir="$4"

    if [[ ! -e "$common_src" ]]; then
        echo "Source not found: $common_src" >&2
        return 1
    fi

    if [[ ! -e "$overlay_src" ]]; then
        echo "Source not found: $overlay_src" >&2
        return 1
    fi

    backup_if_needed "$dest" "$backup_dir"
    mkdir -p "$(dirname "$dest")"
    cat "$common_src" > "$dest"
    printf '\n\n' >> "$dest"
    cat "$overlay_src" >> "$dest"
    echo "Rendered $dest from $common_src + $overlay_src"
}

install_agent() {
    local label="$1"
    local target_dir="$2"
    local overlay_src="$3"
    local backup_dir="$HOME/.${label}-backup-${TIMESTAMP}"

    echo ""
    echo "Setting up ${label} config..."
    echo "-----------------------------"
    mkdir -p "$target_dir"

    render_instruction "$COMMON_SRC" "$overlay_src" "$target_dir/CLAUDE.md" "$backup_dir"
    mkdir -p "$target_dir/skills"

    for skill_dir in "$SKILLS_SRC"/*; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name
            skill_name="$(basename "$skill_dir")"
            create_link "$skill_dir" "$target_dir/skills/$skill_name" "$backup_dir"
        fi
    done

    echo ""
    echo "Installed in $target_dir:"
    echo "  CLAUDE.md"
    for skill_dir in "$SKILLS_SRC"/*; do
        if [[ -d "$skill_dir" ]]; then
            echo "  skills/$(basename "$skill_dir")"
        fi
    done

    if [[ -d "$backup_dir" ]]; then
        echo ""
        echo "Backed up previous ${label} files to: $backup_dir"
    fi
}

echo "Agent config setup"
echo "=================="
echo "Source: $SOURCE_DIR"

install_agent "claude" "$HOME/.claude" "$CLAUDE_OVERLAY_SRC"
install_agent "codex" "${CODEX_HOME:-$HOME/.codex}" "$CODEX_SRC"

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
backup_if_needed "$CODEX_DIR/AGENTS.md" "$HOME/.codex-backup-${TIMESTAMP}"
ln -sfn "$CODEX_DIR/CLAUDE.md" "$CODEX_DIR/AGENTS.md"
echo "Linked $CODEX_DIR/AGENTS.md -> $CODEX_DIR/CLAUDE.md"

echo ""
echo "Setup complete."

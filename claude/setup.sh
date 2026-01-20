#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_DIR="$HOME/.claude-backup-$(date +%Y%m%d-%H%M%S)"

echo "Claude Code config setup"
echo "========================"
echo "Source: $SCRIPT_DIR"
echo "Target: $CLAUDE_DIR"
echo ""

# Backup existing config if it exists and isn't already a symlink to us
backup_if_needed() {
    local target="$1"
    if [[ -e "$target" && ! -L "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        echo "Backing up $target to $BACKUP_DIR/"
        mv "$target" "$BACKUP_DIR/"
    elif [[ -L "$target" ]]; then
        # Remove existing symlink
        rm "$target"
    fi
}

# Create symlink
create_link() {
    local src="$1"
    local dest="$2"
    if [[ -e "$src" ]]; then
        backup_if_needed "$dest"
        ln -sf "$src" "$dest"
        echo "Linked $dest -> $src"
    else
        echo "Source not found: $src"
    fi
}

# Ensure directory exists
mkdir -p "$CLAUDE_DIR"

echo "Setting up user config..."
echo "-------------------------"
create_link "$SCRIPT_DIR/user/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

echo ""
echo "Setup complete!"
echo ""
echo "User config installed:"
echo "  ~/.claude/CLAUDE.md"
echo ""
echo "To install team plugin, run in Claude Code:"
echo "  /plugin marketplace add https://github.com/ishandhanani/dynamo-claude-plugin"
echo "  /plugin install dynamo@dynamo-dev"
echo ""
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Previous config backed up to: $BACKUP_DIR"
fi

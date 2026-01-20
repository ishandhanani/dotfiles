#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
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

# Ensure directories exist
mkdir -p "$CLAUDE_DIR"
mkdir -p "$PLUGINS_DIR"

echo "Setting up user config..."
echo "-------------------------"
# User-level config (CLAUDE.md, settings.json)
create_link "$SCRIPT_DIR/user/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
create_link "$SCRIPT_DIR/user/settings.json" "$CLAUDE_DIR/settings.json"

echo ""
echo "Setting up plugin..."
echo "--------------------"
# Plugin (symlink for development - changes reflect immediately)
create_link "$SCRIPT_DIR/plugin" "$PLUGINS_DIR/workflow-tools"

echo ""
echo "Setup complete!"
echo ""
echo "User config:"
echo "  ~/.claude/CLAUDE.md"
echo "  ~/.claude/settings.json"
echo ""
echo "Plugin installed:"
echo "  ~/.claude/plugins/workflow-tools"
echo ""
echo "Commands available:"
echo "  /workflow-tools:commit"
echo "  /workflow-tools:pr-create"
echo "  /workflow-tools:debug-session"
echo ""
echo "Skills available:"
echo "  spec-refine (auto-activates on spec discussions)"
echo "  spec-to-tasks (auto-activates on task breakdown)"
echo ""
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Previous config backed up to: $BACKUP_DIR"
fi

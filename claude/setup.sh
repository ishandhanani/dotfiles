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
echo "Setting up personal skills..."
echo "------------------------------"
SKILLS_SRC="$SCRIPT_DIR/user/skills"
SKILLS_DEST="$CLAUDE_DIR/skills"
mkdir -p "$SKILLS_DEST"

if [[ -d "$SKILLS_SRC" ]]; then
    for skill_dir in "$SKILLS_SRC"/*/; do
        if [[ -d "$skill_dir" ]]; then
            skill_name="$(basename "$skill_dir")"
            create_link "$skill_dir" "$SKILLS_DEST/$skill_name"
        fi
    done
else
    echo "No skills directory found at $SKILLS_SRC"
fi

echo ""
echo "Setup complete!"
echo ""
echo "User config installed:"
echo "  ~/.claude/CLAUDE.md"
echo ""
echo "Skills installed:"
if [[ -d "$SKILLS_DEST" ]]; then
    for link in "$SKILLS_DEST"/*/; do
        if [[ -d "$link" ]]; then
            echo "  ~/.claude/skills/$(basename "$link")"
        fi
    done
fi
echo ""
echo "Plugin setup"
echo "------------"
echo "The following plugins need to be installed inside Claude Code (interactive commands)."
echo ""

read -p "Install dynamo-claude-plugin globally? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "  Run these in Claude Code:"
    echo "    /plugin marketplace add https://github.com/ishandhanani/dynamo-claude-plugin"
    echo "    /plugin install dynamo@dynamo-dev"
    echo ""
fi

read -p "Install last30days-skill? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "  Run these in Claude Code:"
    echo "    /plugin marketplace add https://github.com/mvanhorn/last30days-skill"
    echo "    /plugin install last30days@last30days-skill"
    echo ""
fi

if [[ -d "$BACKUP_DIR" ]]; then
    echo "Previous config backed up to: $BACKUP_DIR"
fi

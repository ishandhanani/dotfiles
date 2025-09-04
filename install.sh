#!/bin/bash

# Simple install script - just symlink everything

echo "Installing dotfiles..."

# Create symlinks
ln -sf $(pwd)/zsh/.zshrc ~/.zshrc
ln -sf $(pwd)/bash/.bashrc ~/.bashrc
ln -sf $(pwd)/vim/.vimrc ~/.vimrc
ln -sf $(pwd)/git/.gitconfig ~/.gitconfig

# Copy SSH keys if they exist
if [ -d "ssh" ] && [ "$(ls -A ssh)" ]; then
    mkdir -p ~/.ssh
    cp -r ssh/* ~/.ssh/
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/*
fi

echo "Done! Reload your shell."
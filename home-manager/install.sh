#!/bin/bash

# Home Manager Installation Script
# This script sets up Nix and Home Manager on a fresh system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "darwin"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
ARCH=$(uname -m)

echo "========================================="
echo "   Home Manager Installation Script"
echo "========================================="
echo ""
print_step "Detected OS: $OS ($ARCH)"
echo ""

# Check if Nix is installed
if ! command -v nix &> /dev/null; then
    print_step "Nix is not installed. Installing with the Determinate installer..."

    if [[ "$OS" == "darwin" ]] || [[ "$OS" == "linux" ]]; then
        curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
        print_success "Nix installed successfully"
        print_warning "Please restart your terminal and run this script again"
        exit 0
    else
        print_error "Unsupported OS for automatic Nix installation"
        exit 1
    fi
else
    print_success "Nix is already installed (Determinate enables flakes by default)"
fi

# Determine the correct flake target by matching the current user/OS/arch
# to a homeConfigurations output defined in flake.nix.
print_step "Determining flake target..."
USERNAME=$(whoami)
case "$OS:$ARCH:$USERNAME" in
    darwin:*:idhanani)         FLAKE_TARGET="work" ;;
    darwin:*:ishandhanani)     FLAKE_TARGET="home" ;;
    linux:aarch64:ubuntu)      FLAKE_TARGET="brev-vm-arm" ;;
    linux:*:ubuntu)            FLAKE_TARGET="brev-vm" ;;
    linux:*:nvidia)            FLAKE_TARGET="brev-vm-gpu" ;;
    linux:*:ishan)             FLAKE_TARGET="simbox" ;;
    *)
        print_error "No flake target known for $OS/$ARCH/$USERNAME. Edit install.sh or flake.nix."
        exit 1
        ;;
esac
print_success "Using flake target: $FLAKE_TARGET"

# Check if configuration files need updating
print_step "Checking configuration files..."
print_warning "Please ensure you've updated the following:"
echo "  1. home.nix - username and home directory"
echo "  2. modules/git.nix - git userName and userEmail"
echo ""
read -p "Have you updated these files? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Please update the configuration files first"
    echo "  vim home.nix"
    echo "  vim modules/git.nix"
    exit 1
fi

# Build the configuration first (without switching)
print_step "Building configuration..."
if nix build .#homeConfigurations.$FLAKE_TARGET.activationPackage --no-link --show-trace; then
    print_success "Configuration builds successfully"
else
    print_error "Failed to build configuration"
    exit 1
fi

# Backup existing files
print_step "Backing up existing dotfiles..."
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for file in .zshrc .bashrc .vimrc .gitconfig .tmux.conf; do
    if [[ -f "$HOME/$file" ]]; then
        cp "$HOME/$file" "$BACKUP_DIR/"
        print_success "Backed up $file"
    fi
done

# Apply the configuration
print_step "Applying Home Manager configuration..."
# Instead of installing home-manager globally, just use your flake
nix run home-manager/master -- switch --flake ".#${FLAKE_TARGET}" -b backup

if [[ $? -eq 0 ]]; then
    print_success "Home Manager configuration applied successfully!"
    echo ""
    echo "========================================="
    echo "          Installation Complete!"
    echo "========================================="
    echo ""
    print_step "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.zshrc"
    echo "  2. Run 'rebuild' to apply future changes"
    echo "  3. Run 'edit-home' to modify configuration"
    echo ""
    print_step "Your old dotfiles are backed up in:"
    echo "  $BACKUP_DIR"
    echo ""
    print_success "Enjoy your new declarative configuration!"
else
    print_error "Failed to apply configuration"
    echo "Check the error messages above and try again"
    exit 1
fi
# Dotfiles Makefile
# Commands to manage Nix configuration and Claude Code setup

.PHONY: help install work home vm vm-arm clean backup check claude

# Colors
GREEN := \033[0;32m
BLUE := \033[0;34m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# Variables
OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m)
USERNAME := $(shell whoami)
BACKUP_DIR := $(HOME)/.dotfiles-backup-$(shell date +%Y%m%d-%H%M%S)

help: ## Show this help message
	@echo "$(BLUE)Home Manager Makefile$(NC)"
	@echo "====================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-12s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)First time setup:$(NC)"
	@echo "  1. Run 'make install' to install Nix"
	@echo "  2. Restart your terminal"
	@echo "  3. Run 'make work', 'make home', or 'make vm'"

install: ## Install Nix using official installer
	@echo "$(BLUE)==> Installing Nix with official installer...$(NC)"
	@if ! command -v nix &> /dev/null; then \
		echo "$(YELLOW)Installing Nix for $(OS) ($(ARCH))...$(NC)"; \
		curl -L https://nixos.org/nix/install | sh -s -- --daemon; \
		echo "$(GREEN)✓ Nix installed successfully$(NC)"; \
		echo "$(YELLOW)! Please restart your terminal and run 'make work/home/vm'$(NC)"; \
	else \
		echo "$(GREEN)✓ Nix is already installed$(NC)"; \
	fi
	@echo "$(BLUE)==> Enabling flakes...$(NC)"
	@sudo mkdir -p /etc/nix
	@if ! grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null; then \
		echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf > /dev/null; \
		echo "$(GREEN)✓ Flakes enabled system-wide$(NC)"; \
	else \
		echo "$(GREEN)✓ Flakes already enabled system-wide$(NC)"; \
	fi
	@if [ "$(OS)" = "darwin" ]; then \
		sudo launchctl kickstart -k system/org.nixos.nix-daemon; \
	fi

check: ## Check if configuration builds without applying
	@echo "$(BLUE)==> Checking configuration...$(NC)"
	@cd home-manager && nix flake check --show-trace
	@echo "$(GREEN)✓ Configuration check passed$(NC)"

backup: ## Backup existing dotfiles
	@echo "$(BLUE)==> Backing up existing dotfiles...$(NC)"
	@mkdir -p "$(BACKUP_DIR)"
	@for file in .zshrc .bashrc .vimrc .gitconfig .tmux.conf; do \
		if [ -f "$(HOME)/$$file" ]; then \
			cp "$(HOME)/$$file" "$(BACKUP_DIR)/"; \
			echo "$(GREEN)✓ Backed up $$file$(NC)"; \
		fi; \
	done
	@echo "$(YELLOW)Backup location: $(BACKUP_DIR)$(NC)"

work: backup check ## Apply work configuration (idhanani@macbook)
	@echo "$(BLUE)==> Applying work configuration...$(NC)"
	@nix run home-manager/master -- switch --flake ./home-manager#work -b backup
	@echo "$(GREEN)✓ Work configuration applied successfully!$(NC)"
	@echo "$(YELLOW)Run 'source ~/.zshrc' or restart your terminal$(NC)"

home: backup check ## Apply home configuration (ishandhanani@macbook)
	@echo "$(BLUE)==> Applying home configuration...$(NC)"
	@nix run home-manager/master -- switch --flake ./home-manager#home -b backup
	@echo "$(GREEN)✓ Home configuration applied successfully!$(NC)"
	@echo "$(YELLOW)Run 'source ~/.zshrc' or restart your terminal$(NC)"

vm: backup check ## Apply VM configuration (ubuntu@linux x86_64)
	@echo "$(BLUE)==> Applying VM configuration...$(NC)"
	@nix run home-manager/master -- switch --flake ./home-manager#brev-vm -b backup
	@echo "$(GREEN)✓ VM configuration applied successfully!$(NC)"
	@echo "$(YELLOW)Run 'source ~/.zshrc' or restart your terminal$(NC)"

vm-arm: backup check ## Apply VM configuration (ubuntu@linux aarch64)
	@echo "$(BLUE)==> Applying ARM VM configuration...$(NC)"
	@nix run home-manager/master -- switch --flake ./home-manager#brev-vm-arm -b backup
	@echo "$(GREEN)✓ ARM VM configuration applied successfully!$(NC)"
	@echo "$(YELLOW)Run 'source ~/.zshrc' or restart your terminal$(NC)"

rebuild: check ## Quick rebuild current configuration
	@echo "$(BLUE)==> Rebuilding current configuration...$(NC)"
	@echo "$(YELLOW)Please specify which config to rebuild:$(NC)"
	@echo "  make work   - for work config"
	@echo "  make home   - for home config"  
	@echo "  make vm     - for VM config"

clean: ## Clean up Nix store and old generations
	@echo "$(BLUE)==> Cleaning up...$(NC)"
	@nix-collect-garbage -d
	@home-manager expire-generations "-30 days"
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

update: ## Update flake inputs
	@echo "$(BLUE)==> Updating flake inputs...$(NC)"
	@cd home-manager && nix flake update
	@echo "$(GREEN)✓ Flake inputs updated$(NC)"

generations: ## Show home-manager generations
	@echo "$(BLUE)==> Home Manager generations:$(NC)"
	@home-manager generations

rollback: ## Rollback to previous generation
	@echo "$(BLUE)==> Rolling back to previous generation...$(NC)"
	@home-manager rollback
	@echo "$(GREEN)✓ Rolled back successfully$(NC)"

claude: ## Setup Claude Code configuration (symlinks to ~/.claude/)
	@echo "$(BLUE)==> Setting up Claude Code configuration...$(NC)"
	@./claude/setup.sh
	@echo "$(GREEN)✓ Claude Code configuration applied$(NC)"

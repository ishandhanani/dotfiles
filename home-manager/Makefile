.DEFAULT_GOAL := help
CONFIG_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
.PHONY: help install setup-macos apply check status update

help: ## Show available commands
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  %-14s %s\n", $$1, $$2 }' "$(CONFIG_DIR)Makefile"

install: ## Install Nix if missing
	@"$(CONFIG_DIR)install.sh"

setup-macos: ## Apply macOS settings and install missing GUI apps
	@"$(CONFIG_DIR)scripts/manage.sh" setup-macos

apply: ## Apply dotfiles and install missing CLI tools
	@"$(CONFIG_DIR)scripts/manage.sh" apply

check: ## Build the local configurations without applying
	@"$(CONFIG_DIR)scripts/manage.sh" check

status: ## Check macOS settings, app configs, and installed GUI apps
	@"$(CONFIG_DIR)scripts/check-macos-settings.sh"

update: ## Update locked Nix dependencies
	@cd "$(CONFIG_DIR)" && nix flake update

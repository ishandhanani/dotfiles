# CLAUDE.md - Dotfiles Reference for AI Assistants

This document explains the Nix design decisions and agent-specific features in this dotfiles repository.

## Repository Overview

**Type:** Home Manager flake-based configuration  
**Owner:** Ishan Dhanani  
**Platforms:** macOS (aarch64-darwin), Linux (x86_64-linux, aarch64-linux)  
**Design:** Single shared module set with platform conditionals

## Nix Design Decisions

### 1. Flake Structure: One Module Set, Multiple Configs

**Decision:** All 5 configurations (`home`, `work`, `brev-vm`, `simbox`, `brev-vm-arm`) share the same `home.nix` and module files.

**Why:** 
- Single source of truth for configuration
- Changes propagate to all environments automatically
- Platform differences handled via conditionals (`pkgs.stdenv.isDarwin`, `pkgs.stdenv.isLinux`)

**Implementation:**
```nix
# flake.nix:28-40
extraSpecialArgs = {
  user = "ishandhanani";  # or "idhanani", "ubuntu", "ishan"
  homeDirectory = "/Users/ishandhanani";  # or "/home/ubuntu", etc.
};
```

User-specific values (username, home directory) are passed via `extraSpecialArgs`, allowing the same modules to work across different users/machines.

### 2. Modular Architecture

**Decision:** Each tool/service has its own module file in `modules/`.

**Why:**
- Clear separation of concerns
- Easy to enable/disable entire features
- Platform-specific logic isolated per module

**Modules:**
- `vim.nix` - Editor configuration with ALE linting
- `git.nix` - Git with SSH signing and delta
- `zsh.nix` / `bash.nix` - Shell configs (mirror each other)
- `ssh.nix` - SSH config with platform-specific key management
- `uvx.nix` - UV tool installer with conditional installation

### 3. Platform Conditionals

**Decision:** Use `lib.mkIf pkgs.stdenv.isDarwin` / `lib.mkIf pkgs.stdenv.isLinux` for platform-specific code.

**Examples:**

**SSH Key Management (ssh.nix:34-52):**
- macOS: Uses `--apple-use-keychain` flag, checks keychain before adding
- Linux: Uses `ssh-agent` service, checks agent before adding
- Both: Only add if not already present (prevents redundant prompts)

**Font Configuration (home.nix:69):**
- Linux: `fonts.fontconfig.enable = true` (needed for font rendering)
- macOS: Not needed (handled by system)

**SSH Agent Service (ssh.nix:31):**
- Linux: `services.ssh-agent.enable = true` (systemd service)
- macOS: Not needed (uses keychain)

### 4. Activation Scripts

**Decision:** Use `home.activation.*` for one-time setup tasks that run on `home-manager switch`.

**Why:**
- Runs before/after configuration changes
- Can check state before acting (e.g., "is key already in agent?")
- Platform-specific shell scripts

**Current Activations:**
- `sshAddKey` (macOS) - Adds SSH key to keychain if not present
- `sshAddKeyLinux` (Linux) - Adds SSH key to agent if not present
- `installUvTools` (uvx.nix) - Installs UV tools if not already installed

**Pattern:** Always check state first, then act conditionally. Prevents redundant operations and prompts.

### 5. Lazy Loading for Performance

**Decision:** AI functions (125 lines) are lazy-loaded instead of sourced at shell startup.

**Why:**
- Faster shell startup (50-100ms improvement)
- Functions only load when first used
- Reduces initial shell memory footprint

**Implementation (zsh.nix:102-119):**
```nix
_load_ai_functions() {
  if [ "$_ai_functions_loaded" -eq 0 ]; then
    source ${../functions/ai-functions.sh}
    _ai_functions_loaded=1
  fi
}

gcai() {
  _load_ai_functions
  git_ai_commit "$@"
}
```

Wrappers check a flag, source the functions once, then delegate to the real function.

### 6. Conditional Tool Installation

**Decision:** UV tools check if already installed before attempting installation.

**Why:**
- Faster `home-manager switch` (no network requests if already present)
- Prevents unnecessary reinstalls
- Reduces activation time

**Implementation (uvx.nix:15-22):**
```nix
home.activation.installUvTools = ''
  if ! uv tool list | grep -q "y-cli"; then
    uv tool install y-cli
  fi
  # ... similar check for llm
'';
```

### 7. PATH Consolidation

**Decision:** PATH additions only in `home.nix` via `sessionPath`, not in shell init scripts.

**Why:**
- Single source of truth
- Works across all shells (zsh, bash)
- Cleaner module separation

**Implementation (home.nix:23-26):**
```nix
sessionPath = [
  "$HOME/.local/bin"
  "$HOME/go/bin"
];
```

## Agent-Specific Features

### AI-Powered Git Functions

**Location:** `functions/ai-functions.sh` (lazy-loaded via zsh.nix)

**Functions:**

1. **`gcai` (git_ai_commit)**
   - Generates semantic commit messages for staged changes
   - Uses `llm` CLI tool with Claude 4o model
   - Format: `type(scope): description`
   - Commits immediately after generation

2. **`gprai` (PR generator)**
   - Generates PR title and description from branch diff
   - Compares current branch against `origin/main` or `origin/master`
   - Uses `llm` CLI tool with Claude 4o model
   - Optional: Creates PR via `gh` CLI if confirmed

**Dependencies:**
- `llm` - Installed via UV tools (uvx.nix)
- `gh` - Installed as Nix package (home.nix)

**Lazy Loading:**
- Functions defined in separate shell script (complex syntax)
- Wrapped in zsh.nix with lazy-loading pattern
- First use triggers source, subsequent uses are direct

**Usage:**
```bash
git add .
gcai          # Generates and commits with AI message

gprai         # Generates PR title/description, optionally creates PR
```

### UV Tools Integration

**Location:** `modules/uvx.nix`

**Purpose:** Installs Python CLI tools via `uv tool install` (not Nix packages).

**Why UV tools instead of Nix:**
- Tools update independently of Nix
- Faster iteration for development tools
- Some tools aren't in nixpkgs

**Tools Installed:**
- `llm` - Simon Willison's LLM CLI (used by AI functions)
- `y-cli` - Y CLI tool

**Design:** Conditional installation prevents reinstalls on every `home-manager switch`.

## Key Files Reference

**Core Configuration:**
- `flake.nix` - Flake definition, 5 homeConfigurations sharing modules
- `home.nix` - Main config, imports all modules, defines packages

**Modules:**
- `modules/ssh.nix` - SSH config with platform-specific key management
- `modules/zsh.nix` - Zsh with lazy-loaded AI functions
- `modules/uvx.nix` - UV tool installer with conditional checks
- `modules/vim.nix` - Vim with ALE linting (optimized debounce)
- `modules/git.nix` - Git with SSH signing

**Agent Functions:**
- `functions/ai-functions.sh` - AI-powered git commands (lazy-loaded)

## Platform Detection Pattern

Throughout the config, platform detection follows this pattern:

```nix
let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  # Conditional feature
  someFeature.enable = isDarwin;
  
  # Conditional activation script
  home.activation.someScript = lib.mkIf isDarwin ''
    # macOS-specific code
  '';
  
  # Conditional config value
  someConfig = lib.optionalString isDarwin "macOS value";
}
```

This allows the same module to work on both platforms with appropriate differences.

## Performance Optimizations

**Applied optimizations (design decisions, not hacks):**

1. **Vim ALE:** Reduced lint frequency (`lint_on_text_changed = 'normal'`, `lint_delay = 300ms`)
2. **Shell startup:** Lazy-load AI functions (50-100ms faster)
3. **Activation scripts:** Check state before acting (prevents redundant operations)
4. **Starship:** Minimal module set, fast timeout (100ms), no Python execution
5. **PATH:** Single source of truth (cleaner, faster)

These are architectural decisions to keep the config fast and responsive, not workarounds.

---

**Last Updated:** 2026-01-19

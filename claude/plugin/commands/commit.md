---
name: commit
description: Stage and commit changes with standardized format
---

# Standardized Commit

$GIT_STATUS
```bash
git status --short
```

$GIT_DIFF
```bash
git diff --stat
```

$STAGED_DIFF
```bash
git diff --cached --stat
```

## Instructions

Based on the git status and diff above:

1. **Stage changes** if not already staged:
   - Stage relevant files (use judgment on what belongs together)
   - Don't stage unrelated changes

2. **Write commit message** in this format:
   ```
   <type>: <description>
   ```

   **Types**:
   - `fix`: Bug fix
   - `feat`: New feature
   - `refactor`: Code restructuring (no behavior change)
   - `docs`: Documentation only
   - `test`: Adding/updating tests
   - `chore`: Build, config, tooling changes

   **Rules**:
   - Description is lowercase, no period
   - Keep under 72 characters
   - Be specific (not "fix bug" but "fix null pointer in request handler")

3. **Commit** without asking for confirmation

## Examples

Good:
- `fix: handle empty response in sglang backend`
- `feat: add per-user rate limiting middleware`
- `refactor: extract token validation to separate module`

Bad:
- `Fix bug` (too vague)
- `Updated code` (meaningless)
- `WIP` (not a complete commit)

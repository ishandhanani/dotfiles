---
name: pr-create
description: Create a PR with standardized team format
---

# Create Pull Request

$BRANCH
```bash
git branch --show-current
```

$BASE_BRANCH
```bash
git remote show origin | grep 'HEAD branch' | cut -d' ' -f5
```

$COMMITS
```bash
git log --oneline $(git merge-base HEAD origin/$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5))..HEAD
```

$DIFF_STAT
```bash
git diff --stat origin/$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)...HEAD
```

## Instructions

Based on the branch and commits above:

1. **Push** if not already pushed:
   - `git push -u origin $BRANCH` if no upstream
   - `git push` otherwise

2. **Create PR** using `gh pr create` with this format:

**Title**:
- If single commit: use the commit message
- If multiple commits: summarize the change concisely

**Body** (use exactly this template):
```
## Summary
- [Bullet point 1: what changed]
- [Bullet point 2: if needed]

## Context
[Why this change was needed]

[Linear ticket link if found in branch name or commits, e.g., "Closes LIN-123"]

## Testing
- [ ] [Step to verify the change works]
- [ ] [Another verification step if needed]

## Checklist
- [ ] Tests pass
- [ ] No performance regression
- [ ] Code follows project conventions
```

3. **Execute** without asking for confirmation

4. **Output** the PR URL when done

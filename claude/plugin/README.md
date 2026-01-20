# workflow-tools

A Claude Code plugin for standardized development workflows with Linear integration.

## Installation

### Add the marketplace (one time)

```bash
/plugin marketplace add https://github.com/ishandhanani/dotfiles/tree/main/claude/plugin
```

### Install the plugin

```bash
/plugin install workflow-tools@ishandhanani-dotfiles --scope user
```

### Update to latest version

```bash
/plugin update workflow-tools@ishandhanani-dotfiles
```

## Commands

| Command | Description |
|---------|-------------|
| `/workflow-tools:commit` | Stage and commit with standardized format (`<type>: <description>`) |
| `/workflow-tools:pr-create` | Create PR with team template (Summary, Context, Testing, Checklist) |
| `/workflow-tools:debug-session` | Start debugging session with worklog file |

## Skills (Auto-activate)

| Skill | Triggers when... |
|-------|------------------|
| `spec-refine` | Discussing requirements, specs, or project planning |
| `spec-to-tasks` | Breaking down specs into implementable tasks |

Both skills integrate with **Linear MCP** for issue management.

## Commit Format

```
<type>: <description>
```

**Types:**
- `fix` - Bug fix
- `feat` - New feature
- `refactor` - Code restructuring
- `docs` - Documentation
- `test` - Tests
- `chore` - Build/config

**Examples:**
```
fix: handle empty response in sglang backend
feat: add per-user rate limiting middleware
refactor: extract token validation to separate module
```

## PR Template

```markdown
## Summary
- [What changed]

## Context
[Why this change was needed]
[Linear ticket: LIN-123]

## Testing
- [ ] Verification steps

## Checklist
- [ ] Tests pass
- [ ] No performance regression
- [ ] Code follows project conventions
```

## Spec Workflow

1. **Refine spec**: Discuss requirements, Claude asks clarifying questions
2. **Convert to tasks**: Break spec into Linear tickets with acceptance criteria
3. **Implement**: Each ticket has clear verification steps

## Requirements

- Claude Code CLI
- Linear MCP (for spec-refine and spec-to-tasks skills)
- GitHub CLI (`gh`) for PR creation

## Versioning

This plugin follows semantic versioning. Check releases for changelog.

## License

MIT

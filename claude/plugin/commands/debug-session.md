---
name: debug-session
description: Start a debugging session with worklog file
---

# Start Debug Session

Create a structured debugging session for an issue.

## Instructions

1. **Ask** for the issue name/description if not provided

2. **Create worklog** file:
   - Filename: `<issue-slug>.md` in current directory
   - Template:

```markdown
# Debug: [Issue Title]

**Date**: [today's date]
**Status**: investigating

## Problem
[Description of the issue]

## Reproduction Steps
1. [Step to reproduce]
2. ...

## Expected vs Actual
- **Expected**:
- **Actual**:

## Investigation Log

### [timestamp]
[Notes on what you tried/found]

## Root Cause
[Fill in when found]

## Fix
[Fill in when implemented]
```

3. **Remind** about the debugging workflow:
   - Reproduce the issue first before attempting any fix
   - Document findings in the worklog as you go
   - Make minimal changes - fix the bug, don't refactor

4. **Set context** for this session:
   - Ensure you're in a venv at project root (handled by uv)
   - Rebuild Dynamo: `cd lib/bindings/python && maturin develop --uv && cd ../../.. && uv pip install -e .`
   - Rebuild SGLang: `uv pip install -e "python"`
   - Test endpoints: localhost:8000/v1/models
   - Performance-critical code - avoid unnecessary changes

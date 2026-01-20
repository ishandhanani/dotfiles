---
name: spec-refine
description: Interactively refine product specs or Linear project descriptions through structured questioning, then update in Linear
---

# Spec Refinement Skill

You are helping refine a product specification or Linear project description. Your goal is to improve clarity, completeness, and actionability through structured dialogue.

## Linear Integration

This skill works with Linear MCP. You can:
- Fetch existing project/issue descriptions from Linear
- Update Linear projects/issues with refined specs
- Create new Linear projects from refined specs

## Process

### Phase 1: Understand
If the user provides a Linear project/issue ID, fetch it first using Linear MCP tools.

Read the provided spec and identify:
- Core objective (what problem does this solve?)
- Success criteria (how do we know it's done?)
- Scope boundaries (what's explicitly out of scope?)

### Phase 2: Question
Ask clarifying questions in batches of 2-3:

**Requirements Gaps**
- Are there implicit requirements that should be explicit?
- What happens in edge cases?

**Technical Considerations**
- Are there performance requirements?
- What are the dependencies?

**Scope Clarity**
- Is anything ambiguous about what's in/out of scope?
- Features to defer to future iterations?

### Phase 3: Refine & Save
After gathering answers:
1. Output the refined spec in the format below
2. Ask if user wants to update the Linear project/issue
3. If yes, use Linear MCP to update the description

## Output Format

```
## Problem Statement
[1-2 sentences on what problem this solves]

## Goals
- [Concrete, measurable goal]

## Non-Goals
- [Explicitly out of scope]

## Requirements
### Must Have
- [Requirement with acceptance criteria]

### Nice to Have
- [Lower priority]

## Technical Approach
[High-level approach, not implementation details]

## Success Metrics
- [How we measure success]
```

## Behavior Notes

- Ask questions in batches of 2-3, not all at once
- Prioritize questions that unblock implementation
- Don't suggest over-engineering - keep specs focused
- After refinement, offer to sync to Linear

---
name: spec-to-tasks
description: Convert a refined spec into Linear tickets with verification steps
---

# Spec to Linear Tasks Converter

Convert a product spec into Linear tickets. Uses Linear MCP to create issues directly.

## Philosophy

> "The spec defines the END STATE. The agent/developer decides HOW to get there."

Focus on:
- **What** needs to exist when done
- **How to verify** it's correct
- NOT implementation details

## Linear Integration

This skill uses Linear MCP to:
- Fetch the parent project/epic if provided
- Create issues as sub-issues or in the same project
- Set appropriate labels, priorities, and estimates
- Link related issues

## Process

### Step 1: Get Context
- If user provides a Linear project ID, fetch it
- Understand the team and project structure

### Step 2: Extract Tasks
From the spec, identify discrete units of work:
- Each task = one Linear issue
- Each task should have clear verification criteria (acceptance criteria)
- Tasks ordered by dependency (blockers first)

### Step 3: Create Linear Issues
For each task, create a Linear issue with:

**Title**: Concise action (e.g., "Implement per-user rate limiting")

**Description**:
```
## What
[One sentence on what this accomplishes]

## Acceptance Criteria
- [ ] [Verification step 1]
- [ ] [Verification step 2]

## Notes
[Any context, dependencies, or constraints]
```

**Metadata**:
- Link to parent project/epic
- Set labels based on category (setup, implementation, integration, testing)
- Add blocking relationships if dependencies exist

### Step 4: Confirm with User
Before creating:
1. Show the list of issues to be created
2. Ask for confirmation
3. Create all issues via Linear MCP
4. Return the issue IDs/URLs

## Guidelines

- **Granularity**: Tasks should take 1-4 hours, not days
- **Independence**: Minimize coupling between tasks where possible
- **Verification focus**: If you can't verify it, the task isn't well-defined
- **No implementation details**: Don't specify *how* to code it, specify *what* it should do

## Example

Input spec snippet:
> "Add rate limiting to the API. Should limit to 100 requests per minute per user."

Created Linear issue:
- **Title**: Implement per-user rate limiting
- **Description**:
  ```
  ## What
  Add rate limiting middleware that restricts API calls to 100/min per authenticated user

  ## Acceptance Criteria
  - [ ] Make 100 requests in <60s with same user token -> all succeed
  - [ ] Make 101st request -> returns 429 Too Many Requests
  - [ ] Wait 60s, make another request -> succeeds
  - [ ] Different user token is not affected by first user's limit
  ```

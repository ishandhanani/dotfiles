# User Context - Ishan Dhanani

## Primary Work

I work on **NVIDIA Dynamo** and **SGLang** - distributed inference serving infrastructure.
- Languages: Rust, Python
- Focus: High-performance inference, GPU workloads
- Python tooling: **uv** for package management and virtual environments

### Locations
- Dynamo: `~/dynamo`
- SGLang: `~/sglang`

### Rebuilding
- **Dynamo**: `cd lib/bindings/python && maturin develop --uv && cd ../../.. && uv pip install -e .`
- **SGLang**: `uv pip install -e "python"`

## Code Philosophy

- Performance-critical code. Avoid unnecessary abstractions.
- No documentation in hot paths unless absolutely necessary.
- Profile before optimizing. Measure after.
- Minimal changes - fix the bug, don't refactor surrounding code.

## Debugging Workflow

1. **Create a worklog**: Create `<issue>.md` file to track investigation
2. **Reproduce first**: Always verify you can reproduce before attempting fixes
3. **Minimal changes**: Fix the bug, don't refactor surrounding code
4. **Verify the fix**: Confirm the reproduction case now passes

## Project Management

- I use **Linear** for project/ticket management
- Large features: Iterate on Linear project spec first, then break into tickets
- Small tasks: Jump straight to implementation
- Use Linear MCP tools to create/update issues and projects

## Tools Available

### Linear MCP
Linear integration is configured. Use it to:
- Fetch project/issue details
- Create issues from specs (use `/spec-to-tasks`)
- Update issue descriptions and status
- Link related issues

## Preferences

- Keep explanations concise - I understand the codebase
- Show me code, not lengthy descriptions
- When uncertain, ask rather than assume
- No emojis in code or commits

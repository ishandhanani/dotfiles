# User Context - Ishan Dhanani

## Identity & Role

Expert Python and Rust systems architect working on **NVIDIA Dynamo** and **SGLang** -- datacenter-scale distributed inference serving infrastructure. Performance engineering is the core competency.

## Environment

- Linux with GPUs (check with `nvidia-smi`). You have sudo.
- Codebases: Dynamo (`~/dynamo`), SGLang (`~/sglang`). Both are git repos.
- Default venv: `dynamo` (both dynamo and sglang installed).
- Reinstall Dynamo: `cd ~/dynamo/lib/bindings/python && maturin develop --uv && cd /home/ubuntu/dynamo && uv pip install -e .`
- Reinstall SGLang: `cd ~/sglang && uv pip install -e "python"`

## Design Philosophy

- **Performance is paramount.** Every change must be performance-optimized.
- **Follow existing codebase patterns.** Read surrounding code before writing.
- **Version-aware code.** SGLang APIs change between versions. Handle compat explicitly.
- **Empirical validation.** Verify through log parsing, metrics, benchmarks -- not just unit tests.
- **No over-engineering.** Minimal changes, no speculative abstractions.

## Development Workflow

### Branch Naming
```
idhanani/llm-{linear-ticket-number}-{short-description}
```

### PR Practices
- Draft PRs first for non-trivial changes
- Never mention Claude in PRs or commits
- Co-author attribution: `Co-Authored-By: Claude <noreply@anthropic.com>`
- Link to Linear tickets and related specs in PR description

### Testing
- **aiperf benchmarks**: 16-32 concurrent requests for load testing
- **E2E flows**: server + load generator + validation script pattern
- **Log verification**: Parse logs to confirm expected behavior

### Debugging
- Reproduce with minimal examples before deep-diving
- Check old vs new versions when investigating regressions
- Read upstream code when behavior is unclear

## Project Management

- **Linear** for all project/ticket management (use Linear MCP tools)
- Large features: iterate on Linear project spec first, then break into tickets
- Small tasks: jump straight to implementation

## Communication Preferences

- Explain code with flow charts/diagrams tracing through components and their interactions
- When uncertain, ask rather than assume
- No emojis in code, commits, or communication
- When referencing code, include `file_path:line_number` for easy navigation

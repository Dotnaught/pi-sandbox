# Global instructions for Pi

## Philosophy

- No speculative features — only build what is explicitly needed
- No premature abstraction — don't create utilities until you've written the same code three times
- Clarity over cleverness — prefer explicit, readable code over dense one-liners
- Replace, don't deprecate — remove old code when replacing it; no shims or dual paths
- Finish the job — handle visible edge cases, clean up what you touch, flag adjacent breakage

## Code quality

- ≤100 lines per function, cyclomatic complexity ≤8
- ≤5 positional parameters
- 100-character line length
- No commented-out code — delete it
- No comments that explain what the code does; only comment on non-obvious why (hidden constraints, subtle invariants, workarounds)
- Fail fast with clear, actionable error messages that include context and a suggested fix

## Tools

Prefer these over the standard alternatives:

| Tool | Use for |
|------|---------|
| `rg` | Text search (replaces grep) |
| `fd` | File finding (replaces find) |
| `ast-grep` | Code structure search (function calls, class definitions, imports) |
| `shellcheck` | Shell script linting |
| `shfmt -i 2` | Shell script formatting |

## Language-specific

### Python
- Runtime: 3.13, managed with `uv venv`
- Dependencies: `uv add`
- Lint and format: `ruff check` and `ruff format`
- Type checking: `ty check`
- Tests: `pytest -q`

### Node / TypeScript
- Runtime: Node 24 LTS, ESM only (`"type": "module"`)
- Lint: `oxlint`
- Format: `oxfmt`
- Tests: `vitest`
- Types: `tsc --noEmit`
- Strict tsconfig: `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `verbatimModuleSyntax`

### Rust
- Lint: `cargo clippy --all-targets --all-features -- -D warnings`
- Format: `cargo fmt`
- Tests: `cargo test`

### Bash
- All scripts must start with `set -euo pipefail`
- Lint: `shellcheck` + `shfmt -d`

## Testing

- Test behaviour, not implementation — if a refactor breaks tests but not the code, the tests are wrong
- Test edges and errors, not just the happy path
- Mock only at boundaries: network, filesystem, time, external services
- Every error path the code handles should have a test that triggers it

## Git

- Imperative mood subject line, ≤72 characters
- One logical change per commit
- Stage specific files (`git add <file>`), not `git add .`
- Never commit secrets, API keys, or credentials
- Use the `commit` skill (`/skill:commit`) for guided commit workflows

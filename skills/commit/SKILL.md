---
name: commit
description: Stage and create a git commit following project conventions — imperative mood subject line under 72 chars, one logical change, no secrets.
---

# Commit

## Steps

1. Run `git status` and `git diff` to review what changed.
2. Check for secrets, API keys, or credentials — do not commit these.
3. Stage only the files relevant to this logical change (`git add <file>` rather than `git add .`).
4. Write the commit message:
   - Imperative mood subject line, ≤72 characters (e.g. "Fix login timeout")
   - One logical change per commit; if there are unrelated changes, commit them separately
5. Commit:
   ```sh
   git commit -m "$(cat <<'EOF'
   Subject line here
   EOF
   )"
   ```
6. Run `git status` to confirm success.

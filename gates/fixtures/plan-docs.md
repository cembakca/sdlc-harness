# Plan — Document the deployment runbook

**Blast radius:** docs
**Reversible:** yes — text only.

## Tasks
### 1. Write the runbook
- Files: `docs/RUNBOOK.md` (new)
- Done when: the file exists and the on-call checklist has all six steps.

### 2. Link it from the README
- Files: `README.md`
- Done when: the link resolves in CI's link checker.

## Test strategy
| Level | Tool | What it covers |
|---|---|---|
| lint | markdown link checker | broken links |

## Rollback
`git revert`. No runtime effect whatsoever; no code, config or data is touched.

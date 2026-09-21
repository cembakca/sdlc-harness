# Plan — Rename "workspace" to "project" in the API surface

**Blast radius:** logic
**Reversible:** yes — pure rename.

## Tasks
### 1. Rename the field in the response models
- Files: `server/app/models/project.py`, `server/app/api/projects.py`
- This is the same rename already done for `site` → `url` in commit 4f1a2c3;
  follow that change exactly, including the deprecation alias it added.
- Done when: `server/tests/test_projects_api.py` passes unchanged.

### 2. Update the client types the same way
- Files: `client/src/types/project.ts`
- The sibling file `client/src/types/url.ts` shows the pattern.

## Test strategy
| Level | Tool | What it covers |
|---|---|---|
| unit | pytest + vitest | existing suites, unchanged |

## Rollback
`git revert`. No data, no schema, no behaviour change.

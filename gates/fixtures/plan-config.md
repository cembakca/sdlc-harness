# Plan — Raise the crawl timeout

**Blast radius:** config
**Reversible:** yes — one constant.

## Tasks
### 1. Raise the per-page timeout from 20s to 35s
- Files: `server/app/core/config.py`
- Done when: existing crawler tests still pass with the new default.

## Test strategy
| Level | Tool | What it covers |
|---|---|---|
| unit | pytest | the timeout is read from settings, not hard-coded |

## Rollback
Set the value back. No data touched, no schema change.

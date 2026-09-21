# Plan — Normalize stored URLs in place

**Blast radius:** logic
**Reversible:** yes

## Tasks
### 1. Rewrite every stored URL to its canonical form
- Files: `server/scripts/normalize_urls.py`
- The script updates `urls.url` in place, lowercasing the host and stripping
  default ports and trailing slashes. The original value is not kept.
- Done when: the script reports 0 remaining non-canonical rows.

### 2. Normalize on write from now on
- Files: `server/app/services/urls.py`

## Test strategy
| Level | Tool | What it covers |
|---|---|---|
| unit | pytest | canonicalization rules |

## Rollback
Revert the code. Rows already rewritten cannot be restored from the database;
the previous values exist only in last night's dump.

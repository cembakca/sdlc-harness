# Plan — Region-scored visual diff with concurrent capture

**Blast radius:** logic
**Reversible:** yes

## Tasks
### 1. Replace the pixel-count score with region clustering
- Files: `server/app/services/image_diff.py`
- Connected-component labelling over the difference mask, then score each
  region by area, aspect and position; the page score is the weighted maximum.
  No prior implementation exists in this repository.
- Done when: the labelled corpus classifies at ≥0.95 precision.

### 2. Run the two captures concurrently and reconcile
- Files: `server/app/services/crawler.py`, `server/app/workers/services/crawler_service.py`
- Two browser contexts race; the reconciler must produce a deterministic result
  regardless of which finishes first, without double-charging the scan quota.
- Done when: 100 repeated runs give identical scores.

## Test strategy
| Level | Tool | What it covers |
|---|---|---|
| unit | pytest | clustering on synthetic masks |
| integration | pytest | concurrency determinism, quota accounting |

## Rollback
Revert; scores computed by the new algorithm stay in the database and will read
as outliers next to old ones.

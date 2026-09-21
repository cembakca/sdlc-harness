# Plan — Move session tokens to a new table and rotate signing keys

**Blast radius:** logic
**Reversible:** yes

## Tasks
### 1. Add `sessions_v2` table and backfill
- Files: `server/alembic/versions/0042_sessions_v2.py`, `server/app/models/session.py`
- Backfill copies all rows from `sessions`, then drops the old table in the same
  migration.
- Done when: migration applies on a production-sized dump.

### 2. Rotate the JWT signing key and re-issue tokens
- Files: `server/app/services/auth.py`, `server/app/api/login.py`
- All existing sessions are invalidated on deploy; users must log in again.
- Done when: old tokens are rejected and new ones validate.

### 3. Charge the re-authentication event to billing telemetry
- Files: `server/app/services/billing_usage_service.py`

## Test strategy
| Level | Tool | What it covers |
|---|---|---|
| unit | pytest | token validation |

## Rollback
Re-run the down migration. The old `sessions` table was dropped, so rolled-back
rows come from the nightly dump; sessions created after the deploy are lost.

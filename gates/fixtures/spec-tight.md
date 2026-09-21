# Spec — Rate limit headers on the public API

## Summary
Clients cannot tell how much quota they have left until they get a 429.

## Acceptance criteria (EARS)
1. WHEN a request to any `/api/v1/*` endpoint succeeds THE SYSTEM SHALL return the
   headers `X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Reset`.
2. `X-RateLimit-Reset` SHALL be a Unix timestamp in seconds, UTC.
3. WHEN the caller has exhausted the window THE SYSTEM SHALL respond 429 with
   `Retry-After` set to the whole number of seconds until the window resets.
4. IF the caller is unauthenticated THEN THE SYSTEM SHALL apply the per-IP limit
   of 60 requests per minute and report it in the same three headers.

## Non-functional
- Added latency p95 < 3 ms (headers read from the counter already loaded).

## Out of scope
- Changing any existing limit value.
- Per-endpoint limits; this is per-key only.
- Dashboard or UI surfacing of quota.

## Open questions
None.

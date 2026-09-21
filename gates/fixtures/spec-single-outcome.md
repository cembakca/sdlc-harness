# Spec — Stop scheduling archived clients

## Summary
Archived clients keep consuming scan quota.

## Acceptance criteria (EARS)
1. WHEN a client is archived THE SYSTEM SHALL set `next_scan_at` to null for
   every URL belonging to that client within 60 seconds.
2. WHILE a client is archived THE SYSTEM SHALL exclude its URLs from the
   scheduler query, so no scan is enqueued for them.
3. WHEN an archived client is restored THE SYSTEM SHALL recompute `next_scan_at`
   for its active URLs from their configured frequency.
4. WHEN the scheduler skips an archived client's URL THE SYSTEM SHALL emit one
   `scheduler.skipped_archived` counter increment per skipped URL.

## Out of scope
- Deleting archived clients' evidence.
- Billing changes for archived clients.

## Open questions
None.

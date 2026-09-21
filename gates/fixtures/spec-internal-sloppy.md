# Spec — Retry handling improvements

## Summary
Tasks retry too much and it causes problems in the queue.

## Acceptance criteria
1. The system should stop retrying tasks that clearly will not succeed.
2. Internal counters should be updated appropriately.
3. Dead tasks should be handled gracefully and not block others.
4. The retry logic should be more robust overall.

## Out of scope
- TBD

## Open questions
- How many retries is "too many"?

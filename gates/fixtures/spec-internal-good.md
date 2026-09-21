# Spec — Retry budget per worker task

## Summary
A failing task retries forever and starves the queue.

## Acceptance criteria (EARS)
1. WHEN a task raises a retryable error THE SYSTEM SHALL increment the task
   document's `attempts` field by exactly 1 and SHALL NOT modify `created_at`.
2. WHEN `attempts` transitions to exactly 5 THE SYSTEM SHALL call
   `dead_letter(task_id)` once and SHALL set `status` to `"dead"`.
3. WHILE `status` is `"dead"` THE SYSTEM SHALL make no further `enqueue()` call
   for that task: a sixth failure SHALL produce zero additional calls.
4. WHEN a task succeeds THE SYSTEM SHALL set `attempts` to 0 and leave
   `status` as `"done"`.
5. WHEN the retry path runs THE SYSTEM SHALL leave the task's `priority` field
   unchanged.

## Out of scope
- Per-queue retry budgets.
- Changing the backoff curve.

## Open questions
None.

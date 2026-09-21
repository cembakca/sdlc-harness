# Review — Evidence retention

## Findings
| # | Severity | File:line | Reviewer | Finding | Status |
|---|---|---|---|---|---|
| 1 | low | `services/retention.py:22` | arch | Magic number 90 should be a named constant. | open |

## Spec conformance
The spec asked for a 90-day retention sweep. The change also adds an admin-only
endpoint that permanently deletes a customer's whole archive in one call, plus a
feature flag nobody asked for. Neither appears in the spec or the plan.

## Verdict
No severe findings, but the change does more than was asked.

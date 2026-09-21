# Review — Rate limit headers

## Findings
| # | Severity | File:line | Reviewer | Finding | Status |
|---|---|---|---|---|---|
| 1 | medium | `api/deps.py:140` | sec | The remaining counter is computed before the current request is counted, so a client sees one more than it has. Visible, non-critical. | open |
| 2 | low | `api/deps.py:88` | arch | Header names built by concatenation; a constant would read better. | open |

## Spec conformance
All four acceptance criteria implemented, nothing extra.

## Verdict
No high or critical findings.

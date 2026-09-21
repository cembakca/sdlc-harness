# Review — Evidence share links

## Findings
| # | Severity | File:line | Reviewer | Finding | Status |
|---|---|---|---|---|---|
| 1 | critical | `api/share.py:41` | sec | Share token is `md5(url_id)`; any customer can enumerate another org's evidence archive. | open |
| 2 | high | `services/share.py:77` | sec | Expiry is checked client-side only; an expired link still returns the file. | open |
| 3 | medium | `api/share.py:120` | arch | Share creation is not rate limited. | open |

## Spec conformance
The spec asked for time-limited links. The change also added a public listing
endpoint nobody requested.

## Verdict
Blocking.

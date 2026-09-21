# Spec — Reject uploads over 10 MB

## Summary
The upload endpoint accepts any size and the worker dies on large files.

## Acceptance criteria (EARS)
1. WHEN a request to `POST /api/v1/uploads` declares `Content-Length` greater
   than 10485760 THE SYSTEM SHALL respond 413 and SHALL NOT create a job row.
2. The 413 response body SHALL be `{"code": "upload_too_large", "limit_bytes": 10485760}`.
3. WHEN `Content-Length` is 10485760 or less THE SYSTEM SHALL respond 202 and
   create exactly one job row, as it does today.
4. WHEN a request omits `Content-Length` THE SYSTEM SHALL respond 411.

## Out of scope
- Changing the limit per plan tier.
- Chunked or resumable uploads.

## Open questions
None.

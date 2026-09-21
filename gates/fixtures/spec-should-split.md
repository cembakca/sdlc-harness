# Spec — Agency workspace improvements

## Summary
Agencies asked for several things at once in the last pilot round.

## Acceptance criteria (EARS)
1. WHEN an agency admin opens `/projects` THE SYSTEM SHALL show a per-client
   folder tree instead of the flat list.
2. WHEN a URL is blocked by bot protection THE SYSTEM SHALL email the agency once
   per threshold crossing.
3. WHEN an invoice is generated THE SYSTEM SHALL include a per-client cost
   breakdown as a PDF attachment.
4. WHEN a scan finishes THE SYSTEM SHALL push a Slack message if the workspace
   has a Slack integration.
5. WHEN an admin exports evidence THE SYSTEM SHALL produce a ZIP containing the
   screenshots and an index.csv.
6. WHEN a client is archived THE SYSTEM SHALL stop scheduling its URLs within
   one minute.

## Out of scope
- Mobile app.

## Open questions
None.

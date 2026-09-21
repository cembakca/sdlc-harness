# Spec — Team billing

## Summary
Teams want one invoice per organization instead of per seat.

## Acceptance criteria
1. WHEN an org admin opens billing THE SYSTEM SHALL show a single invoice.
2. Seat changes mid-cycle SHALL be prorated somehow.
3. The system should handle currency correctly.

## Out of scope
- Not decided yet.

## Open questions
- [ ] Which currency does an org with mixed-country members get billed in?
- [ ] Do we prorate on seat removal, or only on addition?
- [ ] What happens to an in-flight invoice when a team downgrades?
- [ ] Is tax handled by us or by the payment provider?

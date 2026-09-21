# Plan — Charge for overage scans

**Blast radius:** logic
**Reversible:** yes

## Tasks
### 1. Meter scans above the plan limit
- Files: `server/app/services/billing_usage_service.py`, `server/app/models/invoice.py`
- Done when: an org over its limit accrues an overage line.

### 2. Push the overage line to Stripe at cycle close
- Files: `server/app/services/stripe_billing_service.py`
- Done when: the invoice in Stripe test mode carries the overage item.

### 3. Show the overage on the billing screen
- Files: `client/src/components/billing/UsageCard.tsx`

## Test strategy
| Level | Tool | What it covers |
|---|---|---|
| unit | pytest | metering arithmetic |

## Rollback
Revert the code; invoices already pushed to Stripe stay pushed and must be
credited manually.

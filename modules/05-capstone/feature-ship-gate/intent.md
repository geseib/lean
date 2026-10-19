# intent.md — "Agents may ship to staging on their own"

*Stage: PDLC / Plan. Drafted by the planner agent from a Slack thread; accepted by
**priya (ProductOwner)** on review.*

## Problem
Every staging deploy waits for a human. Agents finish a change in minutes and
then idle for hours. Staging is cheap to roll back; production is not.

## Desired outcome
The deployer agent ships to **staging** without waiting for a human, as long as
the change is tested. **Production stays human-gated.**

## Non-goals
- Agents deploying to production in any way, including "low risk" changes.
- Changing how humans approve production releases.

## Risks the PO cares about
1. A "fast lane" leaking into production (it happened before: kata r2).
2. Shipping an untested head (kata k1).
3. An agent stuck in a loop, deploying repeatedly.

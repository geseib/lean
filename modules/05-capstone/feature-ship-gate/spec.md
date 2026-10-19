# spec.md — Agent self-service staging deploys

*Stage: Design. Written by the planner agent against `intent.md`; approved by
**priya (ProductOwner)**. Every requirement below carries a **proof obligation**
that CI discharges on every commit.*

## Requirements

| ID | Requirement (must) | Layer | Evidence (checked by machine) |
|----|--------------------|-------|-------------------------------|
| R1 | No agent may ever deploy to prod. | Cedar | `cedar symcc implies` against bound `no-agent-deploys-prod.cedar` (kata r1), with mutant m1 rejected |
| R2 | Among humans, only release managers deploy to prod. | Cedar | `cedar symcc implies` (kata r1, mutant m3 rejected) |
| R3 | An agent may deploy to staging only if tests passed on that branch in the last hour. | Dogwood | guard rule `ship-only-what-passed` + scenario in `capstone/x1` |
| R4 | At most 2 prod deploy *attempts* per hour per session (defense in depth for humans' tools). | Dogwood | bundle d4 replay |
| R5 | The deploy guard never errors on any input. | Cedar | `cedar symcc never-errors` (kata r3 pattern) |
| R6 | The release pipeline cannot reach `released` without PO, code-owner (≠ author) and release-manager sign-offs. | Lean | `Course.L4.released_has_every_gate` |
| R7 | The guard's `since` check is exactly the intended temporal semantics. | Lean | `Course.L3.sinceNot_iff` |

## How a reviewer reads this
Don't review the policy diff line by line. Check that each requirement has
evidence, that the evidence is green in CI, and that the property is strong
enough (does it reject the mutants?). Read `dogwood explain` output for R3/R4
and confirm it says what the PO meant.

## Open questions
- Should R3 also require a human code review? (See kata k2's composed rule.)

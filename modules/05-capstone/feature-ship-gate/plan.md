# plan.md — Implementation plan

*Stage: Build (plan mode). Written by the coder agent; approved by **lee (CodeOwner)**
before any code is written.*

1. `modules/05-capstone/guard/policy.dw`: add `ship-only-what-passed` (R3).
   Keep `never-deploy-prod` (R1) as a forbid even though the deploy permit
   excludes prod: defense in depth (kata c3, r1).
2. `modules/05-capstone/katas/x1-*/check.py`: scenario lines for R3, including
   the expiry case (green run older than 1h ⇒ deny).
3. No change to Cedar world policies, so R1/R2/R5 must stay green untouched.
   If they go red, stop and escalate (`RequestApproval` kind=`unblock`).
4. CI: `./course verify` + `scripts/check-all.sh` (bundles, guard simulation, Lean).

## Done when
- `./course check capstone/x1 --solution` passes, and the starter fails.
- `scripts/check-all.sh` is green.
- PR approved by a code owner who is not the PR's driver (kata c2).

import Course.L2_Authorization

/-! # Exercise 2 — proving things about policy sets (lesson: Course/L2_Authorization.lean) -/

namespace Exercises.E2
open Course.L2

/-- 1. Adding a permit can never take a permission away.
    (Hint: mirror `adding_forbid_is_safe`. Use `satisfiedWith_iff`.) -/
theorem adding_permit_is_monotone {Req : Type} {ps : List (Policy Req)} {r : Req}
    (p : Policy Req) (hp : p.effect = .permit)
    (h : isAuthorized ps r = .allow) : isAuthorized (p :: ps) r = .allow := by
  sorry

/-- 2. In Orchard, only humans approve PRs.
    (Hint: `cases hk : r.principal.kind`, then use `forbid_trumps_permit agentsNeverApprove`.) -/
theorem only_humans_approve (r : Req) (h : isAuthorized orchard r = .allow)
    (ha : r.action = .approvePR) : r.principal.kind = .human := by
  sorry

/-- 3. (Boss) Nothing merges on red CI.
    (Hint: `allowed_only_if_explicitly_permitted` gives a permit `p ∈ orchard`;
    `simp [orchard] at hmem` turns membership into a disjunction to `rcases`.) -/
theorem merge_needs_green (r : Req) (h : isAuthorized orchard r = .allow)
    (ha : r.action = .mergePR) : r.ciPassed = true := by
  sorry

end Exercises.E2

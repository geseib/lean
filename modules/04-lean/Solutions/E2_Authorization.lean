import Course.L2_Authorization

/-! # Exercise 2 — proving things about policy sets (lesson: Course/L2_Authorization.lean) -/

namespace Solutions.E2
open Course.L2

/-- 1. Adding a permit can never take a permission away.
    (Hint: mirror `adding_forbid_is_safe`. Use `satisfiedWith_iff`.) -/
theorem adding_permit_is_monotone {Req : Type} {ps : List (Policy Req)} {r : Req}
    (p : Policy Req) (hp : p.effect = .permit)
    (h : isAuthorized ps r = .allow) : isAuthorized (p :: ps) r = .allow := by
  obtain ⟨q, hq, hqe, hqs⟩ := allowed_only_if_explicitly_permitted h
  have hnf : satisfiedWith .forbid ps r = false := by
    cases hx : satisfiedWith .forbid ps r
    · rfl
    · simp [isAuthorized, hx] at h
  have hperm : satisfiedWith .permit (p :: ps) r = true :=
    satisfiedWith_iff.mpr ⟨q, List.mem_cons_of_mem _ hq, hqe, hqs⟩
  have hforbid : satisfiedWith .forbid (p :: ps) r = false := by
    simp [satisfiedWith, hp] at hnf ⊢
    exact hnf
  simp [isAuthorized, hforbid, hperm]

/-- 2. In Orchard, only humans approve PRs.
    (Hint: `cases hk : r.principal.kind`, then use `forbid_trumps_permit agentsNeverApprove`.) -/
theorem only_humans_approve (r : Req) (h : isAuthorized orchard r = .allow)
    (ha : r.action = .approvePR) : r.principal.kind = .human := by
  cases hk : r.principal.kind with
  | human => rfl
  | agent =>
    have hd := forbid_trumps_permit agentsNeverApprove (by simp [orchard]) rfl
      (by simp [Policy.satisfied, agentsNeverApprove, hk, ha])
    rw [hd] at h
    contradiction

/-- 3. (Boss) Nothing merges on red CI.
    (Hint: `allowed_only_if_explicitly_permitted` gives a permit `p ∈ orchard`;
    `simp [orchard] at hmem` turns membership into a disjunction to `rcases`.) -/
theorem merge_needs_green (r : Req) (h : isAuthorized orchard r = .allow)
    (ha : r.action = .mergePR) : r.ciPassed = true := by
  obtain ⟨p, hmem, _, hs⟩ := allowed_only_if_explicitly_permitted h
  simp only [orchard, List.mem_cons, List.not_mem_nil, or_false] at hmem
  rcases hmem with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp_all [Policy.satisfied, agentsDeployBelowProd, releaseManagersDeploy, codeOwnersApprove,
      mergeOnGreen, agentsNeverApprove, noSelfApproval, agentsNeverDeployProd]

end Solutions.E2

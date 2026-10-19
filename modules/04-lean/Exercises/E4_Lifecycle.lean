import Course.L4_Lifecycle

/-! # Exercise 4 — lifecycle properties (lesson: Course/L4_Lifecycle.lean) -/

namespace Exercises.E4
open Course.L4

/-- 1. The only way into `released` is from `merged`. (Hint: `cases hs` and `simp_all`.) -/
theorem released_comes_from_merged {c d : Change} (hs : Step c d) (hd : d.stage = .released) :
    c.stage = .merged := by
  sorry

/-- 2. Nothing merges without an approved plan. (Hint: `reachable_inv`, then `Inv.plan`.) -/
theorem merged_has_plan {c : Change} (h : Reachable c) (hm : c.stage = .merged) :
    c.planBy.isSome := by
  sorry

/-- 3. No step ever erases who accepted the intent. -/
theorem intent_is_never_erased {c d : Change} (hs : Step c d) (hi : c.intentBy.isSome) :
    d.intentBy.isSome := by
  sorry

end Exercises.E4

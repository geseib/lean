import Course.L1_Basics

/-! # Exercise 1 — warm-up proofs (lesson: Course/L1_Basics.lean) -/

namespace Exercises.E1
open Course.L1

/-- 1. Humans may deploy to every tier. (Hint: `cases t`.) -/
theorem human_may_deploy_anywhere (name : String) (t : Tier) :
    mayDeploy (.human name) t = true := by
  sorry

/-- 2. Counting agents distributes over concatenating two traces. (Hint: induction on `xs`.) -/
theorem countAgents_append (xs ys : List Actor) :
    countAgents (xs ++ ys) = countAgents xs + countAgents ys := by
  sorry

/-- 3. A trace of `n` agent events has `n` agents. (Hint: induction on `n`.) -/
theorem countAgents_replicate (n : Nat) (name : String) :
    countAgents (List.replicate n (.agent name)) = n := by
  sorry

end Exercises.E1

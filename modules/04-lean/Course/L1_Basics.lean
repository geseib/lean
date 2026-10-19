/-
# Lesson 1 — Lean in one sitting, for people who write policies

Lean is two things at once:

* a **programming language**: you write data types and functions, and `#eval` runs them;
* a **proof assistant**: you state theorems about those functions, and Lean's small
  *kernel* checks every proof. A proof that type-checks is correct. No reviewer
  has to trust it, and neither do you.

That second half is why AWS writes the Cedar specification in Lean: the
properties of the authorizer are theorems, checked by machine. See
`github.com/cedar-policy/cedar-spec`. This lesson teaches you enough Lean to
read that work and to write your own.

Open this file in VS Code with the Lean 4 extension. The infoview on the right
shows the proof state after every tactic. Move your cursor through the proofs
and watch it change.
-/

namespace Course.L1

/-! ## 1. Data: the vocabulary of our lifecycle -/

/-- Deployment tiers. `deriving DecidableEq` lets Lean decide `t = .prod` by computation. -/
inductive Tier where
  | dev | staging | prod
  deriving DecidableEq, Repr

/-- Who is acting. In the agentic SDLC both kinds appear in every trace. -/
inductive Actor where
  | agent (name : String)
  | human (name : String)
  deriving DecidableEq, Repr

def Actor.isAgent : Actor → Bool
  | .agent _ => true
  | .human _ => false

/-! ## 2. Functions, and running them -/

/-- A first policy, written as an ordinary function. -/
def mayDeploy (who : Actor) (tier : Tier) : Bool :=
  match who, tier with
  | .agent _, .prod => false
  | .agent _, _     => true
  | .human _, _     => true

#eval mayDeploy (.agent "deployer") .staging   -- true
#eval mayDeploy (.agent "deployer") .prod      -- false

/-! ## 3. Theorems: statements about *all* inputs

Testing checks the inputs you thought of. A theorem covers every input. -/

/-- A concrete fact. `rfl` ("reflexivity") means: compute both sides, they are equal. -/
theorem deployer_cannot_ship_prod : mayDeploy (.agent "deployer") .prod = false := rfl

/-- The same fact for EVERY agent. The name is a variable now, so `rfl` alone
    is not enough: we introduce it and let `simp` unfold the definition. -/
theorem no_agent_ships_prod (name : String) : mayDeploy (.agent name) .prod = false := by
  simp [mayDeploy]

/-- Case analysis: if anyone may deploy to prod, they are a human.
    `cases who` splits the proof into one goal per constructor. -/
theorem prod_means_human (who : Actor) (h : mayDeploy who .prod = true) :
    who.isAgent = false := by
  cases who with
  | agent name => simp [mayDeploy] at h     -- h says false = true: contradiction
  | human name => rfl

/-! ## 4. The logic you need

| you write | it means                | to prove it         | to use it            |
|-----------|-------------------------|---------------------|----------------------|
| `p → q`   | if p then q             | `intro hp`          | apply it to a proof of p |
| `p ∧ q`   | p and q                 | `constructor`, or `⟨hp, hq⟩` | `h.1`, `h.2`, `obtain ⟨hp, hq⟩ := h` |
| `p ∨ q`   | p or q                  | `left` / `right`    | `cases h` / `rcases h with hp \| hq` |
| `¬ p`     | p is impossible         | `intro hp` then derive `False` | apply it to a proof of p |
| `∀ x, p x`| for every x             | `intro x`           | apply it to a value |
| `∃ x, p x`| for some x              | `exact ⟨x, proof⟩`  | `obtain ⟨x, hx⟩ := h` |

Workhorse tactics: `simp` (rewrite and simplify), `decide` (decide a closed
claim by computation), `omega` (linear integer and natural-number arithmetic), and
`induction` (proofs about lists and other recursive data). -/

/-- `decide` settles a closed claim by computation. -/
theorem prod_is_not_staging : Tier.prod ≠ Tier.staging := by
  decide

/-- Quantify over a finite type with `cases`: one goal per tier, each easy. -/
theorem every_tier_but_prod_ok :
    ∀ t : Tier, t ≠ .prod → mayDeploy (.agent "x") t = true := by
  intro t ht
  cases t <;> simp_all [mayDeploy]

/-- `omega` closes linear arithmetic. Budgets and rate limits live here. -/
theorem budget_split (a b limit : Nat) (h₁ : a ≤ limit / 2) (h₂ : b ≤ limit / 2) :
    a + b ≤ limit := by
  omega

/-! ## 5. Lists and induction: traces are lists

An agent's history is a list of events. Most interesting theorems about agents
are theorems about lists, proved by induction: prove it for `[]`, then prove
that if it holds for `xs` it holds for `x :: xs`. -/

/-- How many of the actors in a trace are agents. -/
def countAgents : List Actor → Nat
  | []      => 0
  | a :: as => (if a.isAgent then 1 else 0) + countAgents as

/-- Agents can never outnumber the whole trace. -/
theorem countAgents_le_length (as : List Actor) : countAgents as ≤ as.length := by
  induction as with
  | nil => simp [countAgents]
  | cons a as ih =>
    simp only [countAgents, List.length_cons]
    split <;> omega

end Course.L1

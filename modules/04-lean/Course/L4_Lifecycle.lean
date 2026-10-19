import Course.L3_Temporal

/-!
# Lesson 4 — The whole lifecycle as a state machine, with human gates proved

Lessons 2 and 3 verified single decisions and single runtime rules. Here we
model the **AI-native SDLC** end to end, the stage-by-stage flow of Anthropic's
playbook where every stage commits an artifact the next stage reads:

    intent.md ─▶ spec.md ─▶ plan.md ─▶ build ─▶ review ─▶ merged ─▶ released
     (PO)        (PO)       (code owner) (agent)   (human, ≠ author)   (release mgr)

Agents may move a change forward only where the playbook lets them (build,
rework). Every other arrow needs a human with the right role. We prove that
**every reachable released state carries the full chain of human sign-offs**,
however the agents interleave their steps, retries and rework.

This is the ADLC idea in one theorem: the agent is fast and untrusted; the
*process* is what we verify.
-/

namespace Course.L4

inductive Role where
  | productOwner | codeOwner | releaseManager
  deriving DecidableEq, Repr

structure Actor where
  name    : String
  isAgent : Bool
  roles   : List Role

/-- A human holding role `r`. Agents never qualify, whatever roles they claim. -/
def Actor.isHumanWith (a : Actor) (r : Role) : Prop :=
  a.isAgent = false ∧ r ∈ a.roles

inductive Stage where
  | intent | spec | plan | build | review | merged | released
  deriving DecidableEq, Repr

/-- How far along the pipeline a stage is. -/
def Stage.rank : Stage → Nat
  | .intent => 0 | .spec => 1 | .plan => 2 | .build => 3
  | .review => 4 | .merged => 5 | .released => 6

/-- One change moving through the lifecycle, with its audit trail. -/
structure Change where
  stage           : Stage
  intentBy        : Option String := none   -- product owner who accepted intent.md
  specBy          : Option String := none   -- product owner who approved spec.md
  planBy          : Option String := none   -- code owner who approved plan.md
  author          : Option String := none   -- agent that built it
  reviewer        : Option String := none   -- human who approved the PR
  releasedBy      : Option String := none   -- release manager who shipped it

def start : Change := { stage := .intent }

/-- The lifecycle's transitions, each with its gate. -/
inductive Step : Change → Change → Prop
  | acceptIntent (c : Change) (po : Actor) :
      c.stage = .intent → po.isHumanWith .productOwner →
      Step c { c with stage := .spec, intentBy := some po.name }
  | approveSpec (c : Change) (po : Actor) :
      c.stage = .spec → po.isHumanWith .productOwner →
      Step c { c with stage := .plan, specBy := some po.name }
  | approvePlan (c : Change) (lead : Actor) :
      c.stage = .plan → lead.isHumanWith .codeOwner →
      Step c { c with stage := .build, planBy := some lead.name }
  | build (c : Change) (agent : Actor) :
      c.stage = .build → agent.isAgent = true →
      Step c { c with stage := .review, author := some agent.name }
  | requestChanges (c : Change) (anyone : Actor) :
      c.stage = .review →
      Step c { c with stage := .build }
  | approveReview (c : Change) (lead : Actor) :
      c.stage = .review → lead.isHumanWith .codeOwner → c.author ≠ some lead.name →
      Step c { c with stage := .merged, reviewer := some lead.name }
  | release (c : Change) (rm : Actor) :
      c.stage = .merged → rm.isHumanWith .releaseManager →
      Step c { c with stage := .released, releasedBy := some rm.name }

inductive Reachable : Change → Prop
  | start : Reachable start
  | step {c d : Change} : Reachable c → Step c d → Reachable d

/-- The invariant: how far a change has got determines which sign-offs exist. -/
structure Inv (c : Change) : Prop where
  intent   : c.stage.rank ≥ 1 → c.intentBy.isSome
  spec     : c.stage.rank ≥ 2 → c.specBy.isSome
  plan     : c.stage.rank ≥ 3 → c.planBy.isSome
  authored : c.stage.rank ≥ 4 → c.author.isSome
  reviewed : c.stage.rank ≥ 5 → ∃ rv, c.reviewer = some rv ∧ c.author ≠ some rv
  released : c.stage.rank ≥ 6 → c.releasedBy.isSome

theorem inv_start : Inv start := by
  constructor <;> simp [start, Stage.rank]

theorem inv_step {c d : Change} (hc : Inv c) (hs : Step c d) : Inv d := by
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hc
  cases hs with
  | acceptIntent _ po hst _ =>
    constructor <;> simp_all [Stage.rank]
  | approveSpec _ po hst _ =>
    constructor <;> simp_all [Stage.rank]
  | approvePlan _ lead hst _ =>
    constructor <;> simp_all [Stage.rank]
  | build _ agent hst _ =>
    constructor <;> simp_all [Stage.rank]
  | requestChanges _ _ hst =>
    constructor <;> simp_all [Stage.rank]
  | approveReview _ lead hst _ hne =>
    constructor <;> simp_all [Stage.rank]
  | release _ rm hst _ =>
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> simp_all [Stage.rank]

theorem reachable_inv {c : Change} (h : Reachable c) : Inv c := by
  induction h with
  | start => exact inv_start
  | step _ hs ih => exact inv_step ih hs

/-- **The ADLC theorem.** Every released change carries the whole chain of
    human sign-offs, and its reviewer was not the agent that wrote it. -/
theorem released_has_every_gate {c : Change} (h : Reachable c) (hr : c.stage = .released) :
    c.intentBy.isSome ∧ c.specBy.isSome ∧ c.planBy.isSome ∧
    (∃ rv, c.reviewer = some rv ∧ c.author ≠ some rv) ∧ c.releasedBy.isSome := by
  have inv := reachable_inv h
  have hrank : c.stage.rank = 6 := by simp [hr, Stage.rank]
  exact ⟨inv.intent (by omega), inv.spec (by omega), inv.plan (by omega),
         inv.reviewed (by omega), inv.released (by omega)⟩

end Course.L4

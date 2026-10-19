import Course.L3_Temporal

/-! # Exercise 3 — verify a `formerly within` monitor (lesson: Course/L3_Temporal.lean) -/

namespace Solutions.E3
open Course.L3

/-- Semantics of `formerly within w`: some event in the window satisfies `p`. -/
def FormerlyWithin (w now : Nat) (p : Event → Bool) (h : History) : Prop :=
  ∃ e ∈ h, now ≤ e.time + w ∧ p e = true

/-- The monitor. -/
def formerlyWithin (w now : Nat) (p : Event → Bool) (h : History) : Bool :=
  h.any (fun e => decide (now ≤ e.time + w) && p e)

/-- 1. The monitor is exactly the semantics. (Hint: `simp [List.any_eq_true]`.) -/
theorem formerlyWithin_iff (w now : Nat) (p : Event → Bool) (h : History) :
    formerlyWithin w now p h = true ↔ FormerlyWithin w now p h := by
  simp [formerlyWithin, FormerlyWithin, List.any_eq_true]

def approvedRelease (change : String) (x : Event) : Bool :=
  x.tool == .requestApproval && x.kind == .response && x.ok && x.subject == change

/-- Bundle d2: a deploy needs a human release approval in the last 4 hours. -/
def allowedDeploy (h : History) (e : Event) : Bool :=
  if e.tool == .deploy && e.kind == .request then formerlyWithin 14400 e.time (approvedRelease e.subject) h
  else true

def stepDeploy (h : History) (e : Event) : History := if allowedDeploy h e then e :: h else h

def SafeDeploys : History → Prop
  | []         => True
  | e :: older => SafeDeploys older ∧
      (e.tool = .deploy → e.kind = .request → FormerlyWithin 14400 e.time (approvedRelease e.subject) older)

/-- 2. One enforcement step preserves safety. (Hint: copy `step_safe`.) -/
theorem stepDeploy_safe (h : History) (e : Event) (hs : SafeDeploys h) :
    SafeDeploys (stepDeploy h e) := by
  unfold stepDeploy
  split
  · rename_i ha
    refine ⟨hs, fun ht hk => ?_⟩
    have : formerlyWithin 14400 e.time (approvedRelease e.subject) h = true := by
      simpa [allowedDeploy, ht, hk] using ha
    exact (formerlyWithin_iff _ _ _ _).mp this
  · exact hs

/-- 3. Every enforced execution is safe. (Hint: copy `enforce_safe`.) -/
theorem enforceDeploys_safe (es : List Event) : SafeDeploys (es.foldl stepDeploy []) := by
  suffices ∀ h, SafeDeploys h → SafeDeploys (es.foldl stepDeploy h) from this [] trivial
  induction es with
  | nil => intro h hs; exact hs
  | cons e es ih => intro h hs; exact ih (stepDeploy h e) (stepDeploy_safe h e hs)

end Solutions.E3

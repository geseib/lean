import Course.L2_Authorization

/-!
# Lesson 3 — A verified mini-Dogwood: runtime monitors over traces

Dogwood decides each tool call from the agent's *history*. Its temporal
operators come from Metric First-Order Temporal Logic (MFOTL), and its
reference interpreter is a **runtime monitor**: an algorithm that keeps a
little state and answers "does the policy hold now?" at every event.

Two questions matter for any monitor:

1. **Is the algorithm right?** Does the code compute the logic's meaning?
   Here we prove our monitor for `!bad since good` is *exactly* the formal
   semantics (sound and complete).
2. **Does enforcing it give the safety we wanted?** We prove that any
   execution filtered by the monitor satisfies a declarative safety property,
   whatever the agent tries.

We also prove the AWS post's warning about counting `response` instead of
`request` events by exhibiting a concrete concurrent trace.
-/

namespace Course.L3

/-! ## Events and histories -/

inductive Tool where
  | runTests | pushCommit | merge | requestApproval | deploy
  deriving DecidableEq, Repr

inductive Kind where
  | request | response
  deriving DecidableEq, Repr

structure Event where
  time    : Nat
  tool    : Tool
  kind    : Kind
  subject : String          -- the PR or change the event is about
  ok      : Bool := true    -- for responses: tests passed / human approved
  deriving Repr

/-- A history, **newest event first** (so `e :: h` means "e happened after h"). -/
abbrev History := List Event

/-! ## The `since` operator: semantics vs. monitor

Dogwood's `!bad since within W good` means: there is an anchor event where
`good` held, and `bad` held at no event after it. We drop the window here to
keep the proof short (lesson exercise E3 adds it back for `formerly`). -/

/-- **Semantics** (declarative): the history splits as `newer ++ anchor :: older`,
    the anchor is good, and nothing newer is bad. -/
def SinceNot (bad good : Event → Bool) (h : History) : Prop :=
  ∃ newer anchor older, h = newer ++ anchor :: older ∧ good anchor = true ∧
    ∀ x ∈ newer, bad x = false

/-- **Monitor** (operational): walk back from the newest event. -/
def sinceNot (bad good : Event → Bool) : History → Bool
  | []      => false
  | e :: es => if good e then true else if bad e then false else sinceNot bad good es

/-- The monitor computes exactly the semantics: sound (→) and complete (←). -/
theorem sinceNot_iff (bad good : Event → Bool) (h : History) :
    sinceNot bad good h = true ↔ SinceNot bad good h := by
  induction h with
  | nil => simp [sinceNot, SinceNot]
  | cons e es ih =>
    constructor
    · intro hm
      by_cases hg : good e = true
      · exact ⟨[], e, es, rfl, hg, by simp⟩
      · by_cases hb : bad e = true
        · simp [sinceNot, hg, hb] at hm
        · have hrest : sinceNot bad good es = true := by simpa [sinceNot, hg, hb] using hm
          obtain ⟨newer, anchor, older, hsplit, hgood, hnew⟩ := ih.mp hrest
          refine ⟨e :: newer, anchor, older, by simp [hsplit], hgood, ?_⟩
          intro x hx
          rcases List.mem_cons.mp hx with rfl | hx
          · simpa using hb
          · exact hnew x hx
    · rintro ⟨newer, anchor, older, hsplit, hgood, hnew⟩
      cases newer with
      | nil =>
        simp at hsplit
        obtain ⟨rfl, rfl⟩ := hsplit
        simp [sinceNot, hgood]
      | cons x newer =>
        simp at hsplit
        obtain ⟨rfl, rfl⟩ := hsplit
        have hb : bad e = false := hnew e (by simp)
        by_cases hg : good e = true
        · simp [sinceNot, hg]
        · have : sinceNot bad good (newer ++ anchor :: older) = true :=
            ih.mpr ⟨newer, anchor, older, rfl, hgood, fun y hy => hnew y (by simp [hy])⟩
          simp [sinceNot, hg, hb, this]

/-! ## The merge policy (bundle d1 / kata k1) as a monitor -/

def greenFor (pr : String) (x : Event) : Bool :=
  x.tool == .runTests && x.kind == .response && x.ok && x.subject == pr

/-- k1's lesson: count the push *request*, so an in-flight push taints the head. -/
def pushTo (pr : String) (x : Event) : Bool :=
  x.tool == .pushCommit && x.kind == .request && x.subject == pr

/-- The decision for an incoming event, given the history before it. -/
def allowed (h : History) (e : Event) : Bool :=
  if e.tool == .merge && e.kind == .request then sinceNot (pushTo e.subject) (greenFor e.subject) h
  else true

/-- Enforcement: a denied request never executes, so it never enters the executed trace. -/
def step (h : History) (e : Event) : History :=
  if allowed h e then e :: h else h

def enforce (es : List Event) : History := es.foldl step []

/-- The safety property, stated only with the declarative semantics:
    every executed merge was preceded by green tests on an untouched head. -/
def Safe : History → Prop
  | []          => True
  | e :: older  => Safe older ∧
      (e.tool = .merge → e.kind = .request → SinceNot (pushTo e.subject) (greenFor e.subject) older)

theorem step_safe (h : History) (e : Event) (hs : Safe h) : Safe (step h e) := by
  unfold step
  split
  · rename_i ha
    refine ⟨hs, fun ht hk => ?_⟩
    have : sinceNot (pushTo e.subject) (greenFor e.subject) h = true := by
      simpa [allowed, ht, hk] using ha
    exact (sinceNot_iff _ _ _).mp this
  · exact hs

/-- **Whatever the agent attempts, the executed trace is safe.** -/
theorem enforce_safe (es : List Event) : Safe (enforce es) := by
  suffices ∀ h, Safe h → Safe (es.foldl step h) from this [] trivial
  induction es with
  | nil => intro h hs; exact hs
  | cons e es ih => intro h hs; exact ih (step h e) (step_safe h e hs)

/-! ## Counting: request vs. response (bundle d4, and the AWS post's sum example)

A limit of 2 deploys, enforced two ways. Responses arrive late, so a monitor
that counts *responses* cannot see deploys that are still in flight. -/

def isDeployReq (x : Event) : Bool := x.tool == .deploy && x.kind == .request
def isDeployResp (x : Event) : Bool := x.tool == .deploy && x.kind == .response

def stepBy (counted : Event → Bool) (limit : Nat) (h : History) (e : Event) : History :=
  if isDeployReq e && decide (h.countP counted ≥ limit) then h else e :: h

def enforceBy (counted : Event → Bool) (limit : Nat) (es : List Event) : History :=
  es.foldl (stepBy counted limit) []

/-- Counting requests: the limit holds for every input, however interleaved. -/
theorem request_counting_is_safe (limit : Nat) (es : List Event) :
    (enforceBy isDeployReq limit es).countP isDeployReq ≤ limit := by
  suffices ∀ h : History, h.countP isDeployReq ≤ limit →
      (es.foldl (stepBy isDeployReq limit) h).countP isDeployReq ≤ limit from
    this [] (by simp)
  induction es with
  | nil => intro h hh; exact hh
  | cons e es ih =>
    intro h hh
    apply ih
    unfold stepBy
    by_cases hd : isDeployReq e = true
    · by_cases hlim : h.countP isDeployReq ≥ limit
      · simp [hd, hlim, hh]
      · simp [hd, hlim, List.countP_cons]
        omega
    · simp [hd, List.countP_cons, hh]

/-- Three deploys launched in parallel before any response comes back. -/
def burst : List Event :=
  [⟨0, .deploy, .request, "c1", true⟩, ⟨1, .deploy, .request, "c2", true⟩,
   ⟨2, .deploy, .request, "c3", true⟩, ⟨3, .deploy, .response, "c1", true⟩]

/-- Counting responses lets all three through: the limit of 2 is broken. -/
theorem response_counting_is_unsafe :
    ¬ ∀ es, (enforceBy isDeployResp 2 es).countP isDeployReq ≤ 2 :=
  fun h => absurd (h burst) (by decide)

end Course.L3

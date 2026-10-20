import Course.L2_Authorization

/-!
# Lesson 3 — A verified mini-Dogwood: runtime monitors over traces

Dogwood decides each tool call from the agent's *history*. Its temporal
operators come from Metric First-Order Temporal Logic (MFOTL), and its
reference interpreter is a **runtime monitor**: an algorithm that keeps a
little state and answers "does the policy hold now?" at every event.

Three questions matter for any monitor, and they're easy to blur:

1. **Is the algorithm right?** Does the code compute the logic's meaning?
   We prove our monitor for `!bad since good` is *exactly* its formal
   semantics (sound and complete): `sinceNot_iff`.
2. **Does enforcement deliver the specification?** Every execution filtered
   by the monitor satisfies the temporal-logic spec, whatever the agent tries:
   `enforce_safe`.
3. **Is the specification the property we actually wanted?** Here Lean finds
   a counterexample. The `since` spec is satisfied by a trace that merges an
   untested commit (the "second race" from kata k1's stretch goal), so we
   design a better spec and prove a monitor for it: `enforceSha_merges_tested`.

Questions 1 and 2 are about the *implementation*; question 3 is about the
*requirement*. Proofs settle the first two. Only a property stated
independently of the monitor can expose the third.

We also prove the AWS post's warning about counting `response` instead of
`request` events by exhibiting a concrete concurrent trace.

**A simplification to know about:** in this model a denied request never enters
the history (`step` drops it). Dogwood keeps denied requests as attempts (module
2, bundle d4). For the `since` rule, keeping attempts can only add pushes,
which makes the monitor *more* conservative, so the safety results carry over.
For counting rules the difference matters, and lesson 3's counting section
models it explicitly.
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
  subject : Nat             -- the PR or change the event is about
  ok      : Bool := true    -- for responses: tests passed / human approved
  head    : Nat  := 0       -- the commit the event concerns (pushed, tested or merged)
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

def greenFor (pr : Nat) (x : Event) : Bool :=
  x.tool == .runTests && x.kind == .response && x.ok && x.subject == pr

/-- k1's lesson: count the push *request*, so an in-flight push taints the head. -/
def pushTo (pr : Nat) (x : Event) : Bool :=
  x.tool == .pushCommit && x.kind == .request && x.subject == pr

/-- The decision for an incoming event, given the history before it. -/
def allowed (h : History) (e : Event) : Bool :=
  if e.tool == .merge && e.kind == .request then sinceNot (pushTo e.subject) (greenFor e.subject) h
  else true

/-- Enforcement: a denied request never executes, so it never enters the executed trace. -/
def step (h : History) (e : Event) : History :=
  if allowed h e then e :: h else h

def enforce (es : List Event) : History := es.foldl step []

/-- The specification, stated with the declarative semantics only: every
    executed merge satisfies the MFOTL formula `!push since green`. -/
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

/-- **Whatever the agent attempts, the executed trace meets the specification.** -/
theorem enforce_safe (es : List Event) : Safe (enforce es) := by
  suffices ∀ h, Safe h → Safe (es.foldl step h) from this [] trivial
  induction es with
  | nil => intro h hs; exact hs
  | cons e es ih => intro h hs; exact ih (step h e) (step_safe h e hs)

/-! ## Is the specification the right one?

The `since` spec talks about *when* events happened. What we wanted is about
*which commit* was tested. Let each push carry the commit it pushes, and each
test response the commit it tested. -/

/-- The commit at the tip of `pr` after the executed pushes in `h` (0 initially). -/
def currentHead (pr : Nat) : History → Nat
  | []      => 0
  | e :: es => if e.tool == .pushCommit && e.kind == .request && e.subject == pr then e.head
               else currentHead pr es

/-- Some green run in `h` tested exactly the commit that `pr` points at now. -/
def testedNow (pr : Nat) (h : History) : Bool :=
  h.any (fun t => greenFor pr t && t.head == currentHead pr h)

/-- **The property we actually wanted**, stated independently of any monitor:
    every executed merge merged a commit that a green test run tested. -/
def mergesTested : History → Bool
  | []          => true
  | e :: older  => mergesTested older &&
      (!(e.tool == .merge && e.kind == .request) || testedNow e.subject older)

/-- The second race: a push lands while the tests run on the previous commit. -/
def secondRace : List Event :=
  [ { time := 0,   tool := .runTests,   kind := .request,  subject := 42, head := 1 },
    { time := 100, tool := .pushCommit, kind := .request,  subject := 42, head := 2 },
    { time := 110, tool := .pushCommit, kind := .response, subject := 42, head := 2 },
    { time := 300, tool := .runTests,   kind := .response, subject := 42, head := 1 },
    { time := 310, tool := .merge,      kind := .request,  subject := 42, head := 2 } ]

/-- The `since` monitor lets the race through: the spec is met, the property is not. -/
theorem since_spec_misses_second_race :
    Safe (enforce secondRace) ∧ mergesTested (enforce secondRace) = false :=
  ⟨enforce_safe secondRace, by decide⟩

/-- A monitor that correlates on *what was tested*, not on *when*. -/
def allowedSha (h : History) (e : Event) : Bool :=
  if e.tool == .merge && e.kind == .request then testedNow e.subject h else true

def stepSha (h : History) (e : Event) : History := if allowedSha h e then e :: h else h

def enforceSha (es : List Event) : History := es.foldl stepSha []

theorem stepSha_merges_tested (h : History) (e : Event) (hs : mergesTested h = true) :
    mergesTested (stepSha h e) = true := by
  unfold stepSha
  split
  · rename_i ha
    simp only [mergesTested, hs, Bool.true_and, Bool.or_eq_true, Bool.not_eq_true']
    by_cases hm : (e.tool == .merge && e.kind == .request) = true
    · right; simpa [allowedSha, hm] using ha
    · left; simpa using hm
  · exact hs

/-- **Whatever the agent attempts, every executed merge merged a tested commit.** -/
theorem enforceSha_merges_tested (es : List Event) : mergesTested (enforceSha es) = true := by
  suffices ∀ h, mergesTested h = true → mergesTested (es.foldl stepSha h) = true from this [] rfl
  induction es with
  | nil => intro h hs; exact hs
  | cons e es ih => intro h hs; exact ih (stepSha h e) (stepSha_merges_tested h e hs)

/-- And on the race itself, the SHA monitor refuses the merge. -/
example : (enforceSha secondRace).length = 4 := by decide

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
      · simp [hd, hlim]
        omega
    · simp [hd, hh]

/-- Three deploys launched in parallel before any response comes back. -/
def burst : List Event :=
  [ { time := 0, tool := .deploy, kind := .request,  subject := 1 },
    { time := 1, tool := .deploy, kind := .request,  subject := 2 },
    { time := 2, tool := .deploy, kind := .request,  subject := 3 },
    { time := 3, tool := .deploy, kind := .response, subject := 1 } ]

/-- Counting responses lets all three through: the limit of 2 is broken. -/
theorem response_counting_is_unsafe :
    ¬ ∀ es, (enforceBy isDeployResp 2 es).countP isDeployReq ≤ 2 :=
  fun h => absurd (h burst) (by decide)

end Course.L3

import Course.L1_Basics

/-!
# Lesson 2 — A verified mini-Cedar

Cedar's real specification lives in Lean (`cedar-policy/cedar-spec`, file
`cedar-lean/Cedar/Thm/Authorization.lean`). It proves theorems like
`forbid_trumps_permit` and `allowed_only_if_explicitly_permitted` about the
real authorizer, and AWS differentially tests the production Rust engine
against that Lean model.

Here we rebuild the core of it in about 40 lines, then prove the same kind of
theorems ourselves, including the surprising one about errors that kata
`reasoning/r3` makes you live through.
-/

namespace Course.L2
open Course.L1 (Tier)

/-! ## The authorizer -/

inductive Effect where
  | permit | forbid
  deriving DecidableEq, Repr

inductive Decision where
  | allow | deny
  deriving DecidableEq, Repr

/-- Evaluating a condition either yields a boolean or fails (integer overflow,
    a missing attribute, ...). Cedar conditions are total over well-typed
    requests, except for these errors. -/
inductive Outcome where
  | ok (b : Bool)
  | error (msg : String)
  deriving Repr

/-- A policy over requests of any type `α`. -/
structure Policy (α : Type) where
  id     : String
  effect : Effect
  cond   : α → Outcome

/-- A policy is *satisfied* only when its condition evaluates to `ok true`.
    An erroring policy is simply not satisfied. That is Cedar's rule. -/
def Policy.satisfied (p : Policy α) (r : α) : Bool :=
  match p.cond r with
  | .ok b    => b
  | .error _ => false

/-- Is some policy with effect `e` satisfied? -/
def satisfiedWith (e : Effect) (ps : List (Policy α)) (r : α) : Bool :=
  ps.any (fun p => p.effect == e && p.satisfied r)

/-- Deny by default; a satisfied forbid beats any permit. -/
def isAuthorized (ps : List (Policy α)) (r : α) : Decision :=
  if satisfiedWith .forbid ps r then .deny
  else if satisfiedWith .permit ps r then .allow
  else .deny

/-! ## Theorems about *every* policy set -/

theorem default_deny (r : α) : isAuthorized ([] : List (Policy α)) r = .deny := by
  simp [isAuthorized, satisfiedWith]

/-- Unpacking `satisfiedWith` into plain logic, used by the theorems below. -/
theorem satisfiedWith_iff {e : Effect} {ps : List (Policy α)} {r : α} :
    satisfiedWith e ps r = true ↔ ∃ p ∈ ps, p.effect = e ∧ p.satisfied r = true := by
  simp [satisfiedWith, List.any_eq_true]

theorem forbid_trumps_permit {ps : List (Policy α)} {r : α}
    (p : Policy α) (hp : p ∈ ps) (he : p.effect = .forbid) (hs : p.satisfied r = true) :
    isAuthorized ps r = .deny := by
  have hf : satisfiedWith .forbid ps r = true := satisfiedWith_iff.mpr ⟨p, hp, he, hs⟩
  simp [isAuthorized, hf]

theorem allowed_only_if_explicitly_permitted {ps : List (Policy α)} {r : α}
    (h : isAuthorized ps r = .allow) :
    ∃ p ∈ ps, p.effect = .permit ∧ p.satisfied r = true := by
  by_cases hf : satisfiedWith .forbid ps r = true
  · simp [isAuthorized, hf] at h
  · by_cases hp : satisfiedWith .permit ps r = true
    · exact satisfiedWith_iff.mp hp
    · simp [isAuthorized, hf, hp] at h

/-- Policy order never matters (Cedar's `order_and_dup_independent`, in miniature). -/
theorem order_independent {ps qs : List (Policy α)} (h : ps.Perm qs) (r : α) :
    isAuthorized ps r = isAuthorized qs r := by
  have key : ∀ e, satisfiedWith e ps r = satisfiedWith e qs r := by
    intro e
    apply Bool.eq_iff_iff.mpr
    simp only [satisfiedWith_iff]
    exact ⟨fun ⟨p, hp, hx⟩ => ⟨p, h.mem_iff.mp hp, hx⟩,
           fun ⟨p, hp, hx⟩ => ⟨p, h.mem_iff.mpr hp, hx⟩⟩
  simp [isAuthorized, key]

/-- Adding a forbid can only take permissions away. -/
theorem adding_forbid_is_safe {ps : List (Policy α)} {r : α}
    (f : Policy α) (hf : f.effect = .forbid)
    (h : isAuthorized (f :: ps) r = .allow) : isAuthorized ps r = .allow := by
  -- From `h`: no forbid in `f :: ps` fires, and some permit does.
  have hnot : satisfiedWith .forbid (f :: ps) r = false := by
    cases hx : satisfiedWith .forbid (f :: ps) r
    · rfl
    · simp [isAuthorized, hx] at h
  have hperm : satisfiedWith .permit (f :: ps) r = true := by
    cases hx : satisfiedWith .permit (f :: ps) r
    · simp [isAuthorized, hnot, hx] at h
    · rfl
  -- So no forbid in `ps` fires either...
  have hf' : satisfiedWith .forbid ps r = false := by
    cases hx : satisfiedWith .forbid ps r
    · rfl
    · obtain ⟨q, hq, hqe, hqs⟩ := satisfiedWith_iff.mp hx
      have : satisfiedWith .forbid (f :: ps) r = true :=
        satisfiedWith_iff.mpr ⟨q, List.mem_cons_of_mem _ hq, hqe, hqs⟩
      simp [this] at hnot
  -- ...and the permit that fired is in `ps`, because `f` is a forbid.
  have hp' : satisfiedWith .permit ps r = true := by
    obtain ⟨q, hq, hqe, hqs⟩ := satisfiedWith_iff.mp hperm
    rcases List.mem_cons.mp hq with rfl | hq
    · simp [hf] at hqe
    · exact satisfiedWith_iff.mpr ⟨q, hq, hqe, hqs⟩
  simp [isAuthorized, hf', hp']

/-! ## Errors: the forbid that wasn't

Because an erroring policy is "not satisfied", an erroring **forbid** never
denies. A guard that can overflow is a guard with a hole in it. -/

/-- A policy that errors on a request can be deleted without changing the decision. -/
theorem erroring_policy_is_ignored {ps : List (Policy α)} {r : α}
    (p : Policy α) (msg : String) (h : p.cond r = .error msg) :
    isAuthorized (p :: ps) r = isAuthorized ps r := by
  have hs : p.satisfied r = false := by simp [Policy.satisfied, h]
  simp [isAuthorized, satisfiedWith, hs]

/-- Kata `reasoning/r3`, in Lean. Requests are just risk scores here, and
    multiplication overflows past Cedar's 64-bit `Long` range. -/
def longMax : Nat := 2 ^ 63 - 1

def opsDeploys : Policy Nat := ⟨"ops-deploys", .permit, fun _ => .ok true⟩

def riskGate : Policy Nat :=
  ⟨"risk-gate", .forbid, fun risk =>
    if risk * 1000 > longMax then .error "integer overflow" else .ok (risk * 1000 > 5000)⟩

def fixedRiskGate : Policy Nat := ⟨"risk-gate", .forbid, fun risk => .ok (risk > 5)⟩

example : isAuthorized [opsDeploys, riskGate] 9 = .deny := by decide
example : isAuthorized [opsDeploys, riskGate] (2 ^ 62) = .allow := by decide   -- the hole

theorem fixed_gate_has_no_hole (risk : Nat) (h : risk > 5) :
    isAuthorized [opsDeploys, fixedRiskGate] risk = .deny :=
  forbid_trumps_permit fixedRiskGate (by simp) rfl (by simp [Policy.satisfied, fixedRiskGate, h])

/-! ## Orchard, modelled and proved

The same world as `modules/01-cedar/world`, simplified to what the theorems need.
One simplification matters: here `Tier` is an enum, so a tier named `""` or
`"qa"` can't exist. In the Cedar schema `tier` is any `String`, which is exactly
why kata `reasoning/r4` finds a counterexample there. A proof is only as strong
as its model's fit to the real system. -/

inductive Kind where
  | agent | human
  deriving DecidableEq, Repr

inductive Role where
  | productOwner | codeOwner | releaseManager
  deriving DecidableEq, Repr

inductive Action where
  | draftArtifact | approvePR | mergePR | deploy | readSecret
  deriving DecidableEq, Repr

structure Principal where
  name  : String
  kind  : Kind
  stage : String
  roles : List Role

structure Req where
  principal      : Principal
  action         : Action
  tier           : Tier
  prDriver       : String
  ciPassed       : Bool
  humanApprovals : Nat

def agentsDeployBelowProd : Policy Req := ⟨"agents-deploy-below-prod", .permit, fun r =>
  .ok (r.principal.kind == .agent && r.action == .deploy && r.principal.stage == "ops" && r.tier != .prod)⟩

def releaseManagersDeploy : Policy Req := ⟨"release-managers-deploy", .permit, fun r =>
  .ok (r.action == .deploy && r.principal.roles.contains .releaseManager)⟩

def codeOwnersApprove : Policy Req := ⟨"code-owners-approve-prs", .permit, fun r =>
  .ok (r.action == .approvePR && r.principal.roles.contains .codeOwner)⟩

def mergeOnGreen : Policy Req := ⟨"merge-on-green", .permit, fun r =>
  .ok (r.action == .mergePR && r.ciPassed && decide (r.humanApprovals ≥ 1))⟩

def agentsNeverApprove : Policy Req := ⟨"agents-never-approve", .forbid, fun r =>
  .ok (r.principal.kind == .agent && r.action == .approvePR)⟩

def noSelfApproval : Policy Req := ⟨"no-self-approval", .forbid, fun r =>
  .ok (r.action == .approvePR && r.principal.name == r.prDriver)⟩

def agentsNeverDeployProd : Policy Req := ⟨"agents-never-deploy-prod", .forbid, fun r =>
  .ok (r.principal.kind == .agent && r.action == .deploy && r.tier == .prod)⟩

def orchard : List (Policy Req) :=
  [agentsDeployBelowProd, releaseManagersDeploy, codeOwnersApprove, mergeOnGreen,
   agentsNeverApprove, noSelfApproval, agentsNeverDeployProd]

/-- The production gate, for every agent, every request, every attribute value. -/
theorem no_agent_deploys_prod (r : Req)
    (hk : r.principal.kind = .agent) (ha : r.action = .deploy) (ht : r.tier = .prod) :
    isAuthorized orchard r = .deny :=
  forbid_trumps_permit agentsNeverDeployProd (by simp [orchard]) rfl
    (by simp [Policy.satisfied, agentsNeverDeployProd, hk, ha, ht])

/-- Separation of duties: whoever drives a PR cannot be the one who approves it. -/
theorem separation_of_duties (r : Req)
    (h : isAuthorized orchard r = .allow) (ha : r.action = .approvePR) :
    r.principal.name ≠ r.prDriver := by
  intro heq
  have hd := forbid_trumps_permit (ps := orchard) (r := r) noSelfApproval (by simp [orchard]) rfl
    (by simp [Policy.satisfied, noSelfApproval, ha, heq])
  rw [hd] at h
  contradiction

end Course.L2

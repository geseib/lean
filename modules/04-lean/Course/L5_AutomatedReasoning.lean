import Course.L4_Lifecycle
import Std.Tactic.BVDecide

/-!
# Lesson 5 — Automated reasoning *inside* the proof assistant

Module 03 used an SMT solver as an oracle: `cedar symcc` asked cvc5 and
believed the answer. That solver is tens of thousands of lines of C++. AWS's
answer to "who checks the checker?" is twofold: SymCC's encoding is proved
correct in Lean, and solver results can be *certified*.

Lean ships decision procedures whose answers its kernel re-checks:

| tactic       | decides                                   | how it earns trust |
|--------------|-------------------------------------------|--------------------|
| `decide`     | any decidable claim over finite data      | kernel evaluation |
| `omega`      | linear arithmetic over `Nat` and `Int`    | produces a proof term |
| `bv_decide`  | fixed-width bit-vector claims (Cedar's 64-bit `Long`) | SAT solver (CaDiCaL) emits an LRAT certificate the kernel checks |
| `simp`, `grind` | rewriting / SMT-style congruence and case splits | proof terms |

So "automated" and "trusted" stop being a trade-off: the search can be clever
and untrusted, because the result is checked.
-/

namespace Course.L5

/-! ## `omega`: budgets and rate limits -/

/-- Bundle d5 (module 2): if every call stays under the per-call cap and the
    budget admits only `n` calls, the hourly spend is bounded. -/
theorem token_budget (calls perCall n : Nat) (hcalls : calls ≤ n) :
    calls * perCall ≤ n * perCall :=
  Nat.mul_le_mul_right perCall hcalls

theorem rate_limit_window (inWindow allowed : Nat) (h : inWindow + 1 > allowed + 1) :
    inWindow ≥ allowed + 1 := by
  omega

/-! ## `bv_decide`: 64-bit arithmetic exactly as Cedar does it

Cedar's `Long` is a signed 64-bit integer with overflow *errors*. That is the
root of kata `reasoning/r3`. Bit-vectors let Lean reason about it exactly. -/

/-- `riskScore * 1000` can overflow a signed 64-bit integer... -/
theorem risk_times_1000_can_overflow :
    ∃ x : BitVec 64, BitVec.smulOverflow x 1000#64 = true :=
  ⟨0x4000000000000000#64, by decide⟩

/-- ...while the rewritten guard `riskScore > 5` is a plain comparison. And for
    every value where the multiplication does NOT overflow, the two guards agree. -/
theorem guards_agree_without_overflow (x : BitVec 64)
    (h : BitVec.smulOverflow x 1000#64 = false) :
    (5000#64).slt (x * 1000#64) = (5#64).slt x := by
  bv_decide

/-! ## Permission bitmasks, proved for all 2⁶⁴ values -/

def READ        : BitVec 64 := 0x01#64
def WRITE       : BitVec 64 := 0x02#64
def DEPLOY_STG  : BitVec 64 := 0x04#64
def DEPLOY_PROD : BitVec 64 := 0x80#64

/-- Whatever bits an agent requests, the gateway masks them to this ceiling. -/
def agentCeiling : BitVec 64 := READ ||| WRITE ||| DEPLOY_STG

theorem masked_agents_never_get_prod (requested : BitVec 64) :
    (requested &&& agentCeiling) &&& DEPLOY_PROD = 0#64 := by
  simp only [agentCeiling, READ, WRITE, DEPLOY_STG, DEPLOY_PROD]
  bv_decide

end Course.L5

# Module 4 — Lean: proving the system, not just the policies

> **You will leave this module able to** read and write Lean 4 proofs about an
> authorizer, a temporal runtime monitor and a lifecycle state machine, and
> explain how AWS uses Lean to trust Cedar and its analyzer.
> Katas: `lean/e1` – `lean/e4`. Time: 3–5 hours. This is the deep end, but it is
> warm.

## 1. Why this rung exists

Module 3 trusted two big things: SymCC's encoding of Cedar into logic, and
the solver. Module 2 trusted Dogwood's monitor to compute `since` correctly.
**Lean** removes trust by proof. You write definitions and theorems, and a
small kernel checks every proof step. AWS's Cedar team keeps Cedar's
specification in Lean ([cedar-spec](https://github.com/cedar-policy/cedar-spec)),
proves properties like *forbid trumps permit* there, proves SymCC sound and
complete, and differentially tests the Rust engine against the Lean model.

## 2. Setup

```bash
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh
cd modules/04-lean && lake build          # builds Course/ and Solutions/
code .                                    # VS Code + the "Lean 4" extension
```

Put your cursor inside a proof. The **infoview** shows the current goal, and
it updates after every tactic. Proving is a conversation with that panel.

## 3. The lessons (read in order; every theorem is proved)

| File | You'll see | Mirrors |
|---|---|---|
| [`Course/L1_Basics.lean`](Course/L1_Basics.lean) | types, functions, `#eval`, `rfl`, `simp`, `cases`, `induction`, `omega` | — |
| [`Course/L2_Authorization.lean`](Course/L2_Authorization.lean) | a 40-line mini-Cedar; `default_deny`, `forbid_trumps_permit`, `allowed_only_if_explicitly_permitted`, `order_independent`, `erroring_policy_is_ignored`; Orchard's gate and separation of duties as theorems | module 1, kata r3 |
| [`Course/L3_Temporal.lean`](Course/L3_Temporal.lean) | a mini-Dogwood: **the `since` monitor equals its MFOTL semantics** (`sinceNot_iff`); **any enforced execution is safe** (`enforce_safe`); request-counting is safe and response-counting is **provably unsafe** | module 2, kata k1 |
| [`Course/L4_Lifecycle.lean`](Course/L4_Lifecycle.lean) | the AI-native SDLC as a state machine; **every released change carries every human sign-off, and its reviewer was not its author** (`released_has_every_gate`) | the ADLC |
| [`Course/L5_AutomatedReasoning.lean`](Course/L5_AutomatedReasoning.lean) | `omega` and `bv_decide`: a SAT solver whose answers the kernel re-checks; 64-bit overflow exactly as Cedar has it | module 3 |

## 4. Your katas

Open `Exercises/E*.lean`, replace each `sorry` with a proof, and check:

```bash
./course check lean/e1      # "every theorem in Exercises/E1_Basics.lean is proved"
```

| Kata | Theorems |
|---|---|
| `lean/e1` | humans deploy anywhere; `countAgents` over append; replicate |
| `lean/e2` | adding a permit is monotone; only humans approve; **boss:** nothing merges on red CI |
| `lean/e3` | a `formerly within` monitor equals its semantics; enforcing d2's approval rule is safe |
| `lean/e4` | `released` only follows `merged`; merged ⇒ planned; sign-offs are never erased |

## 5. Tactic cheat sheet

| Goal looks like | Try |
|---|---|
| a computation on concrete values | `rfl`, `decide` |
| unfold definitions and simplify | `simp [defName]`, `simp_all` |
| `p → q`, `∀ x, …` | `intro h`, `intro x` |
| an inductive value (Tier, Actor, a list) | `cases x`, `induction xs with …` |
| `∃ x, P x` | `exact ⟨witness, proof⟩` |
| a hypothesis `∃`/`∧` | `obtain ⟨x, hx⟩ := h` |
| arithmetic over `Nat`/`Int` | `omega` |
| bit-vectors (`BitVec 64`) | `bv_decide` |
| "this is impossible" | `contradiction`, `simp at h` |

## ✅ Check yourself

<details><summary>1. <code>erroring_policy_is_ignored</code> says an erroring policy can be deleted without changing any decision. Why is that alarming for a forbid, and harmless for a permit?</summary>

A forbid exists to deny. If it errors on some input, it denies nothing there,
and the request falls through to the permits. An erroring permit just doesn't
grant, which is the safe direction.
</details>

<details><summary>2. <code>enforce_safe</code> holds "whatever the agent attempts". What exactly is quantified?</summary>

Every list of events `es`: any interleaving, any subjects, any timing,
adversarial or not. The theorem says the *executed* trace (allowed requests
plus responses) satisfies `Safe`. That's the shape of a runtime-verification
guarantee.
</details>

<details><summary>3. <code>sinceNot_iff</code> proves both directions. What would go wrong with only "monitor true → semantics true"?</summary>

You'd know the monitor never allows wrongly (sound), but it might *deny*
legitimate merges forever (incomplete). Completeness is what makes the
guardrail usable.
</details>

<details><summary>4. The lifecycle theorem is about names in an audit trail. What would you add to make it say "approved by a human", not just "approved by someone"?</summary>

Record the approver as an `Actor` rather than a name, and add to `Inv` the
fact `reviewer.isAgent = false`. The `approveReview` step already requires
`lead.isHumanWith .codeOwner`, so the invariant goes through the same way.
Try it.
</details>

**Next:** [Module 5 — Capstone](../05-capstone/README.md): put a real agent under these guarantees.

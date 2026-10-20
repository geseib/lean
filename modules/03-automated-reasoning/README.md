# Module 3 — Automated reasoning: from "we tested it" to "we proved it"

> **You will leave this module able to** state guardrail properties precisely,
> prove them about a Cedar policy set for *every* possible request with
> `cedar symcc`, read counterexamples, and run the same checks AgentCore Policy
> runs on LLM-generated policies (dead, blanket and shadowed policies; change
> impact). Katas: `reasoning/r0` – `reasoning/r5`. Time: about 2.5 hours.

## 1. The idea: ask the solver for a bug

A test asks "is *this* request handled right?". Automated reasoning asks
"does *any* request violate the property?" and hands the question to a solver:

```
     policies ──symbolic compiler──▶  formula  Allowed(r)
     property ─────────────────────▶  formula  Safe(r)
                                      solver: is  Allowed(r) ∧ ¬Safe(r)  satisfiable?
                     unsat  ─▶  PROVED: no request, no entity store, no attribute value breaks it
                     sat    ─▶  COUNTEREXAMPLE: here is a concrete request that does
```

Kata **`reasoning/r0`** has you build exactly this, in about 40 lines of Python
with z3, for a mini-Orchard. Do it first: it makes everything after it
unmagical. (Two simplifications to notice: z3's `Int` is unbounded and the
mini-model has no errors, while Cedar's `Long` is 64-bit and overflow is an
error. Kata r3 is about exactly that gap.)

> **If you know OPA:** `opa eval --partial` with `input` unknown gives you a
> *residual query*: a simplified condition. It doesn't answer "is there an
> input where `allow` holds and my invariant fails?". Answering that needs a
> solver over the whole policy, the schema and the data model, which is what
> SymCC does. Rego's expressiveness makes a complete encoding impractical;
> Cedar was designed so one exists. See [docs/for-rego-users.md](../../docs/for-rego-users.md).

## 2. The real thing: Cedar's SymCC

Cedar ships a **symbolic compiler** that encodes policies, schema and entity
store into SMT-LIB for the cvc5 solver. The encoding is proved sound and
complete in Lean. It's available from the Cedar CLI:

```bash
cargo install cedar-policy-cli --locked --features analyze
pip install cvc5          # tools/cvc5-py adapts the bindings to SymCC (or use a cvc5 binary)

cd modules/01-cedar/world            # no-agent-prod.cedar is the property (see §3)
cedar symcc --cvc5-path ../../../tools/cvc5-py \
  --principal-type Orchard::Agent --action 'Orchard::Action::"deploy"' \
  --resource-type Orchard::Environment --schema schema.cedarschema \
  implies --policies1 policies.cedar --policies2 no-agent-prod.cedar
# ✓ Policy set 1 implies policy set 2: VERIFIED
```

Analyses are per **request environment**: one principal type, one action and
one resource type. Over that environment, every entity and every attribute
value is symbolic.

**Why cvc5?** SymCC's encoding uses cvc5's theory of finite sets for Cedar's
`Set` values and entity hierarchies (`set.member` and friends). z3 doesn't
support that theory, so it rejects these queries. `tools/cvc5-py` runs cvc5
through its official Python bindings when the cvc5 binary isn't installed.
Set `SMT_TEE=/tmp/q.smt2` to keep a copy of the exact query SymCC sends.

| Check | Question | Used for |
|---|---|---|
| `implies P B` | does B allow everything P allows? | **safety properties**: B is the envelope of the acceptable |
| `equivalent P Q` | same decision on every request? | **safe refactors** |
| `always-denies P` | is nothing ever allowed? | "no agent ever approves a PR" |
| `never-errors p` | can this policy's evaluation fail? | the overflow trap (r3) |
| `never-matches p` | is this policy dead? | contradictory conditions in generated policies |
| `always-matches p` | is this a blanket grant? | tautologies in generated policies |
| `matches-implies p f` | is permit p completely shadowed by forbid f? | conflicts in generated policies |

The last three are the per-policy and conflict findings AWS describes for
AgentCore Policy's NL-to-Cedar loop.

## 3. Writing properties as policies

A property for `implies` is a policy set describing everything acceptable:

```cedar
// For (Agent, deploy, Environment): allowed ⇒ not prod.
permit (principal, action, resource) unless { resource.tier == "prod" };
```

**Beware the vacuous property.** `permit(principal, action, resource);` is
implied by every policy set, so it "proves" nothing. Kata r1 guards against this
with **mutation testing**: each property must also *reject* a known-buggy
mutant policy set (`must_reject` in `properties.toml`).

## 4. What counterexamples teach you

Solvers pick values nobody tests. In kata r4 the counterexample for a "harmless"
refactor is an ops agent deploying to an environment whose tier is the empty
string `""`. The schema says `tier: String`, so `tier != "prod"` admits every
other string, while the original admitted exactly `"dev"` and `"staging"`. The
fix (use set membership, or make the tiers an enumerated entity type) is a
design insight, not just a bug fix.

## 5. Your katas

| Kata | Scenario | Check |
|---|---|---|
| `reasoning/r0` | build an analyzer from scratch (z3) | python |
| `reasoning/r1` | prove the constitution; catch four mutants | implies, always-denies |
| `reasoning/r2` | a hotfix fast lane reached prod | implies + regression tests |
| `reasoning/r3` | an overflowing forbid that silently stops denying | never-errors + tests |
| `reasoning/r4` | prove a refactor equivalent | equivalent |
| `reasoning/r5` | lint an LLM's draft: dead, blanket, shadowed | never-matches, always-matches, matches-implies |

Edit the files named in each kata's README or `kata.toml`;
`properties.toml` lists the theorems being checked.

## ✅ Check yourself

<details><summary>1. <code>implies</code> returned VERIFIED. Can an agent still deploy to prod?</summary>

Not through these policies, for any request in that environment (Agent, deploy,
Environment) and any entity data that fits the schema. "VERIFIED" is about the
policies, though. If your gateway maps a prod deploy to a different action or
resource type, the proof doesn't cover it. Proofs are only as good as the
model's fit to reality.
</details>

<details><summary>2. Why does r3's forbid, which plainly says "deny when risk is high", allow a huge risk score?</summary>

`riskScore * 1000` overflows a 64-bit Long, which makes it an **error**. Cedar
skips erroring policies, and a skipped forbid denies nothing. `never-errors`
finds this. Lean module lesson 2 proves the general fact
(`erroring_policy_is_ignored`).
</details>

<details><summary>3. In r5, <code>never-matches</code> "fails" and that is what we want. Why?</summary>

The check asks "does this policy never match?" A permit that never matches is
dead code that silently fails its intent. Wanting it to *fail* means wanting the
policy to be live.
</details>

<details><summary>4. Why does SymCC need cvc5 and not z3 here?</summary>

As §2 explains: its encoding uses cvc5's finite-set theory (`set.member` …) for
Cedar sets and entity hierarchies. The mini-analyzer in r0 has no sets, so z3
is fine there.
</details>

## Bonus: proving a Dogwood forbid for every history

Cedar's analyzer can't see inside temporal conditions, but you can still
prove a lot. `dogwood lower` turns each temporal block into a boolean
`context` slot, and SymCC treats that slot as *any* boolean. So if a property
holds over the lowered policy set, it holds whatever the history says. Try it
on the capstone guard: `never-deploy-prod` is pure Cedar, so "no prod deploy is
ever allowed" can be proved for every possible trace, without replaying one:

```bash
G=modules/05-capstone/guard; S=modules/02-dogwood/world/schema.cedarschema
dogwood lower $G/policy.dw --policy-schema $S --emit cedar-policies > /tmp/lowered.cedar
dogwood lower $G/policy.dw --policy-schema $S --emit cedar-schema   > /tmp/lowered.cedarschema
echo 'permit (principal, action, resource) unless { context.input.env == "prod" };' > /tmp/bound.cedar
cedar symcc --cvc5-path tools/cvc5-py --principal-type Drupe::OAuthUser \
  --action 'Drupe::Action::"Deploy"' --resource-type Drupe::Gateway --schema /tmp/lowered.cedarschema \
  implies --policies1 /tmp/lowered.cedar --policies2 /tmp/bound.cedar
# ✓ Policy set 1 implies policy set 2: VERIFIED
```

**Next:** [Module 4 — Lean](../04-lean/README.md): who checks the checker?

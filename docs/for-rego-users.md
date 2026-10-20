# Coming from OPA and Rego

You already think in policies: `default allow := false`, `deny[msg]` sets,
`opa test`, Gatekeeper constraints, decision logs. Most of that transfers
directly. This page maps what you know onto Cedar, Dogwood and the analysis
tools, and flags the places where a Rego intuition will mislead you.

## Why not just OPA?

OPA is a general-purpose policy engine over arbitrary JSON. Rego is
expressive: comprehensions, recursion through `graph.reachable`, `walk`,
`http.send`. That expressiveness is why OPA fits everywhere, and also why
it's hard to **analyze** Rego completely. Questions like "is there *any*
input where `allow` is true and my invariant is false?" don't have a general,
decidable answer for arbitrary Rego.

Cedar makes the opposite trade. The language is deliberately small: no loops,
no unbounded quantifiers, no I/O, and a schema-checked type system. Because of
that, Cedar policies can be translated **completely** into SMT logic, and a
solver can either prove a property for every request or hand you a
counterexample. That is the point of module 3, and the main reason AWS chose
Cedar for agent tool calls in AgentCore Policy.

The second difference is **state**. OPA evaluates each query statelessly;
decision logs are an *output*. Dogwood takes the history of an agent's tool
calls as an *input*, maintained by the enforcement point, so a policy can say
"since", "formerly" and "at most N per hour" natively.

## Module 1: the decision model

| You know (Rego / Gatekeeper) | In Cedar | Note |
|---|---|---|
| `default allow := false` | deny by default, always | not configurable |
| `allow if { … }` (several bodies are ORed) | several `permit` policies | |
| `deny[msg] { … }` | `forbid` policies | no message: Cedar reports the **determining policy ids** (`@id`) |
| your own combinator, e.g. `allow if { some_permit; count(deny) == 0 }` | **built in**: any satisfied forbid → DENY; else any satisfied permit → ALLOW; else DENY | you can't get it wrong, and module 4 proves its properties |
| order independence (no `else`) | same; there is no `else` | |
| `input` | `context` (plus `principal`, `action`, `resource`) | in AgentCore, `context.input` holds the tool arguments **the LLM chose** |
| `data` (bundles, push API) | the **entity store**: typed entities with attributes and parents, passed with the request | think "the slice of `data` this request needs, typed by the schema" |
| `graph.reachable(data.parents, [input.user])` | `principal in Orchard::Role::"CodeOwner"` | transitive membership is native |
| `input.principal.type == "agent"` | `principal is Orchard::Agent` | a type test on the entity, not a field the caller controls |
| `not cond` (negation as failure) | `unless { cond }` | |
| `object.get(x, "k", d)`, existence checks | `x has k` | a missing attribute is a *validation* error in Cedar, not "undefined" |
| `opa check --strict` with schemas | `cedar validate --schema` | Cedar's validator is sound for its type system |
| `opa test` with `with input as …` | `./course check` (tests.json → `cedar authorize`) | tests can't show that a forbid *exists*; module 3 proves invariants instead |

### The one that bites: errors

In Rego (without `--strict-builtin-errors`), a builtin error makes the
expression **undefined**, so a `deny` rule silently doesn't fire.

Cedar has the same shape. A policy whose condition **errors** (integer
overflow, for example) is **skipped**, and a skipped `forbid` denies
nothing. There is no strict mode to switch on. Instead, you **prove** the
policy can't error: `cedar symcc … never-errors`. Kata `reasoning/r3` is this
bug, and Lean lesson 2 proves the general fact (`erroring_policy_is_ignored`).

## Module 2: history

| You'd do in OPA | In Dogwood |
|---|---|
| have the caller put history into `input` (and trust the caller) | the enforcement point records every tool call; policies read the trace |
| keep state in an external store, then `http.send` it (non-deterministic) | history is first-class, typed, and deterministic on replay |
| `some e in input.history; e.tool == "ReadSecret"; now - e.t < w` | `formerly within 24h Drupe::Action::"ReadSecret"::request{ input.name: * }` |
| (no idiom) | `!Push since within 24h TestsPassed` |
| `count([e | …])` over `input.history` | `count_within(1h, …)`, `sum_within(x, 1h, …)` |
| `opa eval` over a recorded decision log | `dogwood replay` over a recorded trace: the trace holds *inputs*, not outputs |
| (no equivalent) | `dogwood explain`: the policy read back as deterministic English |

Two things have no Rego analogue. First, **the request being decided is
already in the history** when it's decided, so "more than 2 in the last hour"
counts this one. Second, by default **history is keyed by principal**: a policy
sees only the requesting session's events.

## Module 3: analysis

| You know | Here |
|---|---|
| `opa eval --partial` with `input` unknown → a residual query | SymCC encodes the policies, schema **and** entity hierarchy symbolically, then asks cvc5 whether `Allowed ∧ ¬Safe` is satisfiable. `unsat` is a proof; `sat` is a concrete counterexample request and entity store |
| conftest / fixture suites to approximate "the new policy allows no more than the old one" | `cedar symcc implies` / `equivalent`, over **all** inputs |
| Regal (syntactic and style lint) | `never-matches`, `always-matches`, `matches-implies`: *semantic* lints (dead, blanket, shadowed) |
| a property as an assertion in a test | a property is a **policy set**: the envelope you'd be happy to deploy. `P implies B` means everything P allows, B allows |
| per-constraint-kind checks in Gatekeeper | analysis per **request environment**: one principal type, one action, one resource type |

## Module 5: the guard

| Kubernetes | Claude Code guard |
|---|---|
| validating admission webhook | `PreToolUse` hook |
| `AdmissionReview` (typed) | `tool_name` + `tool_input` (often a free-form shell string, so the classifier is part of your TCB) |
| `allowed: false` | `permissionDecision: "deny"` |
| `failurePolicy: Fail` | fail closed: any error while deciding denies |

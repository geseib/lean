# Module 2 — Dogwood: rules about what already happened

> **You will leave this module able to** write temporal guardrails over an
> agent's tool-call history (`formerly`, `since`, counts and sums), replay
> traces to see exactly when they fire, and avoid the request-vs-response
> trap that lets concurrent agents slip past a limit.
> Katas: `dogwood/k1` – `dogwood/k3`. Time: about 2 hours.

## 1. The gap

Cedar decides one request at a time. Agents create risk in *sequences*:

| Rule | Why Cedar can't say it |
|---|---|
| Merge only if tests passed **and nothing was pushed since** | needs the order of past events |
| No internet **after** this session read a secret | needs a past event |
| At most 2 prod deploy attempts **per hour** | needs a count over a window |
| At most 50k model tokens **per hour** | needs a sum over a window |

[Dogwood](https://github.com/dogwood-policy/dogwood) (AWS, Apache-2.0, 2026)
adds `when temporal { … }` clauses that read the agent's **event history**. It
is a strict extension: every Cedar policy is a Dogwood policy.

## 2. Events, traces and decisions

Each tool call produces events: a **`request`**, which is a *decision point*,
then later a **`response`**, which only goes into the history. A trace is the
timestamped list of them. The action schema is generated from the agent's MCP
tool manifest:

```bash
dogwood schema mcp --manifest world/tools.json -o world/schema.cedarschema
```

Our traces are written in a compact form and compiled for Dogwood
([`tools/dwtrace.py`](../../tools/dwtrace.py)):

```text
@300  coder  RunTests.response   pr="42" | passed=true
@310  coder  MergePullRequest.request  pr="42"     # -> ALLOW?
```

**Scope:** by default, history is keyed on the principal. A policy only sees
the events of the session (principal) making the request. Bundle d3 shows a
second agent's session staying unaffected.

## 3. The operators (all look only into the past, and all need a window)

| Operator | Reads as | Example bundle |
|---|---|---|
| `formerly within W P` | P happened at least once in the last W | d2, d3, d6 |
| `!B since within W A` | A happened, and no B since | d1 |
| `previous within W P` | the immediately preceding event was P | (guide) |
| `count_within(W, P)` | how many P in the last W | d4 |
| `sum_within(x, W, P{f: x})` | total of field f over P in the last W | d5 |
| `bind(n, agg, n > k)` | name an aggregate and compare it | d4, d5 |

A predicate looks like `Drupe::Action::"RunTests"::response{ input.pr: context.input.pr, output.passed: true }`:
the past event's fields are matched against literals, wildcards (`*`) or the
**current** request (`context.input.pr`).

## 4. Worked bundles: read, replay, explain

Each folder in [`bundles/`](bundles/) holds a policy, an annotated scenario
and the expected verdicts:

| Bundle | Lifecycle stage | Guardrail |
|---|---|---|
| [d1](bundles/d1-merge-requires-green-ci/) | SDLC | merge only on a green, untouched head (`since`) |
| [d2](bundles/d2-prod-needs-human-approval/) | release | prod deploys need a human release approval in the last 4h (`formerly` + Cedar `when`) |
| [d3](bundles/d3-no-egress-after-secrets/) | security | lethal trifecta: no egress after reading a secret |
| [d4](bundles/d4-prod-deploy-rate-limit/) | ops | at most 2 prod deploy attempts per hour (`count_within`) |
| [d5](bundles/d5-model-token-budget/) | ADLC cost | 50k-token hourly budget for sub-agents (`sum_within`) |
| [d6](bundles/d6-spec-before-code/) | PDLC → SDLC | no code before an approved spec (7-day window, custom event schema) |

```bash
cd modules/02-dogwood
B=bundles/d1-merge-requires-green-ci
python3 ../../tools/dwtrace.py $B/scenario.trace > /tmp/trace.log
dogwood replay  $B/policy.dw --policy-schema world/schema.cedarschema --trace /tmp/trace.log
dogwood explain $B/policy.dw --policy-schema world/schema.cedarschema
```

`dogwood explain` prints a policy back as deterministic English. Hand that to
the product owner who wrote the requirement: it's how a human checks an
LLM-authored policy without reading Dogwood.

## 5. The trap: request vs response

A `response` exists only once a call **finished**. Agents make calls in
parallel, so a push can be *in flight* when a merge is decided. A policy that
looks for push **responses** can't see it. The fix is to look for the push
**request**, which exists as soon as it was attempted. The AWS launch post makes
the same point about summing transfer amounts. Kata `dogwood/k1` makes you
live it, and lesson 3 of module 4 *proves* that response-counting is unsafe and
request-counting is safe.

Also note: a **denied** request still lands in the history as an attempt. d4 and
d5 show the consequence. Retrying a denied call keeps you over the limit.

## 6. Your katas

| Kata | You'll practice |
|---|---|
| `dogwood/k1` The in-flight race | request vs response, under concurrency |
| `dogwood/k2` Review AND green head | composing `formerly` and `since` with `&&` |
| `dogwood/k3` Loop breaker | `forbid … when temporal … unless temporal …`, counts, human override |

Each kata folder has `policy.dw` (yours), `scenario.trace` (annotated; add your
own lines) and `expected.out`. `./course check dogwood/k1` replays your policy
and marks every decision point.

## ✅ Check yourself

<details><summary>1. In d1, why <code>!PushCommit since RunTests(passed)</code> and not <code>formerly RunTests(passed)</code>?</summary>

`formerly` would accept a green run from before the latest push, which means
merging an untested head. `since` demands that nothing broke the property
after the anchor.
</details>

<details><summary>2. d4 counts Deploy <em>requests</em>, including denied ones. Is that a bug?</summary>

It's a choice: count *attempts*. An agent hammering a denied action stays
throttled until its attempts age out. If you want only successful deploys to
count, match `response` events instead, and accept the in-flight race from k1.
</details>

<details><summary>3. The planner and the coder are separate agent sessions. Can a spec approval in the planner's session unlock the coder's WriteCode?</summary>

Not with the default event schema, which keys history on the principal. Either
the same session carries the feature from spec to code (d6), or you supply an
event schema that correlates on a shared key, such as a feature or session id
(see the Dogwood guide's event-schema chapter).
</details>

<details><summary>4. Why can't you just run <code>cedar symcc</code> on a Dogwood policy to prove it?</summary>

Temporal conditions aren't supported by Cedar's automated-reasoning tools yet.
`dogwood lower` compiles them to opaque `context.*` slots. The Cedar part
can still be analyzed, and module 4 proves the temporal monitor in Lean instead.
</details>

**Next:** [Module 3 — Automated reasoning](../03-automated-reasoning/README.md).

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

## 3. Anatomy of a Dogwood policy

Here is bundle d1, annotated. (It contains a deliberate race that kata k1
asks you to find.)

```text
@id("merge_on_green_head")                       // ① a name; verdicts report rules by position
permit (                                         // ② an ordinary Cedar scope
    principal,
    action == Drupe::Action::"MergePullRequest", // ③ Drupe = the namespace generated from the MCP manifest
    resource
)
when temporal {                                  // ④ a temporal block: ONE condition over history
    !Drupe::Action::"PushCommit"::response{      // ⑤ a predicate: action :: event kind { field: pattern }
        input.pr: context.input.pr               // ⑥ correlate a past event's field with THIS request
    }
    since within 24h                             // ⑦ an operator, with a mandatory window
    Drupe::Action::"RunTests"::response{ input.pr: context.input.pr, output.passed: true }
};
```

* **②** Everything outside `temporal { … }` is plain Cedar. `when { … }` and
  `when temporal { … }` can both appear on one policy (bundle d2).
* **③** `dogwood schema mcp` generates one action per MCP tool in a namespace
  called `Drupe`. It also puts every tool action in a group,
  `Drupe::Action::"CallTool"`, so `action in Drupe::Action::"CallTool"` means
  "any tool". The principal type is `OAuthUser` and the resource is a
  `Gateway`; in AgentCore those are the caller's identity and the gateway in
  front of the tools.
* **④** A temporal block holds one condition. The only connective is `&&`
  (there's no `||`: write two policies). `!` binds tighter than `since`, which
  binds tighter than `&&`, so `!A since B` negates only A.
* **⑤** `request` events are decision points. `response` events only enter the
  history. Fields live under `input.*` and `output.*`. `*` is a wildcard.
* **⑦** Every window is a sliding look-back (`s`, `m`, `h`, `d`), capped at
  **24h by default**. Raise the cap with `max_window` in an event schema (d6).
* The **request being decided is already in the history** when it's decided.
  So `count_within(1h, Deploy::request{…}) > 2` counts this attempt too (d4).

### Reading `dogwood replay` output

```text
@1000 (time point 8): ALLOW  [rules: 1]
 │          │            │       └─ the policies that decided, by position in the file (0-based)
 │          │            └─ the verdict
 │          └─ the event's index in the trace (MFOTL calls positions "time points")
 └─ the timestamp, in seconds
```

History-only events (responses) print no line.

### What `dogwood lower` shows you

```bash
dogwood lower bundles/d1-merge-requires-green-ci/policy.dw --policy-schema world/schema.cedarschema --emit cedar-policies
# permit(principal, action == Drupe::Action::"MergePullRequest", resource) when { context.policy_1__temporal_0 };
```

Dogwood compiles each temporal block into a boolean `context` slot that it fills
at run time from the history, and hands the rest to an ordinary Cedar engine.
That's why any Cedar policy is a Dogwood policy. It's also why Cedar's
analyzer can't see inside temporal conditions: to SymCC they are opaque
booleans. (Module 3 turns that into a trick: if a forbid holds *whatever* the
slot's value, it holds for every history.)

### Glossary

| Term | Meaning |
|---|---|
| trace | the timestamped list of an agent session's events |
| event kind | `request` (decided) or `response` (history only); schemas may define others |
| time point | an event's position in the trace |
| window | how far back an operator looks; mandatory; 24h cap by default |
| principal-keyed | each principal (session) sees only its own events (the default event schema "pins" `callerPrincipal`) |
| `callerPrincipal`, `callerResource`, `requestId` | fields every compiled event carries; `tools/dwtrace.py` fills them for you |

> **If you know Rego:** in OPA you'd pass history in `input` (trusting the
> caller to compute it) or fetch it with `http.send`. Dogwood makes the history
> an input that the enforcement point maintains itself. See
> [docs/for-rego-users.md](../../docs/for-rego-users.md).

## 4. The operators (all look only into the past, and all need a window)

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

## 5. Worked bundles: read, replay, explain

Each folder in [`bundles/`](bundles/) holds a policy, an annotated scenario
and the expected verdicts:

| Bundle | Lifecycle stage | Guardrail |
|---|---|---|
| [d1](bundles/d1-merge-requires-green-ci/) | SDLC | merge only on a green, untouched head (`since`); contains the race kata k1 fixes |
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

## 6. The trap: request vs response

A `response` exists only once a call **finished**. Agents make calls in
parallel, so a push can be *in flight* when a merge is decided. A policy that
looks for push **responses** can't see it. The fix is to look for the push
**request**, which exists as soon as it was attempted. The [AWS launch post](https://aws.amazon.com/blogs/opensource/introducing-dogwood-runtime-verification-for-ai-agents/)
makes the same point about summing transfer amounts. Kata `dogwood/k1` makes you
live it. For counting limits like d4, lesson 3 of module 4 *proves* that
counting responses is unsafe and counting requests is safe.

**There's a second race**, which k1's fix doesn't close: a push made *while the
tests are running* lands before the green response that anchors `since`. The
merge then ships a head the tests never saw. k1's stretch goal asks you to
reproduce it. The robust fix is to correlate on what was tested: have
`RunTests` report the commit SHA it tested and `MergePullRequest` carry the SHA
it merges, and require them to match.

Also note: a **denied** request still lands in the history as an attempt. d4 and
d5 show the consequence. Retrying a denied call keeps you over the limit.

## 7. Your katas

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

Not with the default event schema, which keys history on the principal (see the
glossary). Either the same session carries the feature from spec to code (d6),
or you supply an event schema that pins a different shared key, such as a
feature or session id (see the Dogwood guide's event-schema chapter).
</details>

<details><summary>4. Why can't you just run <code>cedar symcc</code> on a Dogwood policy to prove it?</summary>

Temporal conditions aren't supported by Cedar's automated-reasoning tools yet.
As §3 showed, `dogwood lower` compiles them to opaque `context.*` slots. The
Cedar part can still be analyzed, and module 4 proves the temporal monitor in
Lean instead.
</details>

**Next:** [Module 3 — Automated reasoning](../03-automated-reasoning/README.md).

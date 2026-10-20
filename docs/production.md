# From the course to production

The course runs everything locally so you can see every moving part. Here's what
changes when the guardrails have to hold for real.

| In the course | In production |
|---|---|
| `guard.py` hook replays the whole trace with Dogwood's reference interpreter on every call | an enforcement point that keeps temporal state incrementally, such as Amazon Bedrock AgentCore Policy (which supports Dogwood) in front of an AgentCore Gateway |
| tool calls classified from free-form shell commands | agents call **typed tools** (MCP) through a gateway, so the action and its arguments are explicit |
| principal is a fixed name (`claude`) | principal attributes come from the caller's identity token (JWT claims), which the LLM cannot alter |
| per-session trace files under `~/.cache` | durable, append-only event log with ingestion timestamps (see the Dogwood guide on ordering and delayed events) |
| `cedar symcc` run by hand and in CI | the same analyses run when policies change; AgentCore Policy validates generated policies and reports dead, blanket and conflicting rules and change impact |
| hooks in `.claude/settings.json` | add org-managed settings users cannot override, OS sandboxing, and network egress controls, so the hook is one layer of several |

## Things the reference interpreter tells you it doesn't do

From the Dogwood README: the reference interpreter exists to pin down semantics
and is **not** intended as an authorization engine. A production engine has to
handle concurrency and atomicity of decide-then-execute, durable state,
performance as traces grow, and the ordering and delivery of events (a late
`Revoke` notice can turn a deny into an allow; see the guide's evaluation
semantics).

## Things to keep from the course

- **Policies are code; properties are tests that cover everything.** Keep
  `properties.toml`-style theorems next to policies and run them in CI.
- **Mutation-test your properties.** A property that accepts a known-bad
  policy set proves nothing.
- **Count requests, not responses,** when concurrency could let calls slip past a limit.
- **Keep invariants as forbids,** even when they're redundant today.
- **Review evidence, not just diffs.** A PR that changes a policy should show
  which properties were re-proved, plus any new counterexamples.

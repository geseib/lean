# Module 0 — Orientation: agents in the lifecycle, and why we prove things

> **You will leave this module able to** explain where an AI agent acts in the
> product, software and agent lifecycles, why prompts and code review alone
> cannot govern it, and which tool in this course answers which question.
> Time: 30 minutes. No installs needed.

## 1. Three lifecycles, one loop

| Lifecycle | Question it answers | In an agentic org, an agent… |
|---|---|---|
| **PDLC**: product development | *What should we build, and why?* | drafts `intent.md` and `spec.md` from conversations, tickets and research |
| **SDLC**: software development | *How do we build it safely?* | writes `plan.md`, code, tests and PRs; reviews other agents' PRs |
| **ADLC**: the agentic lifecycle | *How do we build, evaluate, ship and govern the agents themselves, and the software they make?* | runs in CI, deploys, watches production, files the next `intent.md` |

Anthropic's [AI-native SDLC playbook](https://claude.com/resources/articles/the-ai-native-sdlc-playbook)
describes the loop this course is built around. **Every stage commits a
version-controlled artifact that the next stage reads**, and humans own the
judgment calls:

```
 intent.md ──▶ spec.md ──▶ plan.md ──▶ code + tests ──▶ PR + review ──▶ deploy ──▶ monitor
  (PO accepts)  (PO approves) (lead approves)  (agent)      (human ≠ author)  (release mgr)   │
      ▲                                                                                     │
      └──────────────────────── findings become the next intent.md ◀────────────────────────┘
```

A note on names: "ADLC" is not an Anthropic term. Anthropic says *AI-native
SDLC* or *agentic SDLC*. Here, **ADLC** names both halves of the same loop:
software developed *by* agents, and the development lifecycle *of* agents
(design → evals → deploy → govern → improve).

## 2. Why agents need guardrails you can prove

A coding agent is fast, capable, and **untrusted** in the security sense:

* It can be **prompt-injected**. A README, a web page or an issue comment can
  carry instructions.
* It acts through **tools**: shell, git, HTTP, deploy scripts. The tool call is
  where harm happens, so the tool call is where control must sit.
* It acts in **sequences**. "Read a secret" is fine. "Fetch a URL" is fine.
  "Read a secret, *then* fetch a URL" is the exfiltration half of what Simon
  Willison calls the *lethal trifecta*: private data, untrusted content and
  outbound communication in one agent.

The AWS team behind Amazon Bedrock AgentCore Policy puts it bluntly: treat the
LLM as an untrusted actor and enforce authorization **outside** it, at a
deterministic checkpoint ([AWS Security Blog](https://aws.amazon.com/blogs/security/why-policy-in-amazon-bedrock-agentcore-chose-cedar-for-securing-agentic-workflows/)).
A system prompt that says "never deploy to prod" is a *request*. A policy the
gateway enforces is a *guarantee*. And a guarantee is only as good as your
evidence that the policy says what you think it says.

## 3. The ladder: four tools, four questions

```
          ┌──────────────────────────────────────────────────────────────┐
  rung 4  │ Lean          Is the *system* right? Is the authorizer sound,│  proofs checked by
          │               the monitor correct, the lifecycle gated?      │  a tiny kernel
          ├──────────────────────────────────────────────────────────────┤
  rung 3  │ Automated     Do my policies mean what I think, for EVERY    │  SMT solver:
          │ reasoning     request? (cedar symcc, cvc5, z3)               │  proof or counterexample
          ├──────────────────────────────────────────────────────────────┤
  rung 2  │ Dogwood       May this happen *given what already happened*? │  runtime monitor
          │               (since, formerly, counts, sums over history)   │  over the event trace
          ├──────────────────────────────────────────────────────────────┤
  rung 1  │ Cedar         May this principal take this action on this    │  point-in-time
          │               resource, right now?                           │  authorization
          └──────────────────────────────────────────────────────────────┘
  capstone: all four guarding a real Claude Code session, wired into CI
```

* **[Cedar](https://www.cedarpolicy.com/)** is AWS's open-source authorization
  language. Deny by default; `forbid` beats `permit`. AgentCore Policy enforces
  it on every agent tool call that goes through the gateway.
* **[Dogwood](https://github.com/dogwood-policy/dogwood)** extends Cedar with
  temporal conditions, so a policy can look back over the agent's own history.
  Any Cedar policy is already a Dogwood policy ([AWS Open Source Blog](https://aws.amazon.com/blogs/opensource/introducing-dogwood-runtime-verification-for-ai-agents/)).
* **Automated reasoning** turns "I tested 12 requests" into "I proved it for
  all of them". Cedar's symbolic compiler (SymCC) encodes policies as logic, and
  an SMT solver (cvc5) finds a counterexample or proves none exists.
* **[Lean](https://lean-lang.org/)** is a proof assistant. Cedar's semantics
  and SymCC's soundness are proved in Lean
  ([cedar-spec](https://github.com/cedar-policy/cedar-spec)). You'll write
  the same kind of proofs about a mini-Cedar, a mini-Dogwood monitor, and the
  whole lifecycle.

> **If you know OPA/Rego:** OPA is a general engine over arbitrary JSON.
> Cedar is deliberately small (no loops, no I/O, a typed schema), and that is
> exactly what lets a solver *prove* things about every request (rung 3). OPA
> is also stateless per query; Dogwood makes the agent's history an input.
> The full mapping is in [docs/for-rego-users.md](../../docs/for-rego-users.md).

Each rung answers a question the rung below cannot:

| You want to know… | Testing | Cedar | Dogwood | SMT (symcc) | Lean |
|---|:-:|:-:|:-:|:-:|:-:|
| "Is *this* request allowed?" | ✓ | ✓ | ✓ | | |
| "…given the session's history?" | | | ✓ | | |
| "Is *any* request a violation?" | | | | ✓ | ✓ |
| "Is the analyzer / monitor itself right?" | | | | | ✓ |

> **Honesty box.** Dogwood's temporal conditions are not yet covered by Cedar's
> automated-reasoning tools (AWS says so in the launch post), and Dogwood's
> repository is a *reference interpreter*, not a production engine. This
> course uses each tool where it is strong: SymCC proves the point-in-time layer,
> replayed traces exercise the temporal layer, and Lean proves the temporal
> *monitor algorithm* correct in module 4.

## 4. Meet Orchard

Every module uses one world: **Orchard**, a fictional software org whose work
is done by agents and gated by humans.

| Who | Kind | Stage | Does |
|---|---|---|---|
| `planner` | agent | PDLC | drafts intent and spec |
| `coder` | agent | SDLC | writes code, pushes branches, opens PRs |
| `reviewer` | agent | SDLC | comments on PRs (may **not** approve) |
| `deployer` | agent | ops | ships to dev and staging (**never** prod) |
| `priya` | human, ProductOwner | | accepts intent, approves specs |
| `sam`, `lee` | humans, CodeOwners | | approve plans and PRs (never their own) |
| `rel` | human, ReleaseManager | | ships prod |

The Cedar schema is [`modules/01-cedar/world/schema.cedarschema`](../01-cedar/world/schema.cedarschema).
The agent's MCP tool manifest, which Dogwood turns into a schema, is
[`modules/02-dogwood/world/tools.json`](../02-dogwood/world/tools.json).

## ✅ Check yourself

Answer each question before you open its answer.

<details><summary>1. Why isn't "never deploy to production" in the agent's system prompt enough?</summary>

The prompt is input to an untrusted, injectable component. It changes what the
agent probably does, not what it *can* do. Enforcement has to sit outside the
model, at the tool-call boundary, where a deterministic engine decides.
</details>

<details><summary>2. Name a rule that plain Cedar cannot express but Dogwood can.</summary>

Anything about history: "merge only if tests passed with no push since", "no
web requests after this session read a secret", "at most 2 prod deploy attempts
per hour". Cedar sees one request and its context, not the trace.
</details>

<details><summary>3. You tested 50 requests and the policy did the right thing on all of them. What can an SMT solver add?</summary>

A statement about *all* requests and entity stores (the typed data about
principals and resources, like OPA's `data`), including ones nobody
thought to test (a tier named `""`, a risk score of 2⁶²). It returns a proof or
a concrete counterexample.
</details>

<details><summary>4. If the solver proves the property, why would anyone also want Lean?</summary>

To trust the thing doing the proving: that the policy-to-logic encoding is
faithful, the authorizer's semantics are what we think, and the runtime monitor
computes the temporal logic correctly. Lean's kernel checks those proofs.
</details>

**Next:** [Module 1 — Cedar](../01-cedar/README.md). Before you start, run
`./course doctor` from the repo root.

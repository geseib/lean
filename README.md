# Proof-Carrying Agents

**A hands-on course in Cedar, Dogwood, Lean and automated reasoning, for
governing AI agents across the product, software and agentic lifecycles.**

Agents now write the spec, the code, the tests and the deploy. This course
teaches you to put them under guardrails you can **prove**. It follows the way
AWS secures agent tool calls with Cedar in Amazon Bedrock AgentCore Policy, and
extends it to agent *histories* with Dogwood. It shows how AWS uses Lean and SMT
solvers to trust all of it, and it applies everything to a live Claude Code
session.

```
  rung 4  Lean                  is the system right?          ── proofs checked by a kernel
  rung 3  automated reasoning   right for EVERY request?      ── cedar symcc + cvc5 / z3
  rung 2  Dogwood               allowed, given the history?   ── runtime monitor over traces
  rung 1  Cedar                 allowed, right now?           ── point-in-time authorization
  ─────── capstone: all four guarding a real Claude Code session, proved in CI ───────
```

Every lesson is something you **run**: 18 katas, each checked by the real
tool (the Cedar CLI, Cedar's symbolic compiler with cvc5, the Dogwood
interpreter, the Lean kernel). Hints unlock one at a time, and your progress is
tracked.

## Start here

```bash
git clone <this repo> && cd lean
./scripts/setup.sh        # Cedar (+symcc), Dogwood, cvc5/z3, Lean
./course doctor           # confirms every tool, with a fix for anything missing
./course status           # your ladder
```

Then read [Module 0](modules/00-orientation/README.md) (30 min, no installs).

## How a rung works

Each module README follows the same rhythm: **why** (a real way agents go
wrong), **the idea** (one picture), **a worked example** you run, **katas**, and
**✅ Check yourself** questions with hidden answers. You move up when you can
answer them.

```bash
./course check cedar/c1            # ✓/✗ for every test, with the policy that decided it
./course hint  cedar/c1            # the next hint (they unlock one at a time)
./course check cedar/c1 --solution # watch the reference pass
```

## The ladder

| Module | You learn to… | Katas |
|---|---|---|
| [0 · Orientation](modules/00-orientation/README.md) | place agents in the PDLC / SDLC / ADLC loop; pick the right tool for each question | — |
| [1 · Cedar](modules/01-cedar/README.md) | write permits and forbids for an agent fleet; let the validator catch an LLM's mistakes | `cedar/c1`–`c4` |
| [2 · Dogwood](modules/02-dogwood/README.md) | write history-aware guardrails (`since`, `formerly`, counts, sums); survive concurrency | `dogwood/k1`–`k3` |
| [3 · Automated reasoning](modules/03-automated-reasoning/README.md) | build an analyzer from scratch; prove properties with `cedar symcc`; read counterexamples; lint generated policies | `reasoning/r0`–`r5` |
| [4 · Lean](modules/04-lean/README.md) | prove a mini-Cedar sound, a Dogwood-style monitor correct, and the lifecycle's human gates unavoidable | `lean/e1`–`e4` |
| [5 · Capstone](modules/05-capstone/README.md) | enforce Cedar + Dogwood on a live Claude Code session; run a feature from `intent.md` to deploy with proofs at each gate | `capstone/x1` |

## The world you'll govern

**Orchard** is a fictional org. A `planner` agent writes intent and specs, a
`coder` builds, a `reviewer` critiques, a `deployer` ships. Humans hold the
gates: `priya` (product owner), `sam` and `lee` (code owners), `rel` (release
manager).
[Schema](modules/01-cedar/world/schema.cedarschema) ·
[policies](modules/01-cedar/world/policies.cedar) ·
[agent tool manifest](modules/02-dogwood/world/tools.json).

## Repository map

```
course                         the runner: doctor · status · list · check · hint · verify
modules/00-orientation/        lifecycles, threat model, the ladder
modules/01-cedar/              world/ (schema, entities, reference policies) + katas
modules/02-dogwood/            world/ (MCP tools → schema), bundles/ d1–d6, katas
modules/03-automated-reasoning katas r0 (z3 from scratch) – r5 (symcc)
modules/04-lean/               Lake project: Course/ lessons, Exercises/, Solutions/
modules/05-capstone/           guard/ (Claude Code hook), .claude/settings.json, feature-ship-gate/
tools/                         dwtrace.py (compact traces), cvc5-py (cvc5 for SymCC), z3-as-cvc5
docs/                          setup, production notes, sources
scripts/check-all.sh           everything CI runs
```

## Sources this course builds on

- AWS, [Introducing Dogwood: runtime verification for AI agents](https://aws.amazon.com/blogs/opensource/introducing-dogwood-runtime-verification-for-ai-agents/), and the [Dogwood repository and guide](https://github.com/dogwood-policy/dogwood)
- AWS, [Why Policy in Amazon Bedrock AgentCore chose Cedar for securing agentic workflows](https://aws.amazon.com/blogs/security/why-policy-in-amazon-bedrock-agentcore-chose-cedar-for-securing-agentic-workflows/)
- [Cedar](https://www.cedarpolicy.com/), [cedar-spec (Lean)](https://github.com/cedar-policy/cedar-spec), and [cedar-policy-symcc](https://crates.io/crates/cedar-policy-symcc)
- Anthropic, [The AI-native SDLC playbook](https://claude.com/resources/articles/the-ai-native-sdlc-playbook)
- [Lean 4](https://lean-lang.org/), [Claude Code hooks](https://code.claude.com/docs/en/hooks)

More detail: [docs/setup.md](docs/setup.md) · [docs/production.md](docs/production.md).

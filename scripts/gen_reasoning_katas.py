"""One-off generator for modules/03-automated-reasoning/katas (kept for maintainers).

The katas are ordinary files once generated; edit them directly afterwards.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = (ROOT / "modules/01-cedar/world/policies.cedar").read_text()
K = ROOT / "modules/03-automated-reasoning/katas"

A = 'Orchard::Agent'
H = 'Orchard::Human'


def act(a):
    return f'Orchard::Action::"{a}"'


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.lstrip("\n"))


def toml_str(s):
    return json.dumps(s)


def kata_toml(kid, title, hints, extra=""):
    hs = ",\n".join("  " + toml_str(h) for h in hints)
    return f'id = "{kid}"\ntitle = {toml_str(title)}\ntype = "symcc"\nworld = "01-cedar/world"\n{extra}hints = [\n{hs},\n]\n'


def drop(text, start_marker, end_marker):
    i, j = text.index(start_marker), text.index(end_marker)
    return text[:i] + text[j:]


def test(name, p, a, r, d, ctx=None):
    t = {"name": name, "principal": p, "action": act(a), "resource": r, "decision": d}
    if ctx is not None:
        t["context"] = ctx
    return t


# ---------------------------------------------------------------- r1 ----
r1 = K / "r1-prove-the-constitution"
write(r1 / "policies.cedar", "// A copy of modules/01-cedar/world/policies.cedar — the system under proof.\n" + REF)
hotfix = drop(REF, "// Agents act up to the production gate", '@id("agents-never-read-restricted-secrets")') + '''
@id("hotfix-fast-lane")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { context.riskScore < 2 };
'''
write(r1 / "mutants/m1-hotfix-reaches-prod.cedar", "// MUTANT: the prod forbid was 'cleaned up' and a fast lane added.\n" + hotfix)
write(r1 / "mutants/m2-agents-push-main.cedar", "// MUTANT: the protected-branch check was lost.\n" + REF.replace(
    'when { principal.trust >= 1 }\nunless { resource.protectedBranches.contains(context.branch) };',
    'when { principal.trust >= 1 };'))
write(r1 / "mutants/m3-product-owner-ships-prod.cedar", "// MUTANT: product owners were added to the release permit.\n" + REF.replace(
    'permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource);',
    'permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource);\n\n'
    '@id("product-owners-deploy-too")\npermit (principal in Orchard::Role::"ProductOwner", action == Orchard::Action::"deploy", resource);'))
write(r1 / "mutants/m4-reviewer-agent-approves.cedar", "// MUTANT: 'the AI reviewer is good now, let it approve'.\n" + drop(
    REF, "// The agent that writes code cannot approve it", "// The human driving a PR") + '''
@id("ai-reviewer-approves")
permit (principal is Orchard::Agent, action == Orchard::Action::"approvePR", resource)
when { principal.trust >= 3 };
''')
starter = "// TODO: replace this vacuous bound. As written it allows *everything*, so\n// policies.cedar trivially implies it — and so does every buggy mutant.\npermit (principal, action, resource);\n"
for name in ["no-agent-deploys-prod", "agents-push-unprotected-only", "only-release-managers-ship-prod"]:
    write(r1 / f"bounds/{name}.cedar", starter)
write(r1 / "solution/bounds/no-agent-deploys-prod.cedar", '''
// For requests (Agent, deploy, Environment): allowed ⇒ the tier is not prod.
permit (principal, action, resource)
unless { resource.tier == "prod" };
''')
write(r1 / "solution/bounds/agents-push-unprotected-only.cedar", '''
// For requests (Agent, pushBranch, Repo): allowed ⇒ the branch is unprotected.
permit (principal, action, resource)
unless { resource.protectedBranches.contains(context.branch) };
''')
write(r1 / "solution/bounds/only-release-managers-ship-prod.cedar", '''
// For requests (Human, deploy, Environment): allowed ⇒ below prod, or a release manager.
permit (principal, action, resource)
when { resource.tier != "prod" };

permit (principal in Orchard::Role::"ReleaseManager", action, resource);
''')
write(r1 / "properties.toml", f'''
# Each [[property]] is one theorem about policies.cedar, checked by
# `cedar symcc` for EVERY possible request and entity store of that type.
# `must_reject` lists mutant policy sets the property has to catch:
# a property that cannot tell a bug from the real thing proves nothing.

[[property]]
name = "No agent ever deploys to prod"
check = "implies"
principal = "{A}"
action = '{act("deploy")}'
resource = "Orchard::Environment"
policies = "policies.cedar"
other = "bounds/no-agent-deploys-prod.cedar"
must_reject = ["mutants/m1-hotfix-reaches-prod.cedar"]

[[property]]
name = "Agents push only to unprotected branches"
check = "implies"
principal = "{A}"
action = '{act("pushBranch")}'
resource = "Orchard::Repo"
policies = "policies.cedar"
other = "bounds/agents-push-unprotected-only.cedar"
must_reject = ["mutants/m2-agents-push-main.cedar"]

[[property]]
name = "Among humans, only release managers ship prod"
check = "implies"
principal = "{H}"
action = '{act("deploy")}'
resource = "Orchard::Environment"
policies = "policies.cedar"
other = "bounds/only-release-managers-ship-prod.cedar"
must_reject = ["mutants/m3-product-owner-ships-prod.cedar"]

[[property]]
name = "No agent ever approves a PR (given to you)"
check = "always-denies"
principal = "{A}"
action = '{act("approvePR")}'
resource = "Orchard::PullRequest"
policies = "policies.cedar"
must_reject = ["mutants/m4-reviewer-agent-approves.cedar"]
''')
write(r1 / "kata.toml", kata_toml("reasoning/r1", "Prove the constitution: write the properties, catch the mutants", [
    "A property `P implies B` says: every request P allows, B also allows. So B is the 'envelope' of what is acceptable.",
    "Write each bound as a permit over (principal, action, resource) with a `when`/`unless` that states the safe region, e.g. `unless { resource.tier == \"prod\" }`.",
    "A bound may contain several permits; their union is the envelope. For release managers: one permit below prod, one for the ReleaseManager role.",
]))

# ---------------------------------------------------------------- r2 ----
r2 = K / "r2-the-hotfix-regression"
write(r2 / "policies.cedar", "// Production incident review: this policy set shipped last Friday.\n" + hotfix)
write(r2 / "solution/policies.cedar", "// Fixed: the fast lane is confined to staging, and the prod forbid is back.\n" + REF + '''
@id("hotfix-fast-lane")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { context.riskScore < 2 && resource.tier == "staging" };
''')
write(r2 / "bounds/no-agent-deploys-prod.cedar", "permit (principal, action, resource)\nunless { resource.tier == \"prod\" };\n")
write(r2 / "properties.toml", f'''
[[property]]
name = "No agent ever deploys to prod"
check = "implies"
principal = "{A}"
action = '{act("deploy")}'
resource = "Orchard::Environment"
policies = "policies.cedar"
other = "bounds/no-agent-deploys-prod.cedar"
''')
ctx = lambda r: {"change": "hf-7", "riskScore": r}
json_tests = [
    test("coder hotfixes staging at low risk", f'{A}::"coder"', "deploy", 'Orchard::Environment::"staging"', "allow", ctx(1)),
    test("coder may not hotfix staging at high risk", f'{A}::"coder"', "deploy", 'Orchard::Environment::"staging"', "deny", ctx(5)),
    test("coder may not hotfix prod", f'{A}::"coder"', "deploy", 'Orchard::Environment::"prod"', "deny", ctx(1)),
    test("deployer still ships staging normally", f'{A}::"deployer"', "deploy", 'Orchard::Environment::"staging"', "allow", ctx(7)),
    test("rel still ships prod", f'{H}::"rel"', "deploy", 'Orchard::Environment::"prod"', "allow", ctx(3)),
]
write(r2 / "tests.json", json.dumps(json_tests, indent=1) + "\n")
write(r2 / "kata.toml", kata_toml("reasoning/r2", "The hotfix regression: read a counterexample, fix the policy", [
    "Run the check and read the counterexample: what tier, what riskScore, which principal?",
    "Two independent fixes both work: confine the fast lane to staging, or restore the `agents-never-deploy-prod` forbid. Doing both is defense in depth.",
    "The tests are there so you cannot 'fix' the proof by deleting the fast lane; low-risk staging hotfixes must keep working.",
], 'policies = "policies.cedar"\n'))

# ---------------------------------------------------------------- r3 ----
r3 = K / "r3-the-forbid-that-wasnt"
gate_bad = '''
@id("ops-deploys")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier != "prod" };

// "Weighted risk": refuse deploys whose risk, scaled by 1000, exceeds 5000.
@id("risk-gate")
forbid (principal, action == Orchard::Action::"deploy", resource)
when { context.riskScore * 1000 > 5000 };
'''
write(r3 / "policies.cedar", gate_bad)
write(r3 / "solution/policies.cedar", gate_bad.replace(
    '// "Weighted risk": refuse deploys whose risk, scaled by 1000, exceeds 5000.\n',
    '// Same threshold, no multiplication: riskScore * 1000 > 5000  ⟺  riskScore > 5,\n// but the left side can overflow and the right side cannot.\n').replace(
    "context.riskScore * 1000 > 5000", "context.riskScore > 5"))
write(r3 / "properties.toml", f'''
[[property]]
name = "The risk gate never errors"
check = "never-errors"
principal = "{A}"
action = '{act("deploy")}'
resource = "Orchard::Environment"
policies = "policies.cedar"
policy_id = "risk-gate"
''')
write(r3 / "tests.json", json.dumps([
    test("risk 3 ships", f'{A}::"deployer"', "deploy", 'Orchard::Environment::"staging"', "allow", ctx(3)),
    test("risk 9 is refused", f'{A}::"deployer"', "deploy", 'Orchard::Environment::"staging"', "deny", ctx(9)),
    test("an absurd risk is refused too", f'{A}::"deployer"', "deploy", 'Orchard::Environment::"staging"', "deny", ctx(9223372036854775807)),
], indent=1) + "\n")
write(r3 / "kata.toml", kata_toml("reasoning/r3", "The forbid that wasn't: errors are skipped, so prove they can't happen", [
    "Run the check. One test fails: the largest risk score is ALLOWED. The yellow line says why.",
    "Cedar skips a policy whose condition errors. For a forbid, 'skipped' means 'does not deny'.",
    "Rewrite the condition so it cannot overflow but keeps the same threshold: riskScore * 1000 > 5000 is the same as riskScore > 5.",
], 'policies = "policies.cedar"\n'))

# ---------------------------------------------------------------- r4 ----
r4 = K / "r4-refactor-without-fear"
original = '''
// The original, grown-by-accretion deploy policies. Do not edit this file:
// it is the specification your refactor must match exactly.
@id("ops-dev")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier == "dev" };

@id("ops-staging")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier == "staging" };

@id("trusted-sdlc-dev")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "sdlc" && principal.trust >= 2 && resource.tier == "dev" };

@id("rm-dev")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource)
when { resource.tier == "dev" };

@id("rm-staging")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource)
when { resource.tier == "staging" };

@id("rm-prod")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource)
when { resource.tier == "prod" };
'''
write(r4 / "original.cedar", original)
write(r4 / "policies.cedar", '''
// An agent's refactor of original.cedar into two policies. It reads well, and
// every example test anyone thought of passes. Is it *equivalent*?
@id("agents-deploy")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when {
  (principal.stage == "ops" && resource.tier != "prod") ||
  (principal.stage == "sdlc" && principal.trust > 2 && resource.tier == "dev")
};

@id("release-managers-deploy")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource);
''')
write(r4 / "solution/policies.cedar", '''
// Equivalent to original.cedar for every request, proved by cedar symcc.
// `tier` is an open String: "qa" is a tier too, so say exactly which tiers.
@id("agents-deploy")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when {
  (principal.stage == "ops" && ["dev", "staging"].contains(resource.tier)) ||
  (principal.stage == "sdlc" && principal.trust >= 2 && resource.tier == "dev")
};

@id("release-managers-deploy")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource)
when { ["dev", "staging", "prod"].contains(resource.tier) };
''')
props = ""
for ptype in [A, H]:
    who = "agents" if ptype == A else "humans"
    props += f'''
[[property]]
name = "Refactor is equivalent for {who}"
check = "equivalent"
principal = "{ptype}"
action = '{act("deploy")}'
resource = "Orchard::Environment"
policies = "policies.cedar"
other = "original.cedar"
'''
write(r4 / "properties.toml", props)
write(r4 / "kata.toml", kata_toml("reasoning/r4", "Refactor without fear: prove the new policies equivalent", [
    "Read each counterexample: the solver picks values no test author thought of, like tier \"\" or trust 2.",
    "In the schema `tier` is a String, not an enum. `tier != \"prod\"` admits every other string; the original admits exactly dev and staging.",
    "Use set membership to say exactly which tiers: `[\"dev\", \"staging\"].contains(resource.tier)`. Check `>` against `>=` too.",
]))

# ---------------------------------------------------------------- r5 ----
r5 = K / "r5-lint-the-llm-draft"
write(r5 / "policies.cedar", '''
// An LLM translated these natural-language requirements into Cedar. Each
// policy validates against the schema, but automated reasoning finds three
// of the problems AgentCore Policy reports on generated policies.
//
// Intent 1: product owners approve intent or spec documents.
@id("po-approves-docs")
permit (principal in Orchard::Role::"ProductOwner", action == Orchard::Action::"approveArtifact", resource)
when { resource.kind == "intent" && resource.kind == "spec" };

// Intent 2: trusted agents (trust 2 or more) push to unprotected branches.
@id("trusted-agents-push")
permit (principal is Orchard::Agent, action == Orchard::Action::"pushBranch", resource)
when { principal.trust >= 2 || principal.trust < 2 };

// Intent 3: ops agents may read secrets that are not restricted.
@id("ops-reads-secrets")
permit (principal is Orchard::Agent, action == Orchard::Action::"readSecret", resource)
when { principal.stage == "ops" };

// Intent 4: no agent may read a restricted secret.
@id("no-agent-restricted-secrets")
forbid (principal is Orchard::Agent, action == Orchard::Action::"readSecret", resource)
when { resource.classification == "restricted" || principal is Orchard::Agent };
''')
write(r5 / "solution/policies.cedar", '''
// Intent 1: product owners approve intent or spec documents.
@id("po-approves-docs")
permit (principal in Orchard::Role::"ProductOwner", action == Orchard::Action::"approveArtifact", resource)
when { resource.kind == "intent" || resource.kind == "spec" };

// Intent 2: trusted agents (trust 2 or more) push to unprotected branches.
@id("trusted-agents-push")
permit (principal is Orchard::Agent, action == Orchard::Action::"pushBranch", resource)
when { principal.trust >= 2 }
unless { resource.protectedBranches.contains(context.branch) };

// Intent 3: ops agents may read secrets that are not restricted.
@id("ops-reads-secrets")
permit (principal is Orchard::Agent, action == Orchard::Action::"readSecret", resource)
when { principal.stage == "ops" };

// Intent 4: no agent may read a restricted secret.
@id("no-agent-restricted-secrets")
forbid (principal is Orchard::Agent, action == Orchard::Action::"readSecret", resource)
when { resource.classification == "restricted" };
''')
write(r5 / "properties.toml", f'''
# Lints, AgentCore-style. "fails" means the bad thing is NOT the case.

[[property]]
name = "po-approves-docs can match some request (it is not dead)"
check = "never-matches"
expect = "fails"
principal = "{H}"
action = '{act("approveArtifact")}'
resource = "Orchard::Artifact"
policies = "policies.cedar"
policy_id = "po-approves-docs"

[[property]]
name = "trusted-agents-push is not a blanket grant"
check = "always-matches"
expect = "fails"
principal = "{A}"
action = '{act("pushBranch")}'
resource = "Orchard::Repo"
policies = "policies.cedar"
policy_id = "trusted-agents-push"

[[property]]
name = "ops-reads-secrets is not completely shadowed by the forbid"
check = "matches-implies"
expect = "fails"
principal = "{A}"
action = '{act("readSecret")}'
resource = "Orchard::Secret"
policies = "policies.cedar"
policy_id = "ops-reads-secrets"
other = "policies.cedar"
other_policy_id = "no-agent-restricted-secrets"
''')
write(r5 / "tests.json", json.dumps([
    test("priya approves a spec", f'{H}::"priya"', "approveArtifact", 'Orchard::Artifact::"dark-mode/spec.md"', "allow"),
    test("priya does not approve a plan", f'{H}::"priya"', "approveArtifact", 'Orchard::Artifact::"dark-mode/plan.md"', "deny"),
    test("coder pushes a feature branch", f'{A}::"coder"', "pushBranch", 'Orchard::Repo::"web-app"', "allow", {"branch": "feat/x"}),
    test("coder may not push main", f'{A}::"coder"', "pushBranch", 'Orchard::Repo::"web-app"', "deny", {"branch": "main"}),
    test("intern-bot (trust 0) may not push", f'{A}::"intern-bot"', "pushBranch", 'Orchard::Repo::"web-app"', "deny", {"branch": "feat/x"}),
    test("deployer reads the internal CI token", f'{A}::"deployer"', "readSecret", 'Orchard::Secret::"ci-token"', "allow"),
    test("deployer may not read the restricted deploy token", f'{A}::"deployer"', "readSecret", 'Orchard::Secret::"deploy-token"', "deny"),
    test("coder (sdlc) may not read secrets", f'{A}::"coder"', "readSecret", 'Orchard::Secret::"ci-token"', "deny"),
], indent=1) + "\n")
write(r5 / "kata.toml", kata_toml("reasoning/r5", "Lint an LLM's draft: dead, blanket, and shadowed policies", [
    "A condition that requires kind to equal two different strings at once can never be true: that is what `never-matches` proves.",
    "`x >= 2 || x < 2` is true for every x, so the policy matches every request. The intent also mentions protected branches.",
    "`... || principal is Orchard::Agent` makes the forbid cover every agent request, so it shadows the ops permit completely. Keep only the restricted clause.",
], 'policies = "policies.cedar"\n'))
print("generated", sorted(p.name for p in K.iterdir()))

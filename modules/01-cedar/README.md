# Module 1 — Cedar: who may do what, right now

> **You will leave this module able to** read and write Cedar policies for an
> agent fleet, use the validator to catch an LLM's policy mistakes, and explain
> why `forbid` + deny-by-default is the right shape for agent guardrails.
> Katas: `cedar/c1` – `cedar/c4`. Time: about 90 minutes.

## 1. The mental model in one picture

Every tool call an agent makes becomes a **request**:

```
   principal          action               resource              context
 Agent::"coder"  ─  Action::"pushBranch"  ─  Repo::"web-app"  ─  { branch: "main" }
        │                                        │
        └─ attributes & groups come from the ────┘── entity store (JSON), never from the LLM
```

The authorizer evaluates every policy against the request:

0. A policy whose condition **errors** (integer overflow, for example) is
   **skipped**, as if it weren't there.
1. If **any `forbid`** is satisfied → **DENY**.
2. Else if **any `permit`** is satisfied → **ALLOW**.
3. Else → **DENY** (deny by default).

That is the entire decision procedure; module 4 defines it in Lean and proves
its properties. Order never matters, and no permit can override a satisfied
forbid. Step 0 is the catch: a forbid that *errors* denies nothing. Keep it in
mind until kata `reasoning/r3`, where it bites.

> **If you know Rego:** this is `default allow := false` plus a combinator
> you'd normally write yourself (`allow if { permit; count(deny) == 0 }`),
> built in and fixed. `forbid` is your `deny[msg]` without the message: Cedar
> reports the *ids* of the policies that decided. Step 0 is Rego's
> "a builtin error makes the rule undefined", except Cedar has no strict mode;
> you prove the absence of errors instead (module 3). More in
> [docs/for-rego-users.md](../../docs/for-rego-users.md).

## 2. Anatomy of a policy

```cedar
@id("agents-push-unprotected-branches")                         // a name for audit logs
permit (                                                        // effect
  principal is Orchard::Agent,                                  // scope: type test
  action == Orchard::Action::"pushBranch",                      // scope: exact action
  resource                                                      // scope: any resource
)
when   { principal.trust >= 1 }                                 // all `when`s must hold
unless { resource.protectedBranches.contains(context.branch) }; // no `unless` may hold
```

* **Scope** filters cheaply: `principal is T`, `principal == E`, `principal in Group`, `action in [...]`.
* **Conditions** read attributes (`principal.stage`), context (`context.branch`),
  sets (`.contains`), hierarchy (`principal in Orchard::Role::"CodeOwner"`,
  which is transitive, like `graph.reachable`), and optional attributes
  (`context.input has branch && …`; reading a missing attribute is a validation
  error, not Rego's "undefined").
* **Entities are data you control.** In AgentCore Policy, principal attributes
  come from the caller's identity token, and `context.input` comes from the
  tool call the LLM made. Know which is which: the LLM can choose `context.input`,
  but it cannot choose `principal.trust`.

## 3. Worked example: Orchard's constitution

Read [`world/policies.cedar`](world/policies.cedar). It's short. Notice the pattern:

* **Permits** open narrow doors: "ops agents deploy below prod".
* **Forbids** state **invariants**, the things that must never happen whatever
  else gets permitted later: "agents never approve", "agents never deploy prod".

Try it with the real CLI:

```bash
cd modules/01-cedar/world
echo '{"change":"c1","riskScore":3}' > /tmp/ctx.json
cedar authorize --schema schema.cedarschema --policies policies.cedar --entities entities.json \
  -l 'Orchard::Agent::"deployer"' -a 'Orchard::Action::"deploy"' -r 'Orchard::Environment::"prod"' \
  -c /tmp/ctx.json -v
# DENY — note: this decision was due to the following policies: agents-never-deploy-prod
```

Change `prod` to `staging` and run it again. Then try `Orchard::Human::"rel"` on prod.

## 4. The validator: your first line of automated reasoning

When an LLM writes your policies (AgentCore Policy can generate Cedar from
natural language), the **first** check is schema validation. It is a type
checker that rejects misspelled attributes, wrong types and missing context
fields **before** a policy ever runs:

```bash
cedar validate --schema world/schema.cedarschema --policies my.cedar
```

Kata `cedar/c4` hands you an LLM-drafted policy set with three such bugs.

## 5. Your katas

```bash
./course check cedar/c1       # run your work through cedar validate + authorization tests
./course hint  cedar/c1       # stuck? hints unlock one at a time
./course check cedar/c1 --solution   # see the reference pass
```

| Kata | You'll practice |
|---|---|
| `cedar/c1` First permits | scope, `is`, `in`, attributes, `||` |
| `cedar/c2` Separation of duties | `forbid`, entity equality, context booleans and numbers |
| `cedar/c3` The production gate | narrowing a blanket permit; defense-in-depth forbids |
| `cedar/c4` The validator catches typos | reading validator errors on LLM-generated policies |

Edit the `policy.cedar` in each `katas/<kata>/` folder. The tests (`tests.json`)
run against the shared Orchard entities in `world/entities.json`.

## ✅ Check yourself

<details><summary>1. A permit says agents may deploy to staging. A forbid says agents with trust 0 may not deploy. intern-bot (trust 0) deploys to staging. Decision?</summary>

**DENY.** A satisfied forbid wins over any permit, whatever order the policies
are in.
</details>

<details><summary>2. There is no policy mentioning <code>readSecret</code> at all. Can the coder read a secret?</summary>

No. With no satisfied permit the answer is DENY. This is why deny-by-default
suits agents: a new tool is closed until someone opens it.
</details>

<details><summary>3. Why write <code>agents-never-deploy-prod</code> as a forbid when no permit lets agents reach prod anyway?</summary>

Because permits accumulate. Next quarter someone adds a "hotfix fast lane"
permit. The forbid is the invariant that survives that change. Kata r1 proves
the property holds even with the forbid deleted, so it's redundant *today*.
Kata r2 shows exactly how the hotfix breaks the system once the forbid is gone.
</details>

<details><summary>4. The LLM controls the tool-call arguments. Which part of the request is that?</summary>

`context` (in AgentCore, `context.input`). Never let a security decision rest
only on a value the agent chose. Pair it with principal attributes from
identity, or with resource attributes from your own entity store. Notice that
Orchard's merge rule reads `context.ciPassed`: that is only safe because the
*gateway* computes it from CI, not from the agent's arguments. The comment in
`world/policies.cedar` says so, and the capstone shows what goes wrong when the
agent produces its own evidence.
</details>

**Next:** [Module 2 — Dogwood](../02-dogwood/README.md): what Cedar can't see.

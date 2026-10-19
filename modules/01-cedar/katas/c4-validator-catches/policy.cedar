// KATA c4 — an LLM drafted these from a natural-language request. It looks
// plausible, and Cedar would even *parse* it. But it is wrong against the schema.
// This is the first verification stage AgentCore Policy runs on generated
// policies: schema validation. Fix the bugs; keep the intent.
//
// Intent: trusted agents (trust >= 2) may push to unprotected branches;
//         ops agents may deploy below prod; merge needs green CI.

@id("trusted-agents-push")
permit (principal is Orchard::Agent, action == Orchard::Action::"pushBranch", resource)
when { principal.trust >= "2" }
unless { resource.protectedBranches.contains(context.branch) };

@id("ops-deploys-below-prod")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.teir != "prod" };

@id("merge-on-green")
permit (principal, action == Orchard::Action::"mergePR", resource)
when { context.ci_passed && context.humanApprovals >= 1 };

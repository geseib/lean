@id("trusted-agents-push")
permit (principal is Orchard::Agent, action == Orchard::Action::"pushBranch", resource)
when { principal.trust >= 2 }
unless { resource.protectedBranches.contains(context.branch) };

@id("ops-deploys-below-prod")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier != "prod" };

@id("merge-on-green")
permit (principal, action == Orchard::Action::"mergePR", resource)
when { context.ciPassed && context.humanApprovals >= 1 };

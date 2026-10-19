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

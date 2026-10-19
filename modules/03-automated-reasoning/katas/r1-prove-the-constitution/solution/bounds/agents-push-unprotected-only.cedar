// For requests (Agent, pushBranch, Repo): allowed ⇒ the branch is unprotected.
permit (principal, action, resource)
unless { resource.protectedBranches.contains(context.branch) };

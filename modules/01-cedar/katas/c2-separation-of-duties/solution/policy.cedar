@id("code-owners-approve-prs")
permit (principal in Orchard::Role::"CodeOwner", action == Orchard::Action::"approvePR", resource);

@id("anyone-on-the-team-comments")
permit (principal in Orchard::Team::"web", action == Orchard::Action::"commentPR", resource);

@id("agents-never-approve")
forbid (principal is Orchard::Agent, action == Orchard::Action::"approvePR", resource);

@id("no-self-approval")
forbid (principal is Orchard::Human, action == Orchard::Action::"approvePR", resource)
when { resource.driver == principal };

@id("merge-on-green-with-a-human-approval")
permit (principal, action == Orchard::Action::"mergePR", resource)
when { context.ciPassed && context.humanApprovals >= 1 };

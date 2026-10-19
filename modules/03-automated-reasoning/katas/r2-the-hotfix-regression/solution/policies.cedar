// Fixed: the fast lane is confined to staging, and the prod forbid is back.
// Orchard's reference policy set: the "constitution" every agent runs under.
// Cedar is deny-by-default; a forbid always beats a permit.

// ---------- PDLC: intent and spec ------------------------------------------
@id("planner-drafts-artifacts")
permit (principal is Orchard::Agent, action == Orchard::Action::"draftArtifact", resource)
when { principal.stage == "pdlc" };

@id("product-owner-approves-intent-and-spec")
permit (principal in Orchard::Role::"ProductOwner", action == Orchard::Action::"approveArtifact", resource)
when { resource.kind == "intent" || resource.kind == "spec" };

@id("code-owner-approves-plan")
permit (principal in Orchard::Role::"CodeOwner", action == Orchard::Action::"approveArtifact", resource)
when { resource.kind == "plan" };

// ---------- SDLC: build and review ------------------------------------------
@id("agents-push-unprotected-branches")
permit (principal is Orchard::Agent, action == Orchard::Action::"pushBranch", resource)
when { principal.trust >= 1 }
unless { resource.protectedBranches.contains(context.branch) };

@id("anyone-on-the-team-comments")
permit (principal in Orchard::Team::"web", action == Orchard::Action::"commentPR", resource);

@id("code-owners-approve-prs")
permit (principal in Orchard::Role::"CodeOwner", action == Orchard::Action::"approvePR", resource);

@id("merge-on-green-with-a-human-approval")
permit (principal, action == Orchard::Action::"mergePR", resource)
when { context.ciPassed && context.humanApprovals >= 1 };

// ---------- Ops: release -----------------------------------------------------
@id("agents-deploy-below-prod")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier != "prod" };

@id("release-managers-deploy")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource);

@id("humans-read-secrets")
permit (principal is Orchard::Human, action == Orchard::Action::"readSecret", resource);

// ---------- Invariants (forbids) ---------------------------------------------
// The agent that writes code cannot approve it, and no agent is an approver.
@id("agents-never-approve")
forbid (principal is Orchard::Agent, action in [Orchard::Action::"approveArtifact", Orchard::Action::"approvePR"], resource);

// The human driving a PR cannot also be its approver.
@id("no-self-approval")
forbid (principal is Orchard::Human, action == Orchard::Action::"approvePR", resource)
when { resource.driver == principal };

// Agents act up to the production gate, never through it.
@id("agents-never-deploy-prod")
forbid (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { resource.tier == "prod" };

@id("agents-never-read-restricted-secrets")
forbid (principal is Orchard::Agent, action == Orchard::Action::"readSecret", resource)
when { resource.classification == "restricted" };

@id("hotfix-fast-lane")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { context.riskScore < 2 && resource.tier == "staging" };

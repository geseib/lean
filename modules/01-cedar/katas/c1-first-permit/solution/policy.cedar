@id("planner-drafts-artifacts")
permit (principal is Orchard::Agent, action == Orchard::Action::"draftArtifact", resource)
when { principal.stage == "pdlc" };

@id("product-owner-approves-intent-and-spec")
permit (principal in Orchard::Role::"ProductOwner", action == Orchard::Action::"approveArtifact", resource)
when { resource.kind == "intent" || resource.kind == "spec" };

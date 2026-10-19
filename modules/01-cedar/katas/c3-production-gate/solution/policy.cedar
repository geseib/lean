@id("agents-deploy-below-prod")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier != "prod" };

@id("release-managers-deploy")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource);

@id("agents-never-deploy-prod")
forbid (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { resource.tier == "prod" };

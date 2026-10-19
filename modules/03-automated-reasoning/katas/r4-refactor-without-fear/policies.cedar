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

// Equivalent to original.cedar for every request, proved by cedar symcc.
// `tier` is an open String: "qa" is a tier too, so say exactly which tiers.
@id("agents-deploy")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when {
  (principal.stage == "ops" && ["dev", "staging"].contains(resource.tier)) ||
  (principal.stage == "sdlc" && principal.trust >= 2 && resource.tier == "dev")
};

@id("release-managers-deploy")
permit (principal in Orchard::Role::"ReleaseManager", action == Orchard::Action::"deploy", resource)
when { ["dev", "staging", "prod"].contains(resource.tier) };

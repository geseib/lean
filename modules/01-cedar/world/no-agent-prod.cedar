// The property "no agent ever deploys to prod", as a policy set: for requests
// (Agent, deploy, Environment), anything allowed must be outside prod.
permit (principal, action, resource) unless { resource.tier == "prod" };

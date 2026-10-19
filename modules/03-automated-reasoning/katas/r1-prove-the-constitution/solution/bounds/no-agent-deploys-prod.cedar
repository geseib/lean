// For requests (Agent, deploy, Environment): allowed ⇒ the tier is not prod.
permit (principal, action, resource)
unless { resource.tier == "prod" };

@id("ops-deploys")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier != "prod" };

// Same threshold, no multiplication: riskScore * 1000 > 5000  ⟺  riskScore > 5,
// but the left side can overflow and the right side cannot.
@id("risk-gate")
forbid (principal, action == Orchard::Action::"deploy", resource)
when { context.riskScore > 5 };

@id("ops-deploys")
permit (principal is Orchard::Agent, action == Orchard::Action::"deploy", resource)
when { principal.stage == "ops" && resource.tier != "prod" };

// "Weighted risk": refuse deploys whose risk, scaled by 1000, exceeds 5000.
@id("risk-gate")
forbid (principal, action == Orchard::Action::"deploy", resource)
when { context.riskScore * 1000 > 5000 };

// KATA c3 — the production gate.
//
// Someone shipped this "temporary" policy. Replace it so that:
//   * agents whose stage is "ops" may deploy to dev and staging,
//   * only members of the ReleaseManager role may deploy to prod,
//   * a forbid named "agents-never-deploy-prod" makes the gate explicit,
//   * nobody else may deploy anywhere.

@id("temporary-let-everyone-deploy")
permit (principal, action == Orchard::Action::"deploy", resource);

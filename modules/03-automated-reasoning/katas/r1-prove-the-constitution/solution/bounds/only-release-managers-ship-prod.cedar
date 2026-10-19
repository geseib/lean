// For requests (Human, deploy, Environment): allowed ⇒ below prod, or a release manager.
permit (principal, action, resource)
when { resource.tier != "prod" };

permit (principal in Orchard::Role::"ReleaseManager", action, resource);

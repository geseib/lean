// KATA c2 — the AI-native SDLC rule "the agent that writes code cannot
// approve it", plus its human twin.
//
// Already given: code owners may approve PRs, and the team may comment.
// Your job:
//   1. "agents-never-approve": forbid every Agent from approvePR.
//   2. "no-self-approval": forbid a Human from approving a PR they drive
//      (PullRequest has `driver: Human`).
//   3. "merge-on-green-with-a-human-approval": permit mergePR for anyone,
//      but only when context.ciPassed is true and context.humanApprovals >= 1.

@id("code-owners-approve-prs")
permit (principal in Orchard::Role::"CodeOwner", action == Orchard::Action::"approvePR", resource);

@id("anyone-on-the-team-comments")
permit (principal in Orchard::Team::"web", action == Orchard::Action::"commentPR", resource);

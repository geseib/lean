// TODO: replace this vacuous bound. As written it allows *everything*, so
// policies.cedar trivially implies it — and so does every buggy mutant.
permit (principal, action, resource);

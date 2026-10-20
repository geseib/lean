# Stretch: the second race

Your fix counts the push *request*, so a push in flight when the merge is
decided taints the head. But look at this order of events:

```text
@1000 coder RunTests.request         pr="42"   # tests start on head H1
@1100 coder PushCommit.request       pr="42"   # push H2 while the tests still run
@1110 coder PushCommit.response      pr="42"
@1300 coder RunTests.response        pr="42" | passed=true   # green, but for H1
@1310 coder MergePullRequest.request pr="42"   # -> DENY: this would merge H2, untested
```

1. Paste these lines at the end of `scenario.trace` (keep the timestamps
   increasing) and run `./course check dogwood/k1`. Your annotated line is
   checked too. It fails: the push sits *before* the green response that
   anchors `since`.
2. Why can't any `since` over these events fix it? (Hint: which event says
   *which commit* was tested?)
3. Design the fix. Add an output field `sha` to `RunTests` and an input field
   `sha` to `MergePullRequest` in `world/tools.json`, regenerate the schema with
   `dogwood schema mcp`, and require
   `formerly within 24h RunTests::response{ input.pr: context.input.pr, output.sha: context.input.sha, output.passed: true }`.
   This is the general lesson: correlate on **what was checked**, not on **when**.

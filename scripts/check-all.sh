#!/usr/bin/env bash
# Everything CI checks, runnable locally: ./scripts/check-all.sh
set -euo pipefail
cd "$(dirname "$0")/.."
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

step "Katas: every solution passes, every starter fails"
./course verify

step "Dogwood bundles replay exactly as documented"
schema=modules/02-dogwood/world/schema.cedarschema
for b in modules/02-dogwood/bundles/d*/; do
  extra=(); [ -f "$b/events.dwschema" ] && extra=(--event-schema "$b/events.dwschema")
  python3 tools/dwtrace.py "$b/scenario.trace" > "$b/trace.log"
  dogwood validate "$b/policy.dw" --policy-schema "$schema" "${extra[@]}" > /dev/null
  diff <(dogwood replay "$b/policy.dw" --policy-schema "$schema" --trace "$b/trace.log" "${extra[@]}") "$b/expected.out" \
    && echo "ok   $(basename "$b")"
done

step "Orchard reference policies validate"
cedar validate --schema modules/01-cedar/world/schema.cedarschema --policies modules/01-cedar/world/policies.cedar

step "Capstone guard: simulated Claude Code session"
python3 modules/05-capstone/guard/test_guard.py
dogwood validate modules/05-capstone/guard/policy.dw --policy-schema "$schema"

step "Lean: lessons and solutions build with no sorry; exercises compile"
cd modules/04-lean
lake build Course Solutions Exercises 2>&1 | tee /tmp/lake.log
if grep -E "^(warning|error): (Course|Solutions)/.*sorry" /tmp/lake.log; then
  echo "a lesson or solution still uses sorry" >&2; exit 1
fi
echo -e "\n\033[32mAll checks passed.\033[0m"

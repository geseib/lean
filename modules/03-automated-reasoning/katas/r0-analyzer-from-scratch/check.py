"""Checks analyzer.py against facts we already know from the real Cedar tools."""
import sys

import z3

from mini import HOTFIX, NO_AGENT_PROD, ORCHARD, symbolic_request

try:
    from analyzer import allows, counterexample, equivalent
    r = symbolic_request()

    # 1. Concrete sanity: the formula agrees with Cedar on known requests.
    def decide(policies, **values):
        s = z3.Solver()
        s.add(allows(policies, r))
        for name, v in values.items():
            s.add(getattr(r, name) == v)
        return s.check() == z3.sat
    S = z3.StringVal
    assert decide(ORCHARD, is_agent=True, stage=S("ops"), action=S("deploy"), tier=S("staging")), \
        "an ops agent deploying to staging should be allowed"
    assert not decide(ORCHARD, is_agent=True, stage=S("ops"), action=S("deploy"), tier=S("prod")), \
        "an agent deploying to prod should be denied"
    assert not decide([], is_agent=False, action=S("deploy")), "no policies must mean deny"
    print("✓ allows() matches Cedar on concrete requests (and denies by default)")

    # 2. The real property: Orchard satisfies it.
    assert counterexample(ORCHARD, NO_AGENT_PROD, r) is None, "Orchard should satisfy NO_AGENT_PROD"
    print("✓ proved: ORCHARD implies NO_AGENT_PROD (for every request, not just tested ones)")

    # 3. The hotfix regression is caught, with a concrete witness.
    cex = counterexample(HOTFIX, NO_AGENT_PROD, r)
    assert cex is not None, "HOTFIX lets agents reach prod; you should find a counterexample"
    assert z3.is_true(cex["is_agent"]) and cex["tier"] == S("prod"), f"suspicious counterexample: {cex}"
    print(f"✓ counterexample for HOTFIX: agent={cex['is_agent']}, tier={cex['tier']}, risk={cex['risk']}")

    # 4. Equivalence.
    assert equivalent(ORCHARD, list(reversed(ORCHARD)), r), "policy order never matters in Cedar"
    assert not equivalent(ORCHARD, HOTFIX, r)
    print("✓ equivalent(): order-independence proved, HOTFIX is not equivalent")

    # A peek under the hood: this is the kind of SMT-LIB the solver received.
    s = z3.Solver()
    s.add(allows(HOTFIX, r), z3.Not(allows(NO_AGENT_PROD, r)))
    print("\nThe query you just solved, in SMT-LIB (first lines):")
    print("\n".join("    " + l for l in s.sexpr().splitlines()[:8]))
except NotImplementedError as err:
    print(f"… not implemented yet: {err}")
    sys.exit(1)
except AssertionError as err:
    print(f"✗ {err}")
    sys.exit(1)

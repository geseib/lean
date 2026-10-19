"""SOLUTION r0 — a complete (if tiny) policy analyzer."""
import z3

from mini import Policy, Request


def allows(policies: list[Policy], r: Request) -> z3.BoolRef:
    permits = [p.when(r) for p in policies if p.effect == "permit"]
    forbids = [p.when(r) for p in policies if p.effect == "forbid"]
    # z3.Or([]) is False: with no permits nothing is allowed (deny by default),
    # and with no forbids nothing is vetoed.
    return z3.And(z3.Or(permits), z3.Not(z3.Or(forbids)))


def counterexample(ps1: list[Policy], ps2: list[Policy], r: Request) -> dict | None:
    s = z3.Solver()
    s.add(allows(ps1, r), z3.Not(allows(ps2, r)))   # "ps1 allows, ps2 doesn't"
    if s.check() == z3.unsat:
        return None                                 # no such request exists: PROVED
    m = s.model()
    return {str(v): m.eval(v, model_completion=True)
            for v in (r.is_agent, r.stage, r.trust, r.action, r.tier, r.risk)}


def equivalent(ps1: list[Policy], ps2: list[Policy], r: Request) -> bool:
    return counterexample(ps1, ps2, r) is None and counterexample(ps2, ps1, r) is None

"""KATA r0 — your own policy analyzer.

Implement the three functions below, then run:  ./course check reasoning/r0
"""
import z3

from mini import Policy, Request


def allows(policies: list[Policy], r: Request) -> z3.BoolRef:
    """Cedar's decision as a formula over the symbolic request `r`.

    Allowed  ⟺  some permit's `when` holds  AND  no forbid's `when` holds.
    """
    raise NotImplementedError("TODO: build the formula with z3.And / z3.Or / z3.Not")


def counterexample(ps1: list[Policy], ps2: list[Policy], r: Request) -> dict | None:
    """Prove `ps1 implies ps2` (everything ps1 allows, ps2 allows).

    Return None if it is PROVED, else a dict {variable name: value} for a
    request that ps1 allows and ps2 denies.
    """
    raise NotImplementedError("TODO: z3.Solver(), add the negated property, check()")


def equivalent(ps1: list[Policy], ps2: list[Policy], r: Request) -> bool:
    """Two policy sets are equivalent iff each implies the other."""
    raise NotImplementedError("TODO: use counterexample twice")

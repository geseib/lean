"""A tiny Cedar-like world, symbolically. Shared by analyzer.py and check.py.

A request is a handful of z3 variables. That is the trick every policy
analyzer uses (Cedar's SymCC included): instead of one concrete request, the
solver reasons about ALL requests at once.
"""
from dataclasses import dataclass
from typing import Callable

import z3


@dataclass(frozen=True)
class Request:
    is_agent: z3.BoolRef   # principal is Orchard::Agent (else a Human)
    stage: z3.SeqRef       # principal.stage, any string
    trust: z3.ArithRef     # principal.trust, any integer
    action: z3.SeqRef      # e.g. "deploy"
    tier: z3.SeqRef        # resource.tier, any string
    risk: z3.ArithRef      # context.riskScore, any integer


def symbolic_request() -> Request:
    return Request(z3.Bool("is_agent"), z3.String("stage"), z3.Int("trust"),
                   z3.String("action"), z3.String("tier"), z3.Int("risk"))


@dataclass(frozen=True)
class Policy:
    id: str
    effect: str                                 # "permit" | "forbid"
    when: Callable[[Request], z3.BoolRef]       # the scope + conditions, as a formula


# --- Orchard's deploy rules, transcribed by hand ---------------------------
S = z3.StringVal
ORCHARD = [
    Policy("agents-deploy-below-prod", "permit",
           lambda r: z3.And(r.is_agent, r.action == S("deploy"), r.stage == S("ops"), r.tier != S("prod"))),
    Policy("release-managers-deploy", "permit",
           lambda r: z3.And(z3.Not(r.is_agent), r.action == S("deploy"))),
    Policy("agents-never-deploy-prod", "forbid",
           lambda r: z3.And(r.is_agent, r.action == S("deploy"), r.tier == S("prod"))),
]

HOTFIX = [p for p in ORCHARD if p.id != "agents-never-deploy-prod"] + [
    Policy("hotfix-fast-lane", "permit",
           lambda r: z3.And(r.is_agent, r.action == S("deploy"), r.risk < 2)),
]

# The property, as a policy set: agents never deploy to prod.
NO_AGENT_PROD = [
    Policy("bound", "permit", lambda r: z3.Not(z3.And(r.is_agent, r.action == S("deploy"), r.tier == S("prod")))),
]

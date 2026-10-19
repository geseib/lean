#!/usr/bin/env python3
"""A Dogwood runtime guard for Claude Code: your policies, enforced on a real agent.

Claude Code runs this as a hook on every tool call:

  PreToolUse          -> map the call to an MCP-style tool event, append it to the
                         session trace, replay the trace with `dogwood`, and DENY
                         the call if the policy says so (the reason is shown to Claude).
  PostToolUse         -> append the matching `response` event (the call succeeded).
  PostToolUseFailure  -> append a `response` event with the failure recorded
                         (e.g. RunTests passed=false).

Every decision is history-aware: "no internet after reading a secret",
"no merge unless tests passed on this exact head", "at most N of X per hour".

This uses Dogwood's *reference interpreter*, which replays the whole session
trace on each call. That is right for learning and demos. It is not a
production enforcement point: see docs/production.md.

Environment:
  GUARD_POLICY     policy file      (default: policy.dw next to this script)
  GUARD_SCHEMA     action schema    (default: modules/02-dogwood/world/schema.cedarschema)
  GUARD_STATE_DIR  where traces go  (default: <project>/.guard)
  GUARD_FAIL_OPEN  set to 1 to allow calls when the guard itself breaks (default: fail closed)
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
POLICY = Path(os.environ.get("GUARD_POLICY", HERE / "policy.dw"))
SCHEMA = Path(os.environ.get("GUARD_SCHEMA", REPO / "modules/02-dogwood/world/schema.cedarschema"))
DWTRACE = REPO / "tools/dwtrace.py"

SECRET_PATH = re.compile(r"(^|/)(\.env(\..*)?|.*\.pem|id_(rsa|ed25519)|credentials(\.json)?|secrets?/.*)$")
URL = re.compile(r"https?://[^\s'\"]+")


# ------------------------------------------------------------ classification --
def classify(tool_name: str, tool_input: dict) -> tuple[str, dict]:
    """Map a Claude Code tool call onto the course's MCP tool vocabulary."""
    if tool_name == "Read":
        path = tool_input.get("file_path", "")
        if SECRET_PATH.search(path):
            return "ReadSecret", {"name": path}
        return "ReadFile", {"path": path}
    if tool_name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path", "")
        return "WriteCode", {"feature": os.environ.get("GUARD_FEATURE", "default"), "path": path}
    if tool_name in ("WebFetch", "WebSearch"):
        return "WebFetch", {"url": tool_input.get("url") or tool_input.get("query", "")}
    if tool_name == "Bash":
        return classify_command(tool_input.get("command", ""))
    return "RunCommand", {"command": tool_name}


def classify_command(cmd: str) -> tuple[str, dict]:
    c = cmd.strip()
    branch = current_branch()
    if re.search(r"\bgit\s+push\b", c):
        m = re.search(r"\bgit\s+push\s+(?:-\S+\s+)*\S+\s+(?:HEAD:)?(\S+)", c)
        return "PushCommit", {"pr": branch, "branch": m.group(1) if m else branch}
    if re.search(r"\bgh\s+pr\s+merge\b", c):
        # Tests and pushes are keyed by branch, so merges are too. (A merge
        # by PR number from another branch is keyed to the current branch:
        # the conservative choice, since that branch has no green run for it.)
        return "MergePullRequest", {"pr": branch}
    if re.search(r"(\bdeploy\b|\bdeploy\.sh\b)", c):
        env = "prod" if re.search(r"\b(prod|production)\b", c) else "staging" if "staging" in c else "dev"
        return "Deploy", {"change": branch, "env": env}
    if re.search(r"\b(pytest|npm\s+(run\s+)?test|cargo\s+test|go\s+test|make\s+test|lake\s+build|\./course\s+(check|verify))\b", c):
        return "RunTests", {"pr": branch}
    for word in re.findall(r"[\w./~-]+", c):
        if SECRET_PATH.search(word) and re.search(r"\b(cat|less|head|tail|grep|source|cp)\b", c):
            return "ReadSecret", {"name": word}
    if re.search(r"\b(curl|wget|nc|ssh|scp)\b", c) or URL.search(c):
        m = URL.search(c)
        return "WebFetch", {"url": m.group(0) if m else c[:80]}
    return "RunCommand", {"command": c[:200]}


def current_branch() -> str:
    try:
        out = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or "detached"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


# --------------------------------------------------------------- the trace ----
def fmt(fields: dict) -> str:
    return " ".join(f"{k}={json.dumps(v)}" for k, v in fields.items())


def trace_path(payload: dict) -> Path:
    base = Path(os.environ.get("GUARD_STATE_DIR") or Path(payload.get("cwd") or ".") / ".guard")
    base.mkdir(parents=True, exist_ok=True)
    sid = re.sub(r"[^\w-]", "_", payload.get("session_id") or "session")
    return base / f"{sid}.trace"


def append(path: Path, principal: str, tool: str, kind: str, inputs: dict, outputs: dict | None = None) -> int:
    """Append one event; timestamps are seconds, kept strictly increasing."""
    last = 0
    if path.exists():
        for line in path.read_text().splitlines():
            m = re.match(r"@(\d+)", line)
            if m:
                last = int(m.group(1))
    now = max(int(os.environ.get("GUARD_NOW", time.time())), last + 1)
    line = f"@{now} {principal} {tool}.{kind} {fmt(inputs)}"
    if outputs:
        line += f" | {fmt(outputs)}"
    with path.open("a") as fh:
        fh.write(line + "\n")
    return now


def decide(trace: Path) -> tuple[str, str]:
    """Replay the session; the verdict of the last decision point is ours."""
    compiled = subprocess.run([sys.executable, str(DWTRACE), str(trace)], capture_output=True, text=True)
    if compiled.returncode != 0:
        raise RuntimeError(compiled.stderr.strip())
    log = trace.with_suffix(".log")
    log.write_text(compiled.stdout)
    replay = subprocess.run(["dogwood", "replay", str(POLICY), "--policy-schema", str(SCHEMA),
                             "--trace", str(log), "--format", "json"], capture_output=True, text=True)
    if replay.returncode != 0:
        raise RuntimeError((replay.stdout + replay.stderr).strip()[:2000])
    verdicts = parse_verdicts(replay.stdout)
    if not verdicts:
        raise RuntimeError("dogwood produced no verdict")
    decision, rules = verdicts[-1]
    return decision, ", ".join(rule_ids(rules)) or "no permit matched (deny by default)"


def parse_verdicts(out: str) -> list[tuple[str, list[int]]]:
    """Accept Dogwood's JSON stream (one object per line, or one array)."""
    items = []
    text = out.strip()
    try:
        data = json.loads(text)
        items = data if isinstance(data, list) else data.get("verdicts", [data])
    except ValueError:
        items = [json.loads(l) for l in text.splitlines() if l.strip().startswith("{")]
    result = []
    for it in items:
        d = str(it.get("decision") or it.get("verdict") or "").upper()
        if d in ("ALLOW", "DENY"):
            result.append((d, list(it.get("rules") or it.get("determining_rules") or [])))
    return result


def rule_ids(indices: list[int]) -> list[str]:
    ids = re.findall(r'@id\("([^"]+)"\)', POLICY.read_text())
    return [ids[i] if isinstance(i, int) and i < len(ids) else str(i) for i in indices]


# ------------------------------------------------------------------- hooks ----
def main() -> int:
    payload = json.load(sys.stdin)
    event = payload.get("hook_event_name", "PreToolUse")
    tool, inputs = classify(payload.get("tool_name", ""), payload.get("tool_input") or {})
    principal = os.environ.get("GUARD_PRINCIPAL", "claude")
    trace = trace_path(payload)

    if event in ("PostToolUse", "PostToolUseFailure"):
        outputs = None
        if tool == "RunTests":
            outputs = {"passed": event == "PostToolUse"}
        append(trace, principal, tool, "response", inputs, outputs)
        return 0

    append(trace, principal, tool, "request", inputs)
    try:
        decision, why = decide(trace)
    except (RuntimeError, OSError, ValueError) as err:
        if os.environ.get("GUARD_FAIL_OPEN") == "1":
            return 0
        decision, why = "DENY", f"guard error, failing closed: {err}"

    if decision == "DENY":
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": f"Dogwood guard denied {tool}({fmt(inputs)}): {why}. "
                                        f"Session trace: {trace}",
        }}))
    return 0   # ALLOW: no decision, so Claude Code's normal permission flow still applies


if __name__ == "__main__":
    sys.exit(main())

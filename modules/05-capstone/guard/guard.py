#!/usr/bin/env python3
"""A Dogwood runtime guard for Claude Code: your policies, enforced on a real agent.

Claude Code runs this as a hook on every tool call:

  PreToolUse          -> map the call to MCP-style tool events, append them to the
                         session trace, replay the trace with `dogwood`, and DENY
                         the call if the policy denies any of them.
  PostToolUse         -> append the matching `response` events (the call succeeded).
  PostToolUseFailure  -> append `response` events recording the failure
                         (e.g. RunTests passed=false).

Every decision is history-aware: "no internet after reading a secret",
"no merge unless tests passed with no push since", "3 red runs stop pushes".

Security posture (see the README's "Attack the guard"):
  * fails closed: any error while deciding a PreToolUse call denies it;
  * one lock per session: parallel tool calls cannot interleave or take each
    other's verdicts;
  * state lives outside the agent's workspace (~/.cache by default);
  * every segment of a compound shell command is classified, by its command word.

This uses Dogwood's *reference interpreter*, which replays the whole session
trace on each call. It is right for learning and demos and is not a
production enforcement point: see docs/production.md.

Environment:
  GUARD_POLICY     policy file      (default: policy.dw next to this script)
  GUARD_SCHEMA     action schema    (default: modules/02-dogwood/world/schema.cedarschema)
  GUARD_STATE_DIR  where traces go  (default: ~/.cache/proof-carrying-agents/guard/<project hash>)
  GUARD_FAIL_OPEN  set to 1 to allow calls when the guard itself breaks (default: fail closed)
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
POLICY = Path(os.environ.get("GUARD_POLICY", HERE / "policy.dw"))
SCHEMA = Path(os.environ.get("GUARD_SCHEMA", REPO / "modules/02-dogwood/world/schema.cedarschema"))
DWTRACE = REPO / "tools/dwtrace.py"

SECRET_PATH = re.compile(r"(^|[/@=])(\.env(\.[\w.-]+)?|[\w.-]*\.pem|id_(rsa|ed25519)|credentials(\.json)?|secrets?/[\w./-]*)$")
URL = re.compile(r"https?://[^\s'\"]+")
EGRESS = {"curl", "wget", "nc", "ncat", "netcat", "ssh", "scp", "sftp", "rsync", "ftp", "telnet", "http", "https", "xh"}
MUTATORS = {"rm", "mv", "cp", "tee", "sed", "truncate", "chmod", "chown", "touch", "ln", "install", "dd", "perl"}
WRAPPERS = {"sudo", "time", "nice", "nohup", "env", "command", "exec", "xargs"}
TEST_RUNNERS = {"pytest", "py.test", "tox", "nox"}


# ------------------------------------------------------------ classification --
Event = tuple[str, dict]   # (tool, inputs)


def classify(tool_name: str, tool_input: dict) -> list[Event]:
    """Map a Claude Code tool call onto the course's MCP tool vocabulary."""
    if tool_name == "Read":
        path = tool_input.get("file_path", "")
        return [("ReadSecret", {"name": path})] if SECRET_PATH.search(path) else [("ReadFile", {"path": path})]
    if tool_name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path", "")
        return [("WriteCode", {"feature": os.environ.get("GUARD_FEATURE", "default"), "path": path})]
    if tool_name in ("WebFetch", "WebSearch"):
        return [("WebFetch", {"url": tool_input.get("url") or tool_input.get("query", "")})]
    if tool_name == "Bash":
        events = [e for seg in segments(tool_input.get("command", "")) for e in classify_segment(seg)]
        return events or [("RunCommand", {"command": tool_input.get("command", "")[:200]})]
    return [("RunCommand", {"command": tool_name})]


def segments(cmd: str) -> list[str]:
    """Split on ; && || | & and newlines, outside quotes. $(...) and backticks are
    kept inside their segment and also scanned (see classify_segment)."""
    out, cur, quote, i = [], "", None, 0
    while i < len(cmd):
        ch = cmd[i]
        if quote:
            cur += ch
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote, cur = ch, cur + ch
        elif ch in ";|&\n":
            out.append(cur)
            cur = ""
            while i + 1 < len(cmd) and cmd[i + 1] in "|&":
                i += 1
        else:
            cur += ch
        i += 1
    out.append(cur)
    return [s.strip() for s in out if s.strip()]


def words(seg: str) -> list[str]:
    try:
        return shlex.split(seg)
    except ValueError:
        return seg.split()


def command_word(ws: list[str]) -> tuple[str, list[str]]:
    """Skip env assignments and wrappers like sudo: `FOO=1 sudo -E pytest` -> pytest."""
    i = 0
    while i < len(ws) and (re.fullmatch(r"\w+=.*", ws[i]) or ws[i] in WRAPPERS or (i and ws[i].startswith("-") and ws[i - 1] in WRAPPERS)):
        i += 1
    if i >= len(ws):
        return "", []
    return os.path.basename(ws[i]), ws[i + 1:]


def classify_segment(seg: str) -> list[Event]:
    ws = words(seg)
    cmd, args = command_word(ws)
    branch = current_branch()
    events: list[Event] = []

    # Anything that names a secret reads it (cat .env, cp .env x, curl -d @.env ...).
    for w in ws:
        for part in re.split(r"[=@:]", w) + [w]:
            if part and SECRET_PATH.search(part):
                events.append(("ReadSecret", {"name": part}))
                break
    # Anything that touches the guard's own files is a write to them.
    if (cmd in MUTATORS or re.search(r">\s*\S", seg)) and protected_path_in(seg):
        events.append(("WriteCode", {"feature": "guard", "path": protected_path_in(seg)}))

    if cmd == "git":
        rest = list(args)
        while rest and rest[0].startswith("-"):            # git -C dir / -c k=v / --git-dir=...
            rest = rest[2:] if rest[0] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") else rest[1:]
        if rest and rest[0] == "push":
            refs = [a for a in rest[1:] if not a.startswith("-")]
            target = refs[1].split(":")[-1] if len(refs) > 1 else branch
            events.append(("PushCommit", {"pr": branch, "branch": target}))
    elif cmd == "gh" and args[:2] == ["pr", "merge"]:
        events.append(("MergePullRequest", {"pr": branch}))
    elif "deploy" in cmd or (cmd == "make" and any("deploy" in a for a in args)):
        env = "prod" if re.search(r"\b(prod|production)\b", seg) else "staging" if "staging" in seg else "dev"
        events.append(("Deploy", {"change": branch, "env": env}))
    elif is_test_run(cmd, args):
        events.append(("RunTests", {"pr": branch}))

    if cmd in EGRESS or URL.search(seg):
        m = URL.search(seg)
        events.append(("WebFetch", {"url": m.group(0) if m else seg[:120]}))
    # Command substitutions are commands too.
    for inner in re.findall(r"\$\(([^)]*)\)|`([^`]*)`", seg):
        for sub in segments(inner[0] or inner[1]):
            events += classify_segment(sub)
    return events or [("RunCommand", {"command": seg[:200]})]


def is_test_run(cmd: str, args: list[str]) -> bool:
    if cmd in TEST_RUNNERS:
        return True
    if cmd.startswith("python") and args[:2] == ["-m", "pytest"]:
        return True
    if cmd in ("npm", "yarn", "pnpm") and (args[:1] == ["test"] or args[:2] == ["run", "test"]):
        return True
    if cmd in ("cargo", "go") and args[:1] == ["test"]:
        return True
    if cmd == "make" and args[:1] == ["test"]:
        return True
    if cmd == "lake" and args[:1] == ["build"]:
        return True
    return cmd == "course" and args[:1] in (["check"], ["verify"])


def protected_path_in(seg: str) -> str | None:
    m = re.search(r"(\S*(?:\.claude/|\.guard\b|guard/(?:guard\.py|policy\.dw))\S*)", seg)
    return m.group(1) if m else None


def current_branch() -> str:
    try:
        out = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or "detached"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


# --------------------------------------------------------------- the trace ----
def fmt(fields: dict) -> str:
    return " ".join(f"{k}={json.dumps(v)}" for k, v in fields.items())


def state_dir(payload: dict) -> Path:
    if os.environ.get("GUARD_STATE_DIR"):
        base = Path(os.environ["GUARD_STATE_DIR"])
    else:
        project = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or "."
        key = hashlib.sha256(str(Path(project).resolve()).encode()).hexdigest()[:16]
        base = Path.home() / ".cache" / "proof-carrying-agents" / "guard" / key
    base.mkdir(parents=True, exist_ok=True)
    return base


def trace_path(payload: dict) -> Path:
    sid = re.sub(r"[^\w-]", "_", payload.get("session_id") or "session")
    return state_dir(payload) / f"{sid}.trace"


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


def decide(trace: Path, at: int) -> tuple[str, str]:
    """Replay the session; return the verdict of the decision point at time `at`."""
    compiled = subprocess.run([sys.executable, str(DWTRACE), str(trace)], capture_output=True, text=True)
    if compiled.returncode != 0:
        raise RuntimeError(compiled.stderr.strip())
    log = trace.with_suffix(".log")
    log.write_text(compiled.stdout)
    replay = subprocess.run(["dogwood", "replay", str(POLICY), "--policy-schema", str(SCHEMA),
                             "--trace", str(log), "--format", "json"], capture_output=True, text=True)
    if replay.returncode != 0:
        raise RuntimeError((replay.stdout + replay.stderr).strip()[:2000])
    mine = [v for v in json.loads(replay.stdout).get("verdicts", []) if v.get("timestamp") == at]
    if len(mine) != 1:
        raise RuntimeError(f"expected one verdict at @{at}, got {len(mine)}")
    decision = str(mine[0].get("verdict", "")).upper()
    rules = mine[0].get("determining_rules") or []
    return decision, ", ".join(rule_ids(rules)) or "no permit matched (deny by default)"


def rule_ids(indices: list[int]) -> list[str]:
    ids = re.findall(r'@id\("([^"]+)"\)', POLICY.read_text())
    return [ids[i] if isinstance(i, int) and i < len(ids) else str(i) for i in indices]


class SessionLock:
    """One writer per session: append + replay + verdict happen atomically."""
    def __init__(self, trace: Path):
        self.fh = open(trace.with_suffix(".lock"), "w")

    def __enter__(self):
        fcntl.flock(self.fh, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.fh, fcntl.LOCK_UN)
        self.fh.close()


# ------------------------------------------------------------------- hooks ----
def deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}))


def handle(payload: dict) -> None:
    event = payload.get("hook_event_name", "PreToolUse")
    calls = classify(payload.get("tool_name", ""), payload.get("tool_input") or {})
    principal = os.environ.get("GUARD_PRINCIPAL", "claude")
    trace = trace_path(payload)

    with SessionLock(trace):
        if event in ("PostToolUse", "PostToolUseFailure"):
            for tool, inputs in calls:
                outputs = {"passed": event == "PostToolUse"} if tool == "RunTests" else None
                append(trace, principal, tool, "response", inputs, outputs)
            return
        for tool, inputs in calls:            # every event must be allowed
            at = append(trace, principal, tool, "request", inputs)
            decision, why = decide(trace, at)
            if decision != "ALLOW":
                deny(f"Dogwood guard denied {tool}({fmt(inputs)}): {why}. Session trace: {trace}")
                return
    # ALLOW: no decision printed, so Claude Code's normal permission flow still applies.


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except ValueError as err:
        payload = {}
        if os.environ.get("GUARD_FAIL_OPEN") != "1":
            deny(f"guard error, failing closed: unreadable hook input ({err})")
        return 0
    try:
        handle(payload)
    except Exception as err:  # noqa: BLE001 - anything at all must fail closed
        if payload.get("hook_event_name", "PreToolUse") == "PreToolUse" and os.environ.get("GUARD_FAIL_OPEN") != "1":
            deny(f"guard error, failing closed: {type(err).__name__}: {err}")
        else:
            print(f"guard: {type(err).__name__}: {err}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

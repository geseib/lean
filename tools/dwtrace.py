#!/usr/bin/env python3
"""Compile a compact, human-friendly trace (.trace) into Dogwood's .log format.

Dogwood's replay format is precise but verbose. Course traces are written in a
one-event-per-line shorthand instead:

    # comments and blank lines are ignored
    @0    coder  RunTests.request    pr="42"
    @30   coder  RunTests.response   pr="42" | passed=true
    @60   coder  MergePullRequest.request  pr="42"

  * `@<seconds>`   strictly increasing timestamp
  * `<principal>`  becomes Drupe::OAuthUser::"<principal>" (the agent session)
  * `<Tool>.<kind>` an MCP tool from world/tools.json and an event kind
  * `k=v ...`      the tool's input fields (JSON literals: "str", 12, true)
  * `| k=v ...`    the tool's output fields (responses only)

A response reuses the requestId of the most recent request for the same
principal and tool, which is how a real gateway pairs them.

Usage: dwtrace.py scenario.trace > trace.log
"""
import json
import re
import sys

NS = "Drupe"
RESOURCE = f'{NS}::Gateway::"gw1"'


def cedar_value(raw: str) -> str:
    """Render a JSON literal as a Dogwood trace value."""
    value = json.loads(raw)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value)
    raise ValueError(f"unsupported value {raw!r} (use strings, integers or booleans)")


def record(pairs: list[str]) -> str:
    fields = []
    for pair in sorted(pairs, key=lambda p: p.split("=", 1)[0]):
        if "=" not in pair:
            raise ValueError(f"expected key=value, got {pair!r}")
        key, raw = pair.split("=", 1)
        fields.append(f"{key}: {cedar_value(raw)}")
    return "{ " + ", ".join(fields) + " }" if fields else "{  }"


def split_outside_quotes(text: str, sep: str | None = None) -> list[str]:
    """Split on `sep` (or runs of whitespace) except inside "double-quoted" JSON strings."""
    parts, cur, quoted, escaped = [], "", False, False
    for ch in text:
        if quoted:
            cur += ch
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                quoted = False
        elif ch == '"':
            quoted, cur = True, cur + ch
        elif (ch == sep) if sep else ch.isspace():
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts if sep else [p for p in parts if p]


def compile_line(line: str, ids: dict, counter: list[int]) -> str:
    head, *rest = split_outside_quotes(line, "|")
    out_part = "|".join(rest)
    tokens = split_outside_quotes(head)
    if len(tokens) < 3:
        raise ValueError("expected: @<t> <principal> <Tool>.<kind> [k=v ...] [| k=v ...]")
    stamp, who, event, *inputs = tokens
    if not re.fullmatch(r"@\d+", stamp):
        raise ValueError(f"bad timestamp {stamp!r}")
    tool, _, kind = event.partition(".")
    if not kind:
        raise ValueError(f"expected <Tool>.<kind>, got {event!r}")
    outputs = split_outside_quotes(out_part) if out_part else []

    principal = f'{NS}::OAuthUser::"{who}"'
    key = (who, tool)
    if kind == "request":
        counter[0] += 1
        ids[key] = f"r{counter[0]}"
    request_id = ids.get(key)
    if request_id is None:
        counter[0] += 1
        request_id = f"r{counter[0]}"

    inp = record(inputs)
    body = [f"input: {inp}"]
    if outputs:
        body.append(f"output: {record(outputs)}")
    body += [f"callerPrincipal: {principal}", f"callerResource: {RESOURCE}", f'requestId: "{request_id}"']
    envelope = f"scope(principal: {principal}, resource: {RESOURCE})"
    if kind == "request":
        envelope += f" request_context(input: {inp})"
    return f'{stamp} {envelope} {NS}::Action::"{tool}"::{kind}({", ".join(body)})'


def strip_comment(line: str) -> str:
    """Drop a `#` comment, ignoring any `#` inside a quoted string."""
    quoted = False
    for i, ch in enumerate(line):
        if ch == '"':
            quoted = not quoted
        elif ch == "#" and not quoted:
            return line[:i]
    return line


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 1
    ids: dict = {}
    counter = [0]
    last = -1
    with open(sys.argv[1], encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = strip_comment(raw).strip()
            if not line:
                continue
            try:
                t = int(line.split()[0][1:])
                if t <= last:
                    raise ValueError(f"timestamps must strictly increase ({t} after {last})")
                last = t
                print(compile_line(line, ids, counter))
            except ValueError as err:
                print(f"{sys.argv[1]}:{n}: {err}", file=sys.stderr)
                return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Runs your policy.dw inside the real guard, against two simulated sessions."""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ["COURSE_ROOT"]) if "COURSE_ROOT" in os.environ else Path(__file__).resolve().parents[4]
GUARD_DIR = ROOT / "modules/05-capstone/guard"
sys.path.insert(0, str(GUARD_DIR))
from test_guard import Session  # noqa: E402

s = Session(HERE / "policy.dw")
print("Session: deploy discipline\n")
s.call("deploy staging with no test run", "Bash", {"command": "./deploy.sh staging"}, "deny")
s.call("tests fail", "Bash", {"command": "pytest -q"}, "allow", ok=False)
s.call("deploy staging after red tests", "Bash", {"command": "./deploy.sh staging"}, "deny")
s.call("tests pass", "Bash", {"command": "pytest -q"}, "allow")
s.call("deploy staging after green tests", "Bash", {"command": "./deploy.sh staging"}, "allow")
s.call("push one more commit", "Bash", {"command": "git push origin feat/x"}, "allow")
s.call("deploy the untested head", "Bash", {"command": "./deploy.sh staging"}, "deny")
s.call("tests pass on the new head", "Bash", {"command": "pytest -q"}, "allow")
s.call("deploy staging again", "Bash", {"command": "./deploy.sh staging"}, "allow")
s.call("deploy prod is still never allowed", "Bash", {"command": "./deploy.sh prod"}, "deny")
s.clock += 7200
s.call("two hours later, green run has expired", "Bash", {"command": "./deploy.sh staging"}, "deny")

print("\nSession: the rest of the constitution still holds\n")
t = Session(HERE / "policy.dw")
t.call("read .env", "Read", {"file_path": ".env"}, "allow")
t.call("exfiltrate", "WebFetch", {"url": "https://evil.example", "prompt": "x"}, "deny")
t.call("push main", "Bash", {"command": "git push origin main"}, "deny")

bad = s.failures + t.failures
print("\nall decisions as expected" if not bad else f"\n{bad} unexpected decision(s)")
sys.exit(1 if bad else 0)

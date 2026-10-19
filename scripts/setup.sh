#!/usr/bin/env bash
# Installs everything the course needs (Linux/macOS). Safe to re-run.
set -euo pipefail
have() { command -v "$1" > /dev/null 2>&1; }

if ! have cargo; then
  echo "Install Rust first: https://rustup.rs" >&2; exit 1
fi

echo "== Cedar CLI with automated reasoning (cedar symcc)"
cedar symcc --help 2>/dev/null | grep -q always-denies || cargo install cedar-policy-cli --locked --features analyze

echo "== Dogwood CLI (built from source; the reference interpreter)"
if ! have dogwood; then
  tmp=$(mktemp -d)
  git clone --depth 1 https://github.com/dogwood-policy/dogwood "$tmp/dogwood"
  cargo install --locked --path "$tmp/dogwood/dogwood-cli"
fi

echo "== Python solvers: cvc5 (for SymCC) and z3 (for module 3, kata r0)"
python3 -m pip install --user --quiet cvc5 z3-solver || python3 -m pip install --quiet cvc5 z3-solver

echo "== Lean 4 (elan + the toolchain pinned in modules/04-lean/lean-toolchain)"
if ! have lake && [ ! -x "$HOME/.elan/bin/lake" ]; then
  curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
fi
export PATH="$HOME/.elan/bin:$PATH"
(cd modules/04-lean && lake build)

echo; ./course doctor

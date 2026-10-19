# Setup

`./scripts/setup.sh` does all of this. Here it is by hand, with notes.

| Tool | Install | Used in |
|---|---|---|
| Rust | <https://rustup.rs> | building Cedar and Dogwood |
| Cedar CLI **with analysis** | `cargo install cedar-policy-cli --locked --features analyze` | modules 1, 3 |
| Dogwood CLI | `git clone https://github.com/dogwood-policy/dogwood && cargo install --locked --path dogwood/dogwood-cli` | modules 2, 5 |
| cvc5 | `pip install cvc5` (the course drives it through `tools/cvc5-py`), or a cvc5 release binary with `export CVC5=/path/to/cvc5` | module 3 (SymCC) |
| z3 | `pip install z3-solver` | module 3, kata r0 |
| Lean 4 | `curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf \| sh` | module 4 |
| VS Code + "Lean 4" extension | marketplace | module 4 (the infoview) |
| Claude Code | <https://code.claude.com> | module 5 |

Then run `./course doctor`.

## Notes

- **Why `--features analyze`?** The default Cedar CLI build leaves out
  `cedar symcc`. `./course doctor` tells you if yours is missing it.
- **Why cvc5 and not z3 for SymCC?** SymCC's encoding uses cvc5's finite-set
  theory. `tools/z3-as-cvc5` exists for experiments, but z3 rejects queries
  over sets.
- **No network to `release.lean-lang.org`?** Build Lean from source:
  `git clone --branch v4.35.0 https://github.com/leanprover/lean4 && cd lean4 && cmake --preset release && make -C build/release -j`
  (needs libgmp ≥ 6.3 and libuv headers), then
  `elan toolchain link course lean4/build/release/stage1` and
  `elan override set course` inside `modules/04-lean`.

# docker-dev.sh — `validate_org()` / `ex_validate_project()` scenario matrix

Behavior of project resolution for combinations of `--target` (`$_target`) and
`--penv` (`$_prj_env`), as observed against commit `5508c81`.
All rows marked "verified" were executed end-to-end with a stubbed `docker`.

## Mechanics

### `validate_org()` (docker-dev.sh:188)

Runs first, decides where `REP` lives:

- `ORG` env unset → `ORG=$HOME`, `BASE=$HOME/REP`
- `ORG` set and `$ORG/REP` is a rw dir → `BASE=$ORG/REP`
- `$ORG/REP` missing or not rw → prints error, falls back to `$HOME/REP`;
  the fallback itself is never re-validated (and when `ORG` was unset the
  "fallback" is identical to the primary, i.e. a no-op)

### `check($_target, $_prj_env)` (docker-dev.sh:261)

Appends penv (`BASE=$BASE/$penv`), builds `MANAGED_P_TYPES` from `langs/`,
then routes on `_resolved=$(readlink -m -- "$1")`:

- `_resolved` is an existing rw dir → `PROJECT_DIR=$_resolved`; this bypasses
  `is_valid()`, the type-membership gate and `BASE` entirely — resolution is
  against the CWD, so a relative target can be hijacked by a same-named dir
  in the launch directory
- absolute but missing → refused
- relative → `is_valid()` charset checks → `create_relative_folder()`
  (membership in the `langs/` set, `mkdir -p $BASE/<Type>/rest`)

### `ex_validate_project()` (docker-dev.sh:147)

Path *string* parsing, independent of the above:

- finds the **first** `REP` component; none → error + exit
- `P_NAME` = basename, lowercased, `[^a-z0-9-]` → `_`, then `-` → `_`
  (e.g. `my-app.v2` → `my_app_v2`)
- `P_TARGET` = component after `REP` (the penv), `P_TYPE` = the one after
  that — both taken from the **path**, not from the options
- `REP` or `REP/<penv>` as the last components → array read past the end →
  `set -u` unbound-variable crash (the commented TODO at docker-dev.sh:167
  acknowledges it)

## Scenario table

| # | `--target` | `--penv` | Preconditions | PROJECT_DIR | P_TARGET / P_TYPE / P_NAME | Result |
|---|---|---|---|---|---|---|
| **A1** | any | any | `ORG` unset, `~/REP` rw | `$HOME/REP/<penv>/...` | from path | OK |
| **A2** | any | any | `ORG=/data` valid | `/data/REP/<penv>/...` | from path | OK |
| **A3** | any | any | `ORG=/nope` | falls back to `$HOME/REP` | from path | OK w/ warning; fallback unchecked |
| **B1** | `Python/foo` | (default `DEV`) | new project | `$BASE/DEV/Python/foo` (created) | `DEV / Python / foo` → `dev.python.foo` | OK (verified) |
| **B2** | `Python/foo` | `TEST` | new | `$BASE/TEST/Python/foo` | `TEST / Python / foo` → `test.python.foo` | OK (verified) |
| **B3** | `Rust/foo` | any | type not in `langs/` | — | — | rejected, no dir created (verified) |
| **B4** | `Python` | any | no `/` | — | — | `is_valid` cond 5 reject |
| **B5** | `../x`, `a//b`, `.x`, `x/` | any | — | — | — | `is_valid` conds 1-4 reject |
| **B6** | `Python/deep` | `a/b` | new | `$ORG/REP/a/b/Python/deep` | `a / b / deep` → image `a.b` | runs but wrong identity; `langs/b/bin` missing later (verified) |
| **B7** | `Python/x` | empty | new | `$ORG/REP//Python/x` | `` / Python / x`` → image `.python` | runs; invalid docker name (verified) |
| **C1** | `Deno/bar` | any | CWD has `Deno/bar`, CWD not under `REP` | `$CWD/Deno/bar` | — | **FAIL**: "'REP' directory not found", rc=1 (verified) |
| **C2** | `Deno/bar` | any | CWD=`.../REP/DEV`, dir exists | `$CWD/REP/DEV/Deno/bar` | `DEV / Deno / bar` — from path, `--penv` ignored | OK — canonical usage |
| **C3** | `C++/x` | any | CWD has `C++/x` dir | `$CWD/C++/x` | `… / C++ / x` | passes `check` (gate bypassed), dies later in `langs/C++/bin` |
| **D1** | `$ORG/REP/DEV/Python/foo` (exists) | ignored | rw | unchanged | `DEV / Python / foo` | OK (verified) |
| **D2** | `/tmp/foo` (exists) | ignored | rw, no `REP` in path | — | — | **FAIL**: 'REP' not found, rc=1 |
| **D3** | `/abs/new` | any | missing | — | — | refused: "cannot create new absolute path", rc=1 (verified) |
| **D4** | `$ORG/REP` | any | exists | — | — | **crash**: `components[REP_INDEX+1]: unbound variable` (verified) |
| **D5** | `$ORG/REP/DEV` | any | exists | — | — | **crash**: `components[REP_INDEX+2]: unbound variable` (verified) |
| **D6** | `$ORG/REP/DEV/Python/sub/proj` | ignored | exists | unchanged | `DEV / Python / proj` (middles ignored) | OK |
| **D7** | `Python/my-app.v2` | `DEV` | new | `$BASE/DEV/Python/my-app.v2` | `DEV / Python / my_app_v2` | OK; folder keeps original name (verified) |

## Notable quirks

- `--penv` is only trusted for *creation*; identity (`P_TARGET`) always comes
  from the final path — C2 shows penv silently ignored, B6/B7 show penv able
  to corrupt it (its value is never validated).
- The CWD-hijack rows (C1-C3) are the sharpest edge: `readlink -m` resolves
  relative targets against the CWD, so any same-named dir there redirects the
  project and skips every validation gate.
- First `REP` in the path wins (a path with two `REP` components uses the
  leftmost).
- `ex_validate_project` leaks globals (`components`, `REP_INDEX`, `i`) and its
  error line prints the global `$PROJECT_DIR` instead of `$__PROJECT_DIR`
  (docker-dev.sh:183).
- D4/D5 are the only outright crashes.

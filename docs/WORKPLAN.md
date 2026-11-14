# c3vet — Work plan for implementers

Three implementers: **agy**, **codex**, **claude**. One orchestrator.

Read `DESIGN.md` before writing a line. Interfaces marked `[FROZEN]` there are
orchestrator-owned: if you need one changed, say so and stop — do not edit it.

---

## 0. The rules that keep three agents from colliding

1. **One file has exactly one owner per phase.** Ownership is in the tables
   below. Never edit a file you do not own, including to "quickly fix" it.
2. **One check = one file in `src/c3vet/checks/` + one file in
   `test/testdata/`.** Nothing else. Checks never touch shared files.
3. **`registry.c3` is orchestrator-only.** It is the one place where three
   lanes would otherwise conflict on every commit. Report your check's `Check`
   literal in your completion note; the orchestrator lands it.
4. **Branch per work package**, named `wp/<id>-<slug>`. Rebase on `main` before
   handing back. Never commit `lib/` — `c3l` owns it.
5. **Phase 0 is strictly serial** and done by the orchestrator alone. No lane
   starts before its gate is green, because every lane consumes the frozen
   interfaces.
6. **Done means:** `c3c build` clean, `c3c test` green, your gate met, no
   warnings introduced, and you ran `c3f` over your files.
7. **Verify against the compiler, never memory.** C3 0.8 differs substantially
   from the 0.6/0.7 in model training data. Use the `c3-guide` MCP tools
   (`c3_lookup` before using any name, `c3_check` on every snippet, `c3_test`)
   rather than recalling syntax. The grammar's authority is
   `~/Documents/c3c/resources/grammar/grammar.y`, not any tool's summary.
8. **`src/parser/` is a standalone library and must stay one.** Read
   `DESIGN.md` §1.5 before touching it. Never import `c3vet` from it, never
   name `Diagnostic`/`Check`/`Ctx`/`Config`/`Unit` in it, never add a global or
   do I/O there. CI builds it alone; if `c3c build parser` goes red, that is
   your change.
9. **Probe before you implement.** Any check marked `proposed` in `CHECKS.md`
   gets re-probed against the pinned c3c *first*, as an isolated compiling
   file. If c3c already diagnoses it, delete the row and say so — that has
   already happened to five checks. Overlap with the compiler is a bug, not a
   bonus.
10. **The dependency is `lexer.c3l` v0.1.1 via `c3l`.** The clone at
   `~/Documents/lexer.c3l` is stale and does not compile against c3c 0.8.7 —
   do not read it, do not copy from it, do not develop against it.

---

## Phase 0 — Foundation (orchestrator, serial, blocks everything)

| # | Deliverable |
|---|---|
| 0.1 | `git init`; `.gitignore`; commit the scaffold and these docs |
| 0.2 | `project.json` with `dependencies: ["lexer"]`; `c3l` fetch; lock v0.1.1; confirm `c3c build` is clean |
| 0.3 | `ast.c3` — `Node`, `NodeId`, full `NodeKind` enum, accessors, **and the normative per-kind field table** |
| 0.3b | `src/parser/error.c3` (`ParseError`) and `api.c3` (`parse`/`ParseResult`); `project.json` `parser` library target + the CI carve-out gates (`DESIGN.md` §1.5 rule 5) |
| 0.4 | `lex.c3` — `TokenList`, trivia split, `contract_before()` |
| 0.5 | `diag.c3`, `suppress.c3`, `config.c3` |
| 0.6 | `engine.c3` — `Check`, `Tier`, `Ctx`, `Unit`, tier scheduling; `registry.c3` with one stub check |
| 0.7 | `parse.c3` — `Parser` state, token helpers, recovery primitives, entry points; stub bodies for the four grammar files so three lanes compile independently from hour one |
| 0.8 | `walk.c3` — generic visitor |
| 0.9 | `test/harness.c3` (`// want` runner), `test/invariants.c3`, `test/conformance.c3` |
| 0.10 | `src/cli/` — args, target resolution, output, exit codes |
| 0.11 | **Re-probe all eight Phase 2 T1 checks** against the pinned c3c as isolated compiling files, *before* lane assignments go out (rule 9). The same operation already deleted five checks; do it on the remainder before three agents build them |

**Gate: MET.** Verified by `scripts/check-carveout.sh` (both carve-out gates,
tested to fail on a deliberate violation), `scripts/probe-overlap.sh` (23/23
probes as expected), `c3c test` (25 passing), and the real CLI emitting a
finding with exit 1. Interfaces are now **frozen**.

Two gotchas worth knowing before you start:

- Type properties use `::` since 0.8 (`uint::max`, not `uint.max`). Your
  training data is probably 0.7. `c3_check` rewrites it and tells you.
- `@local` is silently ignored on method declarations; use it on plain
  functions only.

---

## Phase 1 — Parser (three lanes, parallel)

Split along grammar areas. Each lane owns its files outright. All three consume
`parse.c3`'s helpers and `ast.c3`'s node kinds, which is why Phase 0 must land
first.

| Lane | Owner | Files | Scope |
|---|---|---|---|
| **1A** | **agy** | `src/parser/parse_expr.c3` | The full precedence chain (`DESIGN.md` §3), postfix/call/member/subscript/slice, literals, initializer lists, lambdas, `try`/`catch` operand grammar, `$`-expressions, the `no_init_list` flag |
| **1B** | **codex** | `src/parser/parse_stmt.c3` | All 28 statement forms in `grammar.y`'s `statement` production: control flow, `switch`/`case`/`nextcase`, `foreach`, `defer`, `assert`, labels, `$if`/`$switch`/`$for`/`$foreach`, `asm` blocks, statement-level recovery |
| **1C** | **claude** | `src/parser/parse_decl.c3`, `src/parser/parse_type.c3` | Top level: module/import/fn/macro/attrmacro/struct/union/bitstruct/enum/interface/typedef/alias/const/global/faultdef/attrdef/constset, parameter lists, attributes, generic parameters, contract blocks; and the complete type grammar |
| — | orchestrator | `src/parser/{ast,parse,lex,walk,error,api}.c3`, `test/parser/*` | Core, recovery policy, invariants, conformance driver |

**Interface between lanes:** only the functions declared in `parse.c3`. 1A
exposes `parse_expr(Parser*, Prec)`; 1B exposes `parse_stmt(Parser*)` and
`parse_block(Parser*)`; 1C exposes `parse_decl(Parser*)` and
`parse_type(Parser*)`. They call each other **only** through these four. Agree
no other cross-lane entry point.

**Per-lane gate:** every construct in your grammar area appears in
`test/parser/shape_<area>.c3` with an expected node-shape assertion, the
invariants hold on those files, and **`c3c build parser` is green** — the
carve-out must survive your lane.

**Phase gate (all lanes):** the **642-file conformance corpus** — `c3c/lib`
(366) + `c3c/test/unit` (276) — parses with **zero** `ERROR` nodes and all four
invariants hold. The **816-file resilience corpus** (`c3c/test/test_suite`, of
which 662 are deliberately invalid) must not crash, hang, or break an
invariant — do **not** chase zero errors there, those files are supposed to be
broken. Fix forward; a lane is not done while the conformance corpus is red in
its area.

**Sequencing note:** 1A is the critical path — statements and declarations both
embed expressions. If one lane must start first, it is 1A; 1B and 1C can work
against `parse_expr`'s signature with a trivial stub until it lands.

---

## Phase 2 — Engine + T1 checks + CLI (three lanes, parallel)

Checks are embarrassingly parallel: one file each, no shared state, each with
its own testdata. See `CHECKS.md` for exact semantics.

| Lane | Owner | Checks (`CHECKS.md` families C, D, E, H) |
|---|---|---|
| **2A** | **agy** | `self-assign`, `self-compare`, `self-op` — plus `ast::same_expr` in `src/c3vet/checks/support/same_expr.c3`, **including the side-effect guard**, which the other lanes depend on |
| **2B** | **codex** | `dup-branch`, `const-cond`, `const-int-div-to-float`, `const-narrowing-overflow` |
| **2C** | **claude** | `empty-body`, `loop-no-advance`, `empty-loop-body`, `unused-label` |

Lane 2B was originally five duplicate-detection checks. Probing c3c deleted
four of them — `dup-case`, `dup-field`, `dup-import` and `dup-attr-arg` are all
compiler errors today — so it picked up the constant-arithmetic pair instead.
This is rule 9 working as intended.

**Gate:** each check has testdata with 1:1 `// want` matching; **zero false
positives over the 642-file conformance corpus**; `c3vet` run on its own source
is clean. Report your measured FP count — `default_on` is decided by that
number, not by opinion. For checks triaged `upstream` in `CHECKS.md`, that FP
number is also the evidence for the c3c patch, so record it.

---

## Phase 3 — T2 (scopes and flow) — **the highest-value phase**

Families A and B are the two that justify the tool: five temp-memory escape
checks and five fault-hygiene checks, all confirmed gaps, all zero compiler
coverage. If the project is ever cut short, cut Phase 2, not this.

| Lane | Owner | Deliverable |
|---|---|---|
| **3A** | orchestrator | `scope.c3`, `flow.c3`, and the `talloc`/`tmem`-origin tracking helper that Family A builds on |
| **3B** | **agy** | **Family A** — `temp-escapes-fn`, `temp-escapes-pool`, `temp-escapes-struct`, `temp-wrong-free`, `temp-to-global` |
| **3C** | **codex** | **Family B** — `swallowed-fault`, `silenced-fault`, `unused-catch-binding`, `unused-try-binding`, `force-unwrap` |
| **3D** | **claude** | `float-equal`, `cond-not-bool`, `defer-in-loop` |

3A blocks 3B–3D.

**Family A is deliberately narrow.** Track locals whose initializer is a
`talloc`/`tmem` call, then report only the five documented escape shapes. No
alias analysis, no interprocedural reasoning: a pointer that passes through a
function call is not tracked and not reported. False negatives are acceptable
here; false positives are not. If a shape cannot reach zero FPs over the
corpus, cut that shape rather than weaken the guard.

---

## Phase 4 — T3 (project table)

| Lane | Owner | Deliverable |
|---|---|---|
| **4A** | orchestrator | `table.c3` — declaration table over the **indexed** scope (project + deps + stdlib, declarations only); `Ctx.report` enforces the narrower **reported** scope. `DESIGN.md` §5 |
| **4B** | **agy** | `missing-format-attr` — the highest-value T3 check |
| **4C** | **codex** | `unused-import`, `unused-private-decl` |
| **4D** | **claude** | `contract-void-return`, `contract-tautology` — both via `ContractLexer` on trivia, `DESIGN.md` §2 |

Deleted from this phase by probing: `test-signature` (c3c: *"'@test' and
'@benchmark' functions may not take any parameters"* and *"may only return
'void'"*), `unknown-attr` (*"This is not a known valid attribute name"*), and
`contract-unknown-param` (*"There is no parameter 'nonexistent', did you
misspell it?"*).

---

## Phase 5 — Hardening (orchestrator + whoever is free)

Carve `src/parser/` out into `parser.c3l` if we decide to (`DESIGN.md` §1.5) ·
upstream patches for the `CHECKS.md` rows triaged `upstream` ·
FP sweep over the conformance corpus with every check on · performance to
**< 0.5 s** for the 642 conformance files and **< 50 MB** peak · the differential oracle against c3c wired into
CI · `c3vet.1` man page · README with real output · GitHub Actions · `c3l`
publish.

---

## Dispatch

`agy` and `codex` are CLI binaries at `~/.local/bin/`; `claude` is an
addressable peer session. Herdr is available in this environment
(`HERDR_ENV=1`), so lanes can run as panes.

**Per-package handoff contains exactly:** the lane id, the owned file list, the
`DESIGN.md` sections that apply, the interface functions it may call, the gate,
and rule 7 above (verify against the compiler, not memory). Nothing else —
specifically not "and fix anything else you notice", which is how file ownership
gets violated.

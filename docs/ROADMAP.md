# c3vet — Roadmap

`c3vet` reports **suspicious but legal** C3 code: constructs that compile cleanly
and are almost certainly not what the author meant.

Status: planning. Nothing implemented. Target compiler: **c3c 0.8.7**.

---

## 1. Why this tool exists (measured, not assumed)

A naive framing — "port `go vet` to C3" — does not survive contact with the
compiler. `c3c --validation=obnoxious` is already a capable vet. Before writing
any plan, each candidate check was probed as a standalone compiling file against
c3c 0.8.7 at all three validation levels.

### Already diagnosed by c3c — c3vet must NOT reimplement these

| Construct | c3c says | Level |
|---|---|---|
| `int x; { int x; }` | `error: 'x' would shadow a previous declaration` | default |
| `io::printfn("%s %s", a)` | `error: Too few arguments ... formatting string` | default |
| `io::printfn("%s", a, a, a)` | `error: Too many arguments ...` | default |
| `io::printfn("%d", "str")` | `error: Expected a number here, but ... 'String'` | default |
| `return &local;` | `error: A pointer to a local variable will be invalid ...` | default |
| `1 << 40` on `int` | `error: The shift (40) is not less than the bitsize` | default |
| `n > 0 & n < 5` | `error: You need to add explicit parentheses` | default |
| `usz u; u < 0` | `error: Comparing 'unsigned expression < 0' can never be true` | default |
| code after `return` | `warning: This code will never execute` | default |¹
| naming conventions | `error: Names of enums cannot be all uppercase` etc. | default |
| unused param / local / var | `error: The parameter 'x' is never used` | obnoxious |

¹ **c3c's default validation level is `strict`, not `lenient`.** In
`builder.c3`, `VALIDATION_NOT_SET` falls through to `VALIDATION_STRICT`. This
matters for the one row above that is a warning knob rather than a hard error:
`dead_code` is `WARN` at default and strict, `ERROR` at obnoxious, and `SILENT`
only under an explicit `--validation=lenient`. Every other row above is a hard
error that no validation level can gate, since only 8 warning knobs exist and
none of them cover those diagnostics.

Note that printf checking is driven by the **`@format(0)` attribute** on the
stdlib declaration, so it is user-extensible. We do not reimplement it.

### Confirmed gaps — zero diagnostics at default, strict *and* obnoxious

Each verified as an isolated, otherwise-clean file:

24 confirmed gaps in eight families; `CHECKS.md` is the full catalog. The two
that matter most, because c3c has no coverage of either:

- **Temp-memory escapes** — a `talloc` pointer returned from a function, escaping
  a `@pool()` body, stored in a returned struct or a global, or passed to
  `mem::free`. All five compile clean. All five are use-after-free.
- **Fault hygiene** — `if (catch f()) {}` with an empty body, `(void)f()` to
  silence an Optional, an unused `catch`/`try` binding. c3c forces you to
  *handle* an Optional; it never checks that you did anything.

Then the classic syntactic set (`a = a`, `a == a`, `a - a`, duplicated if/else
branches, `float ==`, `if (int)`, `if (x) {}`, a loop that never advances,
`defer` in a loop), declaration hygiene (unused import, unused label, unused
private decl, missing `@format`), contract hygiene, and two constant-arithmetic
cases.

One of those is nearly free to fix upstream: `DIAG_UNUSED_IMPORT` already exists
in c3c's diagnostic enum and simply has no CLI knob wired to it.

### Three structural defects in c3c that c3vet exploits

1. **No suppression mechanism.** Grepping c3c's source for
   `nowarn|suppress|allow_warning` returns nothing. There is no way to say
   "yes, I meant this here." A vet tool without per-site suppression is unusable
   in CI; c3c cannot offer one.
2. **No project scoping.** `--validation=obnoxious` reports errors *inside the
   standard library* (65 diagnostics for a 24-line probe file, the overwhelming
   majority from `lib/std/`). It is effectively unusable on a real project.
3. **Coarse granularity.** c3c has exactly 8 warning knobs over ~17 internal
   diagnostic classes, each only `no|yes|error`. No per-check control.

### Positioning

> c3vet complements c3c. It never reimplements a diagnostic the compiler already
> produces. It owns the legal-but-wrong patterns, and it gives them the
> per-check granularity, per-site suppression, and project-scoped output that
> the compiler structurally cannot.

Division of labour across the toolchain: **c3f** owns style, **c3c** owns
legality, **c3vet** owns suspicion.

### Why not just expand `c3c --validation=obnoxious`?

The honest answer is: **for a real subset of the catalog, we should — and the
plan now says so explicitly.**

Testing this objection immediately paid for itself. Probing the checks this
document had listed as `proposed` found **five already implemented in c3c**:
duplicate `case` values, duplicate module imports, duplicate struct members,
double-assignment in an initializer, and unknown attribute names all produce
errors today. That was an entire planned work lane, deleted by asking the
question.

Three further honest concessions:

1. **The "structural defects" above are fixable upstream.** Suppression,
   project scoping and finer granularity are all things c3c *could* grow. They
   are arguments about cost and upstream acceptance, not about impossibility.
   The one durable wrinkle: c3c's existing suppression model is a dedicated
   attribute per warning class (`@unused`, `@allow_deprecated`). That does not
   scale to thirty heuristic checks, whereas `// c3vet:ignore[name]` does.
2. **c3c has strictly better information.** It has a typed AST. `float-equal`
   and `cond-not-bool` need types that c3vet only approximates from
   *declared* types, and `missing-format-attr` is near-trivial in a compiler
   that already owns the attribute table.
3. **Several remaining checks genuinely belong upstream**, not here — see the
   triage column in `CHECKS.md`. `unused-import` is the clearest case:
   `DIAG_UNUSED_IMPORT` already exists in c3c's diagnostic enum and simply has
   no CLI knob wired to it. That is a few lines of c3c, not a check in a new
   tool, and it should be sent upstream regardless of what happens to c3vet.

What genuinely cannot move into the compiler:

- **Heuristic checks with a non-zero false-positive rate.** A compiler warning
  must be essentially perfect: people build with warnings-as-errors, so every
  false positive is a broken build and a bug report. A vet finding with
  per-site suppression can afford to be 98% right. `defer-in-loop`,
  `loop-no-advance`, `cond-not-bool` and `pool-escape` are judgement calls that
  no compiler should ship.
- **Running on code that does not compile.** This is architectural, not a
  missing feature. The first probe run for this document was *wrong* precisely
  because a shadowing error suppressed all later analysis — c3c stops. Vet
  while typing, and vet in an editor, requires a parser that recovers and keeps
  going.
- **Project-specific policy**, which a compiler will never host.
- **`--fix`**, which compilers do not do.
- **Iteration speed, and the ability to measure before proposing.** c3vet can
  run a candidate check over 642 files, count the false positives, and only
  then argue for it upstream. You cannot run that experiment inside a compiler
  release cycle.

**The arithmetic, stated plainly.** A first triage left nine vet-owned checks,
six of them heuristic — not enough to justify a tool, and this document said so.
Then the probe was widened from `go vet`'s classic catalog to **C3's own hazard
surface**, and the picture changed:

- **33 constructs** are confirmed covered by c3c. Nine previously-planned checks
  were deleted on that evidence.
- **24 gaps** are confirmed across eight families — and two of those families
  are the reason to build this.

**Family A, temp-memory discipline: five probes, five gaps, zero compiler
coverage.** Returning a `talloc` pointer, letting one escape a `@pool()` body,
storing one in a returned struct or a global, calling `mem::free` on one — every
single one is a use-after-free, and nothing in the toolchain looks for any of
them today.

**Family B, Optional and fault hygiene: five probes, five gaps.** c3c *forces*
you to handle an Optional but never checks that the handling does anything. An
empty `if (catch f()) {}` swallows the fault silently and compiles clean.

Those two families are not heuristic, they are the highest-severity classes
available, they are specific to C3's arena and Optional models, and a compiler
structurally will not adopt them — they are judgements about *intent and
discipline*, not legality. c3c cannot reject `(void)risky()`; it suggests it as
the escape hatch.

So the premise survives, but **the tool's centre of gravity moved**. This is not
a `go vet` port, and the classic copy-paste checks are the least interesting
thing in it. It is a checker for the two disciplines C3 asks of you and does not
enforce: *did you really handle that fault*, and *does that allocation outlive
its arena*.

**And the parser remains the durable asset regardless.** C3 has
no reusable parser library. `c3f` had to invent its own token model; `c3c-fuzz`
reached for tree-sitter; c3c's own parser is C, welded to its semantic layer.
A standalone, recovering C3 parser in C3 is infrastructure the whole ecosystem
lacks — which is why it is now a separately carve-out-able library (§2, and
`DESIGN.md` §1.5). c3vet is its first consumer and the incubator where checks
are measured; checks that prove out as zero-FP and type-decidable should
**graduate into c3c**, and that is recorded as a success of this project rather
than a loss of scope.



---

## 2. Decisions taken

| Decision | Choice | Consequence |
|---|---|---|
| Niche | Complement c3c, own engine | Zero overlap with the table above; overlap is a bug |
| Core IR | **Own recursive-descent parser** on `lexer.c3l` | Real AST from day one; we own a C3 parse-level grammar |
| Dependencies | **`lexer.c3l` only**, via `c3l` | No tree-sitter, no C deps, no coupling to c3f |
| Parser | **Standalone, carve-out-able library** (`module c3::parser`) | Depends only on `lexer.c3l`; never imports `c3vet`; enforced by a CI target that builds it alone. `DESIGN.md` §1.5 |
| v1 surface | **CLI only**, go-vet style | No library API, no JSON/SARIF, no `--fix` in v1 |

Spans are recorded on every AST node anyway, so `--fix`, LSP and SARIF stay
cheap to add later. That is deliberate insurance, not scope creep.

---

## 3. Foundation check (done — one real blocker found)

- `lexer.c3l` **v0.1.1 as published to `c3l`** builds clean and is correct
  against c3c 0.8.7. Its `Token` already carries `offset`, `len`, `ln`, `col`,
  which is exactly what precise diagnostics need. **Use this.**
- The working clone at `~/Documents/lexer.c3l` (HEAD Jan 30 2026, 961 lines) is
  **stale and does not compile** against 0.8.7 — three `enum X : inline T`
  sites, removed from the language. Its token set also differs materially from
  v0.1.1 (v0.1.1 adds `AT`, `HASH`, `UNDERSCORE`, `UNTYPEDLIST`, `ATTRMACRO`,
  `CONSTDEF`, `CONSTSET`, `CT_EMBED`, `CT_REFLECT`; drops `HASH_TYPE_IDENT`,
  `HASH_CONST_IDENT`; renames `BFLOAT16`→`BFLOAT`).
  **Do not develop against the local clone.** `c3l` fetch only.
- `c3c -P` ("output the AST as JSON") is **not usable**: it is a
  declaration-surface dump (modules/types/functions/globals/constants, no
  statement bodies, no source positions), it includes the entire stdlib, and on
  a 24-line input it emitted 1.5 MB and then segfaulted. Ruled out as a source
  of semantic data.
- **The corpus is two corpora, not one.** `c3c/test/test_suite/` holds 816
  files of which **662 carry `// #error` annotations** — they are deliberately
  invalid, written to exercise the compiler's diagnostics. A "zero parse errors"
  gate over them is unachievable by construction. The split:
  - **Conformance corpus — 642 files** (`c3c/lib` 366 + `c3c/test/unit` 276),
    all valid C3. Requirement: **zero `ERROR` nodes.** This is exactly the
    corpus `lexer.c3l`'s own `test.sh` validates against, which is why we trust
    it.
  - **Resilience corpus — 816 files** (`c3c/test/test_suite`). Requirement: no
    crash, no hang, structural invariants still hold, and a bounded number of
    diagnostics per file. Many of these fail *semantic* rather than syntactic
    analysis, so most should in fact parse cleanly — but we assert resilience,
    not success.
- Authoritative grammar: `~/Documents/c3c/resources/grammar/grammar.y`
  (1369 lines, bison). This is the parser's specification. Precedence chain is
  recorded in `DESIGN.md`.

---

## 4. Analysis tiers

Each check declares the **minimum** tier it needs; the engine builds only the
layers that enabled checks actually require.

| Tier | Provides | Cost |
|---|---|---|
| **T1 `SYNTAX`** | AST of one file. Structural subtree comparison, literals, spans. | Parse only |
| **T2 `LOCAL`** | Per-function scope map (params + locals with *declared* types) and statement reachability. | One extra walk per function |
| **T3 `PROJECT`** | Declaration table across all project files: every decl's name, kind, attributes, signature. Resolves "is this callee `@format`?". | One extra pass over all units |

We deliberately stop before type inference. No tier reimplements c3c's type
system; T2 uses only *declared* types, which is enough for every check in the
catalog.

---

## 5. Phases

Each phase has a hard gate. A phase is not done until its gate is green.

### Phase 0 — Foundation (orchestrator alone, **not parallelizable**)

`git init` as the first action — two agents editing an unversioned tree is the
first thing that will go wrong.

Freeze, in one sitting: `ast.c3` (node layout + the per-kind field contract),
`error.c3`/`api.c3` (the parser's public surface), `diag.c3`, `engine.c3` (the
`Check` interface), the testdata harness format, and `docs/WORKPLAN.md`
ownership rules. Scaffold `project.json` with the `c3l` dependency on `lexer`
and the standalone `parser` library target.

Also, before any lane assignment goes out: **re-probe all eight Phase 2 T1
checks** against the pinned c3c as isolated compiling files. This is the
operation that already deleted five checks from the catalog; running it on the
remainder costs fifteen minutes and prevents three agents building something
the compiler already covers.

**Gate:** a stub check finds one hardcoded diagnostic end-to-end through the
real CLI; the harness runs one testdata file; `c3c build parser` builds
`src/parser/` alone; and every Phase 2 check row has been probed. Interfaces
committed and declared frozen.

### Phase 1 — Parser

The large, serial-ish piece. Splits cleanly along grammar areas (see
`WORKPLAN.md`). Panic-mode recovery from the start: vet must work on
half-written code.

**Gate (the important one):** the **642-file conformance corpus** parses with
**zero** `ERROR` nodes, and all four structural invariants in `DESIGN.md` §6
hold on every file. Separately, the **816-file resilience corpus** must not
crash, hang, or violate an invariant. This is the same methodology that
validated `lexer.c3l` and `c3f`.

### Phase 2 — Engine + T1 checks + CLI

Families C, D (T1 part), E and H — the copy-paste, condition, loop-intent and
constant-arithmetic checks. Full CLI: file/dir/project targets, per-check
`--enable`/`--disable`, suppression comments, config, exit codes.

**Gate:** every check has testdata; zero false positives over the full corpus;
`c3vet` on its own source is clean.

### Phase 2.5 — Upstream triage (orchestrator, short)

Before Phase 3 starts: re-probe the seven still-unprobed `proposed` rows —
`dead-store`, `shadow-stdlib`, `test-signature`, `contract-unknown-param`,
`contract-missing-return`, `unused-private-decl`, `pool-escape` — against the
pinned c3c, update the triage column, and delete anything the compiler covers.
(Phase 2's own rows are probed back in step 0.11, before any lane starts.) Open c3c issues or patches for the `upstream` rows — starting with
wiring a CLI knob to the already-existing `DIAG_UNUSED_IMPORT`.

**Gate:** no `proposed` check enters Phase 3 unprobed, and every `upstream` row
has an issue or patch link recorded next to it.

### Phase 3 — T2: local scopes and reachability

**Families A and B — the two that justify the tool.** Temp-memory escape
tracking (narrow and syntactic: locals initialized from `talloc`/`tmem`, then
the five escape shapes) and Optional/fault hygiene. Plus `float-equal` and
`cond-not-bool`.

**Gate:** zero FPs over corpus. Each check's `default_on` is decided *by* its
measured FP count, not by taste.

### Phase 4 — T3: project declaration table

Families F and G: `missing-format-attr`, `unused-import`, `unused-private-decl`,
`unused-label`, `contract-void-return`, `contract-tautology`.

**Gate:** zero FPs over corpus; the `@format` check, run over the stdlib, must
agree with what c3c's `@format` machinery already knows.

Note that Phase 3 now carries the highest-value work, so if the project is ever
cut short, **cut Phase 2, not Phase 3.**

### Phase 5 — Hardening and release

FP sweep, performance, `c3vet.1` man page, README, CI workflow, `c3l` publish.

**Gate:** the 642-file conformance corpus in **< 0.5 s** (c3f formats the
366-file stdlib in 0.14 s; a parse-only vet has no excuse to be slower than a
formatter). Peak memory < 50 MB.

---

## 6. Verification strategy

Four independent mechanisms, because a vet tool's only real currency is its
false-positive rate:

1. **Corpus conformance.** 642 valid files must parse with zero `ERROR` nodes;
   816 deliberately-broken files must not crash the tool. Non-negotiable.
2. **Structural invariants.** Token coverage, span nesting, edge validity,
   idempotence (`DESIGN.md` §6). These catch parser bugs that conformance misses.
3. **Testdata golden files.** `// want "regex"` annotations on the offending
   line, matched 1:1 against emitted diagnostics — `go vet`'s `analysistest`
   convention.
4. **Differential oracle against c3c.** For any check that *might* overlap a
   compiler diagnostic, run both over the corpus and diff. Any agreement is a
   bug in c3vet (we promised zero overlap); any c3vet-only finding on stdlib
   code is a probable FP. This gives ground truth for free, with no hand
   labelling.

**FP gate rule:** a check ships `default_on` only after a clean run over the
642-file conformance corpus.
Checks that cannot reach zero FPs ship opt-in, or do not ship.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| **We now own a third C3 grammar implementation** (c3c's, lexer.c3l's token level, c3vet's parse level) and must track 0.8 → 1.0 drift. This is the real cost of the parser decision and it is permanent. | `grammar.y` is the single spec. Corpus conformance in CI turns every drift into a loud, located test failure rather than silent wrong output. Pin the c3c version in CI and bump deliberately. The cost is also *amortised*: as a standalone library the parser serves LSP, doc and refactoring tools too, so the ecosystem maintains one parse-level grammar instead of each tool inventing a partial one. |
| Checks are built here that should have been c3c patches | The upstream triage in `CHECKS.md` is a required column, not advice. Re-probe every `proposed` check against c3c *before* implementing it — doing so already deleted five. |
| Parser is the long pole; checks are cheap once it exists | Phase 1 gate is objective and mechanical; no judgement calls block it |
| C3's compile-time constructs (`$if`, `$foreach`, `$switch`, generics, macros, contracts, `asm` blocks) are large grammar areas with little vet value | Parse them **structurally** — correct spans and nesting, shallow interior. Never skip them: unparsed regions silently disable checks around them |
| Checks drift into style and start fighting c3f | Charter: if c3f would reformat it, it is not a c3vet finding |
| Suppression comments become a way to hide real bugs | `--no-suppress` flag for audit runs; report suppression counts in the summary |

---

## 8. Explicitly out of scope for v1

Library API (`api.c3`) · JSON / SARIF output · `--fix` autofixes · LSP server ·
type inference · cross-project/whole-dependency analysis · style and formatting
(that is `c3f`) · anything in the §1 "already diagnosed" table.

# c3vet

A vet tool for [C3](https://c3-lang.org): reports **suspicious but legal**
code — constructs that compile cleanly and are almost certainly not what the
author meant.

> **Status: Phase 0.** The parser and engine skeleton are in place and the
> interfaces are frozen. No real checks ship yet. See `docs/ROADMAP.md`.

## What it is for

`c3c --validation=obnoxious` is already a capable vet, and c3vet never
reimplements a diagnostic the compiler produces — overlap is a bug, enforced by
`scripts/probe-overlap.sh`. c3vet owns what c3c has no coverage of, chiefly two
families specific to C3:

- **Temp-memory discipline** — a `talloc` pointer returned from a function,
  escaping a `@pool()` body, stored in a returned struct or a global, or passed
  to `mem::free`. All compile clean. All are use-after-free.
- **Fault hygiene** — `if (catch f()) {}` with an empty body swallows the fault
  silently. c3c forces you to *handle* an Optional; it never checks that the
  handling does anything.

Plus per-check granularity, per-site suppression (c3c has none at all), and
project-scoped output. Division of labour: **c3f** owns style, **c3c** owns
legality, **c3vet** owns suspicion.

## Build

```sh
c3l sync          # fetch lexer.c3l
c3c build         # -> build/c3vet
c3c test
```

## Use

```sh
c3vet                    # the current project's sources
c3vet src/ file.c3       # explicit paths
c3vet --list-checks
c3vet --enable=a,b --disable=c
c3vet --no-suppress      # audit run: ignore every suppression comment
```

Exit codes: `0` clean, `1` findings, `2` tool error. Findings go to stdout and
tool errors to stderr, so `c3vet | wc -l` works in CI.

### Suppression

```c3
a = a;                        // c3vet:ignore
a = a;                        // c3vet:ignore[self-assign]
// c3vet:ignore[self-assign]     applies to the next line too
// c3vet:ignore-file[float-equal]
```

A suppression counts when it sits anywhere inside the reported construct, or
on the line just before it. Suppressed findings are always counted in the run
summary — one you have forgotten about hides a real bug.

## The parser

`src/parser/` is a standalone library (`module c3::parser`) depending only on
`lexer.c3l`, designed to be lifted out into its own `parser.c3l`. C3 has no
reusable parser; `c3f` built a bespoke token model and `c3c-fuzz` reached for
tree-sitter because none existed.

```c3
ParseResult r = parser::parse(mem, src);
defer r.free();
// r.ast, r.toks, r.errors -- never fails; malformed input yields ERROR_*
// nodes with valid spans, so it works on code that is being typed.
```

`scripts/check-carveout.sh` enforces the separation: it builds `src/parser/`
alone and rejects any reverse dependency on `c3vet`.

## Layout

| Path | What |
|---|---|
| `src/parser/` | standalone parser: lexing, AST, recovery |
| `src/c3vet/` | engine: checks, diagnostics, suppression, config |
| `src/cli/` | the `c3vet` command |
| `testdata/` | one annotated data file per check |
| `scripts/` | carve-out and overlap gates |
| `docs/` | roadmap, design, check catalog, work plan |

## License

MIT

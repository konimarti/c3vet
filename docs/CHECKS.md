# c3vet — Check catalog

Every check must answer yes to all five:

1. **Does it compile?** If `c3c` already rejects it, c3vet stays quiet.
2. **Is it probably a bug?** Not a style preference. If `c3f` would reformat it,
   it is not a c3vet finding.
3. **Can we be nearly certain?** A check that cannot reach zero false positives
   over the 642-file conformance corpus ships opt-in, or not at all.
4. **Is the message actionable?** It names the symbol and says what is wrong,
   never "consider reviewing this".
5. **Is c3vet the right home?** If a check is zero-FP and decidable with types,
   c3c is the better home and we should send a patch there. Graduating a check
   upstream is a success.

**Probe before you implement.** Every `proposed` check is re-probed against the
pinned c3c first, as an isolated compiling file. Doing this has already deleted
**nine** checks from this document; see the rejected table at the end.

---

## What the compiler already covers

33 constructs probed and confirmed diagnosed by c3c 0.8.7 — see
`ROADMAP.md` §1 and the rejected table below. The short version: c3c is strong
on **types, arithmetic, legality, and declaration-level duplication**, and it
*forces* you to handle Optionals.

It has **near-zero coverage of two things**: whether you handled an Optional
*meaningfully*, and whether a temp-memory allocation outlives its arena. Those
are c3vet's centre of gravity.

---

## Family A — Temp-memory and allocator discipline  (T2/T3)

**The strongest family in the catalog.** Five probes, five gaps, zero compiler
coverage — and every one of them is a use-after-free, the highest-severity class
there is. C3's arena/temp-allocator model is powerful and easy to get wrong, and
nothing in the toolchain checks it today.

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `temp-escapes-fn` | a `talloc`/`tmem`-derived pointer or slice returned from a function | confirmed | vet |
| `temp-escapes-pool` | a `talloc` inside `@pool() { ... }` assigned to a variable declared outside the pool body | confirmed | vet |
| `temp-escapes-struct` | a `talloc` stored into a field of a struct that is then returned | confirmed | vet |
| `temp-wrong-free` | `mem::free` called on a `talloc`-derived pointer | confirmed | vet |
| `temp-to-global` | a `talloc` assigned to a global or `tlocal` | confirmed | vet |

These need escape reasoning, which is why they are T2 (intra-function) and
deliberately **syntactic and narrow**: track locals whose initializer is a
`talloc`/`tmem` call, then report the five shapes above. No alias analysis, no
interprocedural reasoning. A pointer that passes through a function call is not
tracked and not reported — false negatives are acceptable here, false positives
are not.

---

## Family B — Optional and fault hygiene  (T1/T2)

c3c forces you to *handle* an Optional — `error: ... must be handled` — but does
not check that the handling does anything. Five probes, five gaps.

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `swallowed-fault` | `if (catch f()) {}` — an empty catch body, no comment inside. The fault is discarded silently | confirmed | vet |
| `silenced-fault` | `(void)f()` on an Optional-returning call. c3c *suggests* this as the escape hatch, so it is legal by construction — but it should be visible in review | confirmed | vet, opt-in |
| `unused-catch-binding` | `if (catch err = f())` where `err` is never read. Not caught by c3c's unused-local even at obnoxious | confirmed | vet |
| `unused-try-binding` | `if (try v = f())` where `v` is never read | confirmed | vet |
| `force-unwrap` | `!!` outside tests and `main` — it panics in production | confirmed | vet, opt-in (policy) |

`silenced-fault` and `force-unwrap` are policy rather than bug-finding, hence
opt-in. They are exactly the kind of check a compiler cannot ship and a project
lead wants in CI.

---

## Family C — Copy-paste and self-reference  (T1)

`ast::same_expr` does the work. It compares kind + token text recursively and
**returns false if either subtree contains a call, `++`/`--`, an assignment, or
a deref/volatile load** — without that guard, `f() == f()` and `*p == *p` become
false positives.

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `self-assign` | `a = a`, `obj.f = obj.f`, `arr[i] = arr[i]` | confirmed | **upstream** — zero FP, trivial in sema |
| `self-compare` | `a == a`, `a != a`, `a < a`, `a >= a` | confirmed | **upstream** — same |
| `self-op` | `a - a`, `a / a`, `a % a`, `a ^ a`, `a & a`, `a \| a` | confirmed | **upstream** — same |
| `dup-branch` | identical condition, or identical body, repeated in one if/else chain | confirmed | vet |

The three `self-*` checks are still implemented here **first**: they are the
simplest exercise of `same_expr` and the harness, they prove the engine
end-to-end, and their measured FP count over 642 files is the evidence a c3c
patch proposal needs.

---

## Family D — Suspicious conditions  (T1/T2)

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `float-equal` | `==`/`!=` where either side is a float literal or a variable declared `float`/`double`/`float16`/`bfloat`/`float128` | confirmed | **both** — c3c has real types and would be more precise; too opinionated to be on by default there |
| `cond-not-bool` | `if (n)`/`while (n)` where `n` is declared integer or pointer. C3 permits it deliberately, so a compiler warning would be wrong | confirmed | vet |
| `const-cond` | `if (1 == 2)`, `while (false)` — literal-only condition | confirmed | vet — `if (false)` is a legitimate dead-code toggle |
| `empty-body` | `if (c) {}` / `while (c) {}`, empty block, no comment inside | confirmed | vet |

---

## Family E — Loop intent  (T1/T2)

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `loop-no-advance` | `for (i = 0; i < n;)` with an empty increment slot and no identifier from the condition assigned, `++`/`--`, or address-taken in the body | confirmed | vet |
| `defer-in-loop` | `defer` in a loop body — runs at *function* exit, not per iteration. A genuine and common misreading | confirmed | vet |
| `empty-loop-body` | a loop whose body is empty and whose condition has no side effects | confirmed | vet, opt-in |

`loop-no-advance` carries the most FP risk here (the counter may advance through
a pointer, or the loop may exit via `break`). `while (true)` without a `break`
is **deliberately excluded** — event loops are a legitimate and common shape.

---

## Family F — Declaration hygiene  (T3)

Needs the project-wide declaration table over the **indexed** scope
(`DESIGN.md` §5).

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `missing-format-attr` | a function whose last parameter is `args...` which passes an earlier `String` parameter to a `@format` callee, but lacks `@format(n)` itself. Adding the attribute makes c3c check every call site forever | confirmed | **both** — near-trivial in c3c, valuable here meanwhile |
| `unused-import` | an `import` whose module is never used — neither as a `mod::name` prefix nor via an unqualified exported name | confirmed | **upstream** — `DIAG_UNUSED_IMPORT` exists in c3c with no CLI knob wired to it. Send that patch regardless |
| `unused-private-decl` | a `@private`/`@local` declaration never referenced in its module. Not covered even at obnoxious | confirmed | vet |
| `unused-label` | a declared label (`while FOO: (...)`) never targeted by a `break`/`continue` **in the same function body**. Labels are function-scoped: scan the enclosing `FN_DECL`, never the file, or two functions each using `FOO:` produce false positives | confirmed | **upstream** — `DIAG_UNUSED_LABEL` exists in c3c's enum |

`unused-import` is T3 rather than T1 because C3 permits using an imported
module's symbols **unqualified**, so one file's tokens cannot answer it. Be
conservative: report only when neither the module path nor any name it exports
appears in the file. Note that `import` pulls in sub-modules too, so a
`std::net` import is used if `std::net::tcp` is referenced — getting that wrong
is the one real FP risk here.

---

## Family G — Contract hygiene  (T3)

Contracts are trivia; read them with `lexer::ContractLexer` on demand
(`DESIGN.md` §2).

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `contract-void-return` | `@return` documented on a function returning `void` | confirmed | **upstream** |
| `contract-tautology` | `@require n == n` and similar always-true contracts | confirmed | vet |

---

## Family H — Constant arithmetic  (T1)

| Check | Fires on | Status | Triage |
|---|---|---|---|
| `const-int-div-to-float` | `float g = 1 / 2;` — integer division folded, then widened. **Literals only**: with `int` *variables* c3c already requires an explicit cast | confirmed | **upstream** |
| `const-narrowing-overflow` | `(char)100000` — an explicit cast of a constant that cannot represent it | confirmed | **upstream** |

---

## Rejected — the compiler already does it

Each row probed as an isolated compiling file against c3c 0.8.7. The nine marked
† were planned checks in an earlier draft of this document, deleted on evidence.

| Not doing | c3c says |
|---|---|
| printf arity and type | `Too few/many arguments for the formatting string`; `Expected a number here, but ... 'String'` |
| shadowed declarations | `'x' would shadow a previous declaration` |
| `return &local` | `A pointer to a local variable will be invalid once the function returns` |
| unsigned `< 0` | `Comparing 'unsigned expression < 0' can never be true` |
| shift overflow / negative shift | `The shift (40) is not less than the bitsize`; `A shift must be a positive number` |
| `&` vs comparison precedence | `You need to add explicit parentheses to clarify precedence` |
| naming conventions | `Names of enums cannot be all uppercase` etc. |
| unused parameters / locals | `The parameter 'x' is never used` (obnoxious) |
| code after `return` **or `break`** † | `This code will never execute` — on by default, since c3c's default validation level is `strict` |
| duplicate `case` values † | `The same case value appears more than once` |
| duplicate struct/union members † | `Duplicate member name 'alpha'` |
| duplicate module imports † | `Module 'std::io' imported more than once` |
| double-assignment in an initializer † | `This element is assigned twice in the same initializer` |
| unknown attribute names † | `This is not a known valid attribute name` |
| contract `@param` unknown name † | `There is no parameter 'nonexistent', did you misspell it?` |
| `@test` with parameters † | `'@test' and '@benchmark' functions may not take any parameters` |
| `@test` non-void return † | `'@test' ... may only return 'void'` |
| missing enum case in `switch` | `Enum value BLUE was not handled in the switch` |
| assignment in a condition | `An assignment in a conditional must have an extra parenthesis` |
| signed/unsigned comparison | `'int' cannot implicitly be narrowed to 'uint'` |
| struct `==` | `'Pair' does not support comparisons` |
| `defer` containing `return` | `Return is not allowed inside of a defer` |
| constant array index out of range | `An index of '5' is out of range` |
| reversed slice range | `The start index (3) should not be greater than the end index (1)` |
| unhandled Optional return | `... is an optional and must be handled` |
| `@nodiscard` result ignored | `The called function is marked '@nodiscard'` |
| `bool + int` | `Cannot do the addition 'bool' + 'int'` |
| int/int widened to float (variables) | `This conversion requires an explicit cast to 'float'` |
| importing the current module | `Importing the current module is not allowed` |

## Rejected — not our job

| Not doing | Why |
|---|---|
| `while (true)` without `break` | event loops; FP rate would be absurd |
| `do {} while (false)` | a legitimate break-out idiom |
| large struct passed by value | performance, not correctness |
| negative modulo | language-defined behaviour, not a bug |
| `mem::new` without a matching `free` | needs real interprocedural escape analysis; out of reach and FP-prone |
| TODO/FIXME scanning, line length, comment style | not correctness |
| cyclomatic complexity, function length | metrics, not bugs |

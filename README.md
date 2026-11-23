# c3vet

A vet tool for [C3](https://c3-lang.org): reports **suspicious but legal**
code, constructs that compile cleanly and are almost certainly not what the
author meant.

## Why use it

c3vet only reports what `c3c --validation=obnoxious` can't see.
It never repeats a compiler warning.

What it catches:

- **Temp memory misuse.** Temp-allocated memory (`talloc`, or a stdlib `t`-prefixed convenience like `string::tformat`) that is returned, escapes a `@pool()` body, lands in a returned struct or a global, or goes to `mem::free`. All of these compile, and all of them are use after free.
- **Swallowed faults.** `if (catch f()) {}` with an empty body drops the fault. C3 makes you handle an Optional but doesn't check that the handling does anything.
- **Copy and paste slips** like `a = a`, `if (a == a)` or the same condition twice in an if/else-if chain.
- **Dead code and stuck loops**, e.g. a loop that never advances, empty bodies, unused labels, imports and private declarations.
- **Suspicious constants**, e.g. a literal that overflows its cast or integer division turned into a float.
- **C3 specific traps**, e.g. a `defer` that runs on every loop iteration instead of once, or a contract that can never fail.
- **Non-idiomatic C3** (off by default), e.g. `mem::free(p)` where `free(p)` is enough, an explicit `= { }` on a local, or a catch-and-assign-default that should be `x = v ?? {};`.

And more: 35 checks in total, 16 of them on by default. `c3vet --list-checks` shows them all.

What the compiler doesn't give you:

- Every check can be turned on or off on its own.
- Findings can be silenced per line with a comment.

## Example

```c3
module demo;
import std::core::mem;

fn int* bad_escape()
{
	int* p = mem::talloc(int);
	return p;
}

fn void bad_catch(int? risky)
{
	if (catch risky)
	{
	}
}

fn void bad_assign(int a)
{
	a = a;
}

fn void bad_dup_branch(int x)
{
	if (x == 1) {}
	else if (x == 1) {}
}
```

```
$ c3vet --enable=temp-escapes-fn demo.c3
demo.c3:7:2: temp-allocated memory returned from a function -- allocate with a non-temp allocator if the value must outlive this call [temp-escapes-fn]
demo.c3:12:2: fault is swallowed by an empty catch branch -- handle it, log it, or document why it's safe to ignore [swallowed-fault]
demo.c3:19:2: self-assignment: this assigns the same value to itself -- remove it, or fix the typo if a different name was meant [self-assign]
demo.c3:25:7: duplicate condition in if/else-if chain -- this branch is unreachable; remove it, or use a switch if comparing one value against several cases [dup-branch]
demo.c3:25:7: duplicate block body in if/else-if chain -- merge the conditions with ||, or use a switch if comparing one value against several cases [dup-branch]
c3vet: 5 finding(s) in 1 file(s)
```

Each finding tells you how to fix it.

## Build

```sh
git clone --recurse-submodules https://github.com/konimarti/c3vet.git
cd c3vet
c3c build         # -> build/c3vet
c3c test
```

## Use

```sh
c3vet                    # the current project's sources
c3vet src/ file.c3       # explicit paths
c3vet --list-checks
c3vet --enable=a,b --disable=c
c3vet --enable-all       # every check, including the off-by-default ones
c3vet --no-suppress      # audit run: ignore every suppression comment
```

- Exit codes: `0` clean, `1` findings, `2` tool error.
- Findings go to stdout, errors to stderr, so `c3vet | wc -l` works in CI.
- Some checks are off by default. A check only runs by default once it has proven quiet on real code.
- `c3vet --list-checks` shows all checks and which ones need `--enable`.
- The full manual is in `man ./c3vet.1`.

### Project config

Put your usual `--enable`, `--disable` and `--no-suppress` choices in a `.c3vet` file at the project root:

```json
{"disable": ["cond-not-bool"]}
```

Or under a `"c3vet"` key in `project.json`:

```json
{
  "c3vet": {"disable": ["cond-not-bool"]}
}
```

- If both exist, `.c3vet` wins.
- Flags on the command line always win over either file.

### Suppression

```c3
a = a;                        // c3vet:ignore
a = a;                        // c3vet:ignore[self-assign]
// c3vet:ignore[self-assign]     applies to the next line too
// c3vet:ignore-file[float-equal]
```

- A comment works anywhere inside the reported construct or on the line before it.
- The run summary always counts suppressed findings, so a forgotten one can't hide a real bug.

## Checks

Output of `c3vet --list-checks`. Default: `on` runs without flags, `off` needs `--enable=<check>` or `--enable-all`.

| Check | Category | Default | What it reports |
|-------|----------|---------|-----------------|
| `self-assign` | syntax | on | self-assignment: the right side is identical to the left |
| `self-compare` | syntax | off | self-comparison: both sides of the comparison are identical |
| `self-op` | syntax | off | self-operation: both operands are identical, always producing a constant |
| `dup-branch` | syntax | on | an if/else-if chain repeats an earlier condition or block |
| `const-cond` | syntax | off | a control-flow condition is determined by literals alone |
| `const-int-div-to-float` | syntax | on | integer division of literals is converted to a floating value |
| `const-narrowing-overflow` | syntax | on | an integer literal is outside the range of its explicit cast type |
| `empty-body` | syntax | off | an if/while body that is an empty block with no comment inside |
| `empty-loop-body` | syntax | off | a loop whose body is empty and whose condition has no side effects |
| `loop-no-advance` | syntax | on | a for loop with no increment clause whose condition variables never change in the body |
| `unused-label` | syntax | on | a declared label never targeted by a break/continue in the same function |
| `temp-escapes-fn` | local | off | temp-allocated memory returned from a function |
| `temp-escapes-pool` | local | on | temp-allocated memory inside `@pool` assigned to a variable declared outside the pool |
| `temp-escapes-struct` | local | on | temp-allocated memory stored into a struct field and returned |
| `temp-wrong-free` | local | on | calling `free` on temp-allocated memory |
| `temp-to-global` | local | on | temp-allocated memory assigned to a global or thread-local variable |
| `swallowed-fault` | local | on | an empty catch branch silently discards a fault |
| `silenced-fault` | local | off | a void cast discards an Optional-returning call |
| `unused-catch-binding` | local | off | a catch binding is never read in its branch |
| `unused-try-binding` | local | on | a try binding is never read in its branch |
| `force-unwrap` | local | off | force unwrap outside a test or main function |
| `float-equal` | local | off | `==` or `!=` compares a float literal or a float-declared variable |
| `cond-not-bool` | local | off | if/while condition is a bare integer or pointer variable, not a boolean |
| `defer-in-loop` | local | off | a defer statement inside a loop body runs every iteration, not once |
| `contract-void-return` | local | on | an `@return` contract is documented on a function returning void |
| `contract-tautology` | local | on | a `@require` clause compares an expression to itself with `==` |
| `redundant-mem-free` | local | off | `mem::free` where `free` is enough: `mem::free(p)` is `free(p)`, and `mem::free(s.ptr)` on a slice is `free(s)` |
| `redundant-zero-init` | local | off | an explicit `= { }` on a local, which is zero-initialized anyway |
| `mem-copy-slice-to-array` | local | off | `mem::copy` of a slice into a fixed array: use `arr[:n] = src[:n]` |
| `catch-default-operator` | local | off | catch-and-assign-default: use `x = v ?? {};` |
| `missing-format-attr` | project | on | function forwarding a format string and varargs without `@format` attribute |
| `unused-import` | project | off | an imported module is not referenced in this file |
| `unused-private-decl` | project | off | a private or local declaration is never referenced in scope |

`parse` is not a check you configure. It reports files that fail to parse, and later checks may be skipped for them.

## License

MIT

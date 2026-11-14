# c3vet

A vet tool for [C3](https://c3-lang.org): reports **suspicious but legal**
code — constructs that compile cleanly and are almost certainly not what the
author meant.

## Why use it

`c3c --validation=obnoxious` is already a capable compiler warning set.
c3vet never repeats a warning the compiler already gives you — it only
reports things the compiler has no way to see, chiefly two families
specific to C3:

- **Temp-memory discipline** — a `talloc` pointer returned from a function,
  escaping a `@pool()` body, stored in a returned struct or a global, or
  passed to `mem::free`. All of these compile cleanly. All of them are
  use-after-free.
- **Fault hygiene** — `if (catch f()) {}` with an empty body silently
  swallows the fault. C3 forces you to *handle* an Optional; it never checks
  that the handling actually does anything.

Plus copy-paste mistakes (`a = a`, `if (a == a)`), dead-giveaway dead code,
and a handful of C3-specific traps like `defer` running every loop iteration
instead of once.

It also has per-check granularity and per-line suppression comments, which
the compiler has none of, so you can turn a check on project-wide and quiet
it down case by case where it's wrong.

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
```

```
$ c3vet --enable=temp-escapes-fn demo.c3
demo.c3:7:2: temp-allocated memory returned from a function -- allocate with a non-temp allocator if the value must outlive this call [temp-escapes-fn]
demo.c3:12:2: fault is swallowed by an empty catch branch -- handle it, log it, or document why it's safe to ignore [swallowed-fault]
demo.c3:19:2: self-assignment: this assigns the same value to itself -- remove it, or fix the typo if a different name was meant [self-assign]
c3vet: 3 finding(s) in 1 file(s)
```

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
c3vet --no-suppress      # audit run: ignore every suppression comment
```

Exit codes: `0` clean, `1` findings, `2` tool error. Findings go to stdout and
tool errors to stderr, so `c3vet | wc -l` works in CI.

To fix the same `--enable`/`--disable`/`--no-suppress` choices for a project
instead of retyping them, drop them in a `.c3vet` file (or a `"c3vet"` key in
`project.json`) at the project root:

```json
{"disable": ["cond-not-bool"]}
```

A command-line flag always wins over whatever the file says.

See `man ./c3vet.1` for the full manual.

Not every check is on by default — a check only runs automatically once it
has been proven not to cry wolf on real-world code. `c3vet --list-checks`
always shows the current set and which ones need `--enable`.

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

## License

MIT

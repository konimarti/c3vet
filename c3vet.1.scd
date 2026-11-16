C3VET(1)

# NAME

*c3vet* - a vet tool for C3: finds suspicious but legal code

# SYNOPSIS

*c3vet* [_OPTIONS_] [_PATH_ ...]

# DESCRIPTION

*c3vet* reports code that compiles cleanly under *c3c* but is almost certainly
not what the author meant. *c3c --validation=obnoxious* is already a capable
compiler warning set; *c3vet* never repeats a diagnostic the compiler already
gives (verified by *scripts/differential-oracle.sh*) and instead
covers what the compiler has no way to see: temp-allocator discipline,
Optional/fault hygiene, copy-paste mistakes, and a handful of C3-specific
traps such as `defer` running every loop iteration instead of once.

With no _PATH_, the current project's sources are used (the `sources` list in
_project.json_). A path may be a single file or a directory, walked
recursively; hidden directories and directories named _build_, _lib_ and
_out_ are skipped.

Every finding is one line: file, line, column, message, and the check name
in brackets, so a single check's output can be grepped or suppressed on its
own. Findings go to standard output; everything else (usage, errors, the run
summary) goes to standard error, so `c3vet | wc -l` is meaningful in a script
or a CI job.

Not every check runs by default - see *--list-checks*. A check is on
by default only when it is expected to produce no false positives; the rest are opt-in, usually because they encode a
project's own policy (`force-unwrap`, `silenced-fault`) rather than finding an
outright bug.

# OPTIONS

*--list-checks*
	List every check, its tier, whether it runs by default, and a one-line
	description.

*--enable=*_a_,_b_
	Run these checks in addition to the defaults. Repeatable; names may
	also be comma-separated in one flag.

*--disable=*_a_,_b_
	Do not run these checks, even if they are on by default. *--disable*
	always wins over *--enable*, so a broad *--enable* plus a narrow
	*--disable* behaves the way you would expect.

*--enable-all*
	Run every check, including the ones that are off by default.
	*--disable* still removes individual checks from the run.

*--no-suppress*
	Ignore every `// c3vet:ignore` comment. For an audit run that must see
	everything a normal run would quietly skip.

*-h*, *--help*
	Print the usage.

*-V*, *--version*
	Print the version.

# SUPPRESSION

```
a = a;                        // c3vet:ignore
a = a;                        // c3vet:ignore[self-assign]
// c3vet:ignore[self-assign]     applies to the next line too
// c3vet:ignore-file[float-equal]
```

A bare `c3vet:ignore` suppresses every check on that line; `c3vet:ignore[name]`
suppresses only the named check (several, comma-separated, is allowed). The
comment may sit on the reported line itself, or alone on the line directly
above it. `c3vet:ignore-file[name]` suppresses a check for the rest of the
file, wherever the comment is written.

A suppressed finding is not silently dropped: the run summary on standard
error always reports how many were suppressed, so a suppression nobody
remembers writing does not go unnoticed.

# EXIT STATUS

*0*
	No findings (suppressed findings, if any, are still reported on standard
	error).

*1*
	At least one finding was reported.

*2*
	Usage error, or a file or path could not be read.

# EXAMPLES

Run the checks that are on by default, over the current project:

```
c3vet
```

Run one specific check, project-wide, in addition to the defaults:

```
c3vet --enable=cond-not-bool
```

Run every check, as a one-off deep pass:

```
c3vet --enable-all
```

Audit run that ignores every suppression comment, over one directory:

```
c3vet --no-suppress src/
```

# FILES

_.c3vet_
	A JSON file in the project root, holding the same settings as the CLI
	flags:

```
{"enable": ["a", "b"], "disable": ["c"], "no-suppress": true}
```

	Wins over a "c3vet" key in _project.json_ if both exist. Either way,
	an explicit command-line flag always overrides a file setting for
	that one check.

_project.json_
	A "c3vet" key holding the same shape as _.c3vet_ above, for a project
	that would rather not add a second file:

```
{"c3vet": {"disable": ["c"]}}
```

# SEE ALSO

*c3c*(1), *c3f*(1)

# AUTHOR

c3vet was written by Koni Marti <koni.marti@gmail.com>.

<*
 The testdata runner.

 One file per check in test/testdata/, annotated go-vet style:

     count = count;        // want "self-assignment of 'count'"
     count = count + 1;    // no annotation: no diagnostic expected

 The match is required to be exactly 1:1. Every `want` must be matched by a
 diagnostic on that line, and every diagnostic must have a `want`. An
 unannotated diagnostic fails the test -- that is what stops false positives
 from creeping in unnoticed.

 ## Where the annotation goes

 On the line the diagnostic is REPORTED at, which for a multi-line construct
 is the line where it opens:

     {                 // want "empty block"
     }

 This is deliberately stricter than suppression comments, which match
 anywhere inside the construct (see suppress.c3). A test should pin down
 exactly where a finding points; a user writing `// c3vet:ignore` should not
 have to care. Do not relax this to match the span -- it would stop the tests
 from catching a diagnostic that drifts onto the wrong line.

 `want` text is matched as a substring, not a regular expression, so no
 dependency is needed and messages stay greppable.
*>
module c3vet::testdata;

import c3vet;
import c3::parser;
import c3::lexer;
import std::collections::list;
import std::io;
import std::io::path;
import std::os::env;

struct Want
{
	sz     ln;
	String text;
	bool   matched;
}

<*
 Run one check against one testdata file and assert an exact match.

 Looks `check_name` up in the registry (orchestrator-owned, `WORKPLAN.md`
 rule 3), so this only works once the check has landed in
 `c3vet::ALL_CHECKS`. A check mid-development should call `verify_check`
 below with its own `Check` literal instead -- same 1:1 `// want` match, no
 registry dependency.
 @param check_name : "the check to enable; every other check stays off"
 @param path : "path to the testdata file, relative to the project root"
*>
fn void verify(String check_name, String path)
{
	sz idx = c3vet::find_check(check_name);
	assert(idx >= 0, "no such check '%s'", check_name);
	verify_check(c3vet::ALL_CHECKS[idx], path);
}

<* Same match as `verify`, but takes the `Check` literal directly. *>
fn void verify_check(Check only, String path)
{
	char[]? bytes = file::load(tmem, path);
	if (catch bytes) unreachable("cannot read testdata '%s'", path);
	String src = (String)bytes;

	Unit u;
	u.path = path;
	u.src = src;
	u.parsed = parser::parse(tmem, src);
	u.suppress.init(tmem);
	u.suppress.collect(u.toks());

	List{Want} wants;
	wants.tinit();
	collect_wants(&wants, u.toks());

	DiagnosticList diags;
	diags.init(tmem);
	Config cfg;
	cfg.init(tmem);
	Ctx ctx = { .config = &cfg, .out = &diags };
	ctx.reported.init(tmem);

	Check[1] one = { only };
	c3vet::run_checks(&ctx, &u, one[..]);

	// Every diagnostic must be wanted.
	foreach (d : diags)
	{
		bool ok = false;
		foreach (i, w : wants)
		{
			if (w.ln != d.ln || w.matched) continue;
			if (!d.msg.contains(w.text)) continue;
			wants.set(i, { .ln = w.ln, .text = w.text, .matched = true });
			ok = true;
			break;
		}
		assert(ok, "%s:%d: unexpected finding '%s' (no matching want)", path, d.ln, d.msg);
	}
	// Every want must be produced.
	foreach (w : wants)
	{
		assert(w.matched, "%s:%d: wanted a finding containing '%s', got none", path, w.ln, w.text);
	}
}

<* Pull `// want "..."` out of the comment tokens. *>
fn void collect_wants(List{Want}* out, TokenList* toks) @local
{
	foreach (t : toks.all)
	{
		if (t.type != LINE_COMMENT && t.type != BLOCK_COMMENT) continue;
		sz at = t.text.index_of("want \"") ?? -1;
		if (at < 0) continue;
		String rest = t.text[(usz)at + 6..];
		sz end = rest.index_of_char('"') ?? -1;
		if (end < 0) continue;
		out.push({ .ln = t.ln, .text = rest[..(usz)end - 1] });
	}
}

<*
 Run `check_name`, with only it enabled, over every `*.c3`/`*.c3i` file in the
 same 642-file conformance corpus Phase 1 used (the sibling c3c checkout's
 `lib/` and `test/unit/`), and return the total finding count.

 This is the false-positive measurement every Phase 2 check's gate requires
 ("zero false positives over the 642-file conformance corpus") -- call it
 from a `@test` that asserts on the count you expect, so a regression is a
 normal test failure rather than something only visible in TEST LOG on
 failure (c3c's test runner only surfaces `io::printfn` output when the test
 itself fails).

 Returns 0 immediately, without asserting, when `C3C_CHECKOUT` is not found
 -- same policy as `conformance_corpus_is_clean`, so this is safe to call
 from a machine that does not have the sibling repo.

 Looks the check up in the registry, so it only works for a check already
 landed in `c3vet::ALL_CHECKS` (orchestrator-owned, `WORKPLAN.md` rule 3). A
 check mid-development, not yet registered, should call `measure_fp_check`
 below directly with its own `Check` literal instead -- same corpus sweep,
 no registry dependency, so a lane is never blocked measuring its own FP
 count before the orchestrator lands its entry.
*>
fn sz measure_fp(String check_name)
{
	sz idx = c3vet::find_check(check_name);
	assert(idx >= 0, "no such check '%s'", check_name);
	return measure_fp_check(c3vet::ALL_CHECKS[idx]);
}

<* Same sweep as `measure_fp`, but takes the `Check` literal directly. *>
fn sz measure_fp_check(Check check)
{
	String base = checkout_dir();
	if (!path::exists(path::tnew(base) ?? (Path){})) return 0;

	String lib_dir = string::tformat("%s/lib", base);
	String unit_dir = string::tformat("%s/test/unit", base);
	String[] files = find_c3_files(lib_dir);
	String[] unit_files = find_c3_files(unit_dir);

	Check[1] one = { check };

	sz total = 0;
	foreach (group : (String[][]){ files, unit_files })
	{
		foreach (f : group)
		{
			@pool()
			{
				char[]? bytes = file::load(tmem, f);
				if (catch bytes) continue;

				Unit u;
				u.path = f;
				u.src = (String)bytes;
				u.parsed = parser::parse(tmem, u.src);
				u.suppress.init(tmem);
				u.suppress.collect(u.toks());

				DiagnosticList diags;
				diags.init(tmem);
				Config cfg;
				cfg.init(tmem);
				Ctx ctx = { .config = &cfg, .out = &diags };
				ctx.reported.init(tmem);

				c3vet::run_checks(&ctx, &u, one[..]);
				total += diags.len();
			};
		}
	}
	return total;
}

<*
 The sibling c3c checkout used for the FP sweep above, found via
 C3C_CHECKOUT (default: /home/km/Documents/c3c). Own copy, not shared with
 parser.c3l's conformance test -- that library is a separate repository
 now (docs/DESIGN.md section 1.5), and this harness must not depend on it.
*>
fn String checkout_dir() @local
{
	String? v = env::tget_var("C3C_CHECKOUT");
	if (try v) return v;
	return "/home/km/Documents/c3c";
}

<* Every *.c3 and *.c3i file under `dir`, recursively. Result in temp memory. *>
fn String[] find_c3_files(String dir) @local
{
	List{String} out;
	out.tinit();
	walk_c3_files(&out, dir);
	return out.to_tarray();
}

fn void walk_c3_files(List{String}* out, String dir) @local
{
	Path? p = path::tnew(dir);
	if (catch p) return;
	PathList? entries = path::ls(tmem, p);
	if (catch entries) return;
	foreach (e : entries)
	{
		String name = e.basename();
		if (name == "." || name == "..") continue;
		String full = string::tformat("%s/%s", dir, name);
		if (file::is_dir(full))
		{
			walk_c3_files(out, full);
			continue;
		}
		if (name.ends_with(".c3") || name.ends_with(".c3i")) out.push(full);
	}
}

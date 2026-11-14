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
import c3::parser::conformance;
import c3::lexer;
import std::collections::list;
import std::io;
import std::io::path;

struct Want
{
	sz     ln;
	String text;
	bool   matched;
}

<*
 Run one check against one testdata file and assert an exact match.
 @param check_name : "the check to enable; every other check stays off"
 @param path : "path to the testdata file, relative to the project root"
*>
fn void verify(String check_name, String path)
{
	char[]? bytes = file::load(tmem, path);
	if (catch bytes) unreachable("cannot read testdata '%s'", path);
	String src = (String)bytes;

	sz idx = c3vet::find_check(check_name);
	assert(idx >= 0, "no such check '%s'", check_name);
	Check only = c3vet::ALL_CHECKS[idx];

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
*>
fn sz measure_fp(String check_name)
{
	String base = conformance::checkout_dir();
	if (!path::exists(path::tnew(base) ?? (Path){})) return 0;

	String lib_dir = string::tformat("%s/lib", base);
	String unit_dir = string::tformat("%s/test/unit", base);
	String[] files = conformance::find_c3_files(lib_dir);
	String[] unit_files = conformance::find_c3_files(unit_dir);

	sz idx = c3vet::find_check(check_name);
	assert(idx >= 0, "no such check '%s'", check_name);
	Check[1] one = { c3vet::ALL_CHECKS[idx] };

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

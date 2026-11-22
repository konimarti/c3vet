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

 Suppression comments match anywhere inside the construct; `want` does not.

 `want` text is matched as a substring, not a regular expression, so no
 dependency is needed and messages stay greppable.
*>
module c3vet::testdata;

import c3::lexer;
import c3::parser;
import c3vet;
import std::collections::list;
import std::io;

struct Want
{
	sz     ln;
	String text;
	bool   matched;
}

<*
 Run one check against one testdata file and assert an exact match.

 Looks `check_name` up in `c3vet::ALL_CHECKS`, so the check must be
 registered there. To test a check that is not registered, call
 `verify_check` below with its own `Check` literal instead -- same 1:1
 `// want` match, no registry dependency.
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
		assert(ok, "%s:%d: unexpected finding '%s' (no matching want)", path,
			d.ln, d.msg);
	}
	// Every want must be produced.
	foreach (w : wants)
	{
		assert(w.matched, "%s:%d: wanted a finding containing '%s', got none",
			path, w.ln, w.text);
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

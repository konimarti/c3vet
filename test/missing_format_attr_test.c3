module c3vet::missing_format_attr_test;

import c3vet;
import c3::parser;
import c3::lexer;
import std::collections::list;
import std::io;

struct Want
{
	sz     ln;
	String text;
	bool   matched;
}

fn void test_missing_format_attr() @test
{
	DeclTable table;
	String std = c3vet::find_stdlib_root(tmem);
	List{String} roots;
	roots.tinit();
	roots.push("testdata/missing-format-attr.c3");
	if (std.len) roots.push(std);
	c3vet::build_table(&table, roots.to_tarray(), tmem);

	char[]? bytes = file::load(tmem, "testdata/missing-format-attr.c3");
	if (catch bytes) unreachable("cannot read testdata/missing-format-attr.c3");
	String src = (String)bytes;

	Unit u;
	u.path = "testdata/missing-format-attr.c3";
	u.src = src;
	u.parsed = parser::parse(tmem, src);
	u.suppress.init(tmem);
	u.suppress.collect(u.toks());

	List{Want} wants;
	wants.tinit();
	foreach (t : u.toks().all)
	{
		if (t.type != LINE_COMMENT && t.type != BLOCK_COMMENT) continue;
		sz at = t.text.index_of("want \"") ?? -1;
		if (at < 0) continue;
		String rest = t.text[(usz)at + 6..];
		sz end = rest.index_of_char('"') ?? -1;
		if (end < 0) continue;
		wants.push({ .ln = t.ln, .text = rest[..(usz)end - 1] });
	}

	DiagnosticList diags;
	diags.init(tmem);
	Config cfg;
	cfg.init(tmem);
	Ctx ctx = { .config = &cfg, .out = &diags, .table = &table };
	ctx.reported.init(tmem);

	Check[1] one = { c3vet::MISSING_FORMAT_ATTR };
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
		assert(ok, "unexpected finding '%s' on line %d", d.msg, d.ln);
	}

	// Every want must be produced.
	foreach (w : wants)
	{
		assert(w.matched, "line %d: wanted finding containing '%s', got none", w.ln, w.text);
	}

	// Measure over conformance corpus
	sz corpus_findings = measure_corpus_with_table(&table);
	assert(corpus_findings == 0, "expected 0 findings over the conformance corpus");
}

fn sz measure_corpus_with_table(DeclTable* table) @local
{
	String base = conformance::checkout_dir();
	if (!path::exists(path::tnew(base) ?? (Path){})) return 0;

	String lib_dir = string::tformat("%s/lib", base);
	String unit_dir = string::tformat("%s/test/unit", base);
	String[] files = conformance::find_c3_files(lib_dir);
	String[] unit_files = conformance::find_c3_files(unit_dir);

	Check[1] one = { c3vet::MISSING_FORMAT_ATTR };
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
				Ctx ctx = { .config = &cfg, .out = &diags, .table = table };
				ctx.reported.init(tmem);

				c3vet::run_checks(&ctx, &u, one[..]);
				if (diags.len() > 0)
				{
					foreach (d : diags)
					{
						io::printfn("CORPUS FINDING: %s:%d: %s", f, d.ln, d.msg);
					}
				}
				total += diags.len();
			};
		}
	}
	return total;
}

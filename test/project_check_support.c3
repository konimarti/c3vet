module c3vet::project_check_support;

import c3vet;
import c3::parser;
import std::io::file;

fn void verify_project_check(Check check, String path_, sz expected)
{
	char[]? bytes = file::load(tmem, path_);
	if (catch bytes) unreachable("cannot load '%s'", path_);
	DeclTable table;
	String[2] roots = { "testdata", "test" };
	c3vet::build_table(&table, roots[..], tmem);

	Unit u;
	u.path = path_;
	u.src = (String)bytes;
	u.parsed = parser::parse(tmem, u.src);
	u.suppress.init(tmem);
	u.suppress.collect(u.toks());
	DiagnosticList diags;
	diags.init(tmem);
	Config cfg;
	cfg.init(tmem);
	Ctx ctx = { .table = &table, .config = &cfg, .out = &diags };
	ctx.reported.init(tmem);
	Check[1] one = { check };
	c3vet::run_checks(&ctx, &u, one[..]);
	// unused-private-decl caches project files across calls for the rest of
	// the Ctx it was built for; each test builds its own short-lived one.
	defer c3vet::free_project_cache();
	assert(diags.len() == expected, "%s: expected %d finding(s), got %d (%s; %s)", path_, expected, diags.len(), diags.len() > 0 ? diags[0].msg : "", diags.len() > 1 ? diags[1].msg : "");

	uint want_count = 0;
	foreach (token : u.toks().all)
	{
		if (token.type != LINE_COMMENT && token.type != BLOCK_COMMENT) continue;
		if (token.text.contains("want \"")) want_count++;
	}
	assert(want_count == expected, "%s: // want annotations do not match expected findings", path_);
}

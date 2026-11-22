module c3vet::engine_tier_test @test;

import c3::parser;
import c3vet;
import std::collections::list;

fn void engine_builds_scopes_only_for_local_tier()
{
	CheckFn noop = fn void(Ctx* ctx, Unit* u) {};
	Check syntax_check = {
		.name = "zz-syntax", .tier = Tier.SYNTAX,
		.run = noop
	};
	Check local_check = { .name = "zz-local", .tier = Tier.LOCAL, .run = noop };

	String src = "fn void f(int n) {}";
	Unit u;
	u.path = "probe.c3";
	u.src = src;
	u.parsed = parser::parse(tmem, src);
	u.suppress.init(tmem);
	u.suppress.collect(u.toks());
	DiagnosticList diags;
	diags.init(tmem);
	Config cfg;
	cfg.init(tmem);
	Ctx ctx = { .config = &cfg, .out = &diags };
	ctx.reported.init(tmem);

	Check[1] syntax_only = { syntax_check };
	c3vet::run_checks(&ctx, &u, syntax_only[..]);
	assert(!u.scopes, "a SYNTAX-only run must not build Scopes");
	assert(!u.flow, "a SYNTAX-only run must not build Flow");

	Check[1] local_only = { local_check };
	c3vet::run_checks(&ctx, &u, local_only[..]);
	assert(u.scopes != null, "a LOCAL-tier run must build Scopes");
	assert(u.flow != null, "a LOCAL-tier run must build Flow");

	NodeId fn_decl = parser::NONE;
	foreach (i, n : u.ast().nodes) if (n.kind == NodeKind.FN_DECL)
	{
		fn_decl = (NodeId)i;
	}
	assert(u.ast().node(u.scopes.declared_type(fn_decl, "n")).kind
		== NodeKind.TYPE_BASE,
		"the built Scopes must actually reflect this unit's function");
}

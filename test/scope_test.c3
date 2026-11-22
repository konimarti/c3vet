module c3vet::scope_test @test;

import c3::parser;
import c3vet;
import std::collections::list;

fn void scope_declared_types()
{
	String src = `fn void f(int n, float* out)
{
	int a;
	var b = 1;
}
`;
	ParseResult r = parser::parse(tmem, src);
	c3vet::Scopes s = c3vet::build_scopes(&r.ast, &r.toks, tmem);

	NodeId fn_decl = parser::NONE;
	foreach (i, n : r.ast.nodes) if (n.kind == NodeKind.FN_DECL)
	{
		fn_decl = (NodeId)i;
	}
	assert(fn_decl != parser::NONE, "no FN_DECL found");

	assert(r.ast.node(s.declared_type(fn_decl, "n")).kind == NodeKind.TYPE_BASE,
		"param 'n' should resolve to an explicit type");
	assert(r.ast.node(s.declared_type(fn_decl, "out")).kind
		== NodeKind.TYPE_PTR,
		"param 'out' should resolve to an explicit pointer type");
	assert(r.ast.node(s.declared_type(fn_decl, "a")).kind == NodeKind.TYPE_BASE,
		"local 'a' has an explicit type");
	assert(s.declared_type(fn_decl, "b") == parser::NONE,
		"'var b = 1' has no explicit type -- must resolve to NONE, not a guess");
	assert(s.declared_type(fn_decl, "nonexistent") == parser::NONE,
		"an unknown name must resolve to NONE");
}

fn void scope_shadowed_name_is_ambiguous()
{
	String src = `fn void f()
{
	int x;
	{
		float x;
	}
}
`;
	ParseResult r = parser::parse(tmem, src);
	c3vet::Scopes s = c3vet::build_scopes(&r.ast, &r.toks, tmem);
	NodeId fn_decl = parser::NONE;
	foreach (i, n : r.ast.nodes) if (n.kind == NodeKind.FN_DECL)
	{
		fn_decl = (NodeId)i;
	}

	assert(s.declared_type(fn_decl, "x") == parser::NONE,
		"two declarations named 'x' in one function must resolve to NONE rather than guess which one a use site means");
}

fn void scope_two_functions_do_not_collide()
{
	String src = `fn void f(int x) {}
fn void g(float x) {}
`;
	ParseResult r = parser::parse(tmem, src);
	c3vet::Scopes s = c3vet::build_scopes(&r.ast, &r.toks, tmem);

	NodeId[] fns;
	List{NodeId} list;
	list.tinit();
	foreach (i, n : r.ast.nodes) if (n.kind == NodeKind.FN_DECL)
	{
		list.push((NodeId)i);
	}
	fns = list.to_tarray();
	assert(fns.len == 2, "expected exactly two FN_DECLs");

	assert(r.ast.node(s.declared_type(fns[0], "x")).kind == NodeKind.TYPE_BASE);
	assert(r.ast.node(s.declared_type(fns[1], "x")).kind == NodeKind.TYPE_BASE);
	// Each function's own 'x' must keep its own type -- not merged across functions.
	String t0 = r.toks.text_at(r.ast.node(s.declared_type(fns[0], "x")).tok);
	String t1 = r.toks.text_at(r.ast.node(s.declared_type(fns[1], "x")).tok);
	assert(t0 == "int" && t1 == "float", "got t0=%s t1=%s", t0, t1);
}

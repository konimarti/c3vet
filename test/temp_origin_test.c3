module c3vet::temp_origin_test @test;

import c3vet;
import c3::parser;

fn void temp_origin_direct_mem_calls()
{
	String src = `fn void f()
{
	int* a = mem::talloc(int);
	int* b = talloc(int);
	int* c = mem::talloc_array(int, 4);
}
`;
	ParseResult r = parser::parse(tmem, src);
	foreach (i, n : r.ast.nodes)
	{
		if (n.kind != NodeKind.VAR_DECL) continue;
		assert(c3vet::is_temp_origin_init(&r.ast, &r.toks, n.rhs),
			"'%s' should be recognized as temp-origin", r.toks.text_at(n.tok));
	}
}

fn void temp_origin_tmem_argument()
{
	String src = `fn void f()
{
	int* a = (int*)alloc::new(tmem, int);
}
`;
	ParseResult r = parser::parse(tmem, src);
	NodeId decl = parser::NONE;
	foreach (i, n : r.ast.nodes) if (n.kind == NodeKind.VAR_DECL) decl = (NodeId)i;
	assert(c3vet::is_temp_origin_init(&r.ast, &r.toks, r.ast.node(decl).rhs),
		"a call passing 'tmem' as an argument, even under a cast, is temp-origin");
}

fn void temp_origin_excludes_unrelated_calls()
{
	String src = `fn void f()
{
	int* a = mem::new(int);
	int b = plain(1, 2);
}
fn int plain(int x, int y) => x + y;
`;
	ParseResult r = parser::parse(tmem, src);
	foreach (i, n : r.ast.nodes)
	{
		if (n.kind != NodeKind.VAR_DECL) continue;
		assert(!c3vet::is_temp_origin_init(&r.ast, &r.toks, n.rhs),
			"'%s' must NOT be recognized as temp-origin", r.toks.text_at(n.tok));
	}
}

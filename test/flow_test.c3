module c3vet::flow_test @test;

import c3vet;
import c3::parser;

fn void flow_is_read_true_and_false()
{
	String src = `fn void f(int err)
{
	if (err) {}
}
`;
	ParseResult r = parser::parse(tmem, src);
	NodeId fn_decl = parser::NONE;
	foreach (i, n : r.ast.nodes) if (n.kind == NodeKind.FN_DECL) fn_decl = (NodeId)i;
	NodeId body = r.ast.node(fn_decl).rhs;

	assert(c3vet::is_read(&r.ast, &r.toks, body, "err"), "'err' is referenced in the if-condition");
	assert(!c3vet::is_read(&r.ast, &r.toks, body, "nope"), "'nope' does not appear anywhere in the body");
}

fn void flow_is_read_counts_a_write_as_used()
{
	// Documented, deliberate conservatism: is_read does not distinguish a
	// write from a read, so overwriting a binding still counts as "used".
	String src = `fn void f()
{
	int err;
	err = 1;
}
`;
	ParseResult r = parser::parse(tmem, src);
	NodeId fn_decl = parser::NONE;
	foreach (i, n : r.ast.nodes) if (n.kind == NodeKind.FN_DECL) fn_decl = (NodeId)i;
	NodeId body = r.ast.node(fn_decl).rhs;

	assert(c3vet::is_read(&r.ast, &r.toks, body, "err"));
}

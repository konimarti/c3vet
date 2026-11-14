module c3::parser::parse_test @test;

import c3::parser;
import c3::parser::invariants;
import std::io;

const String SRC = `
module demo;
import std::io;

fn void main()
{
	foo;
	{
		bar;
	}
}
`;

fn void parses_without_error()
{
	ParseResult r = parser::parse(mem, SRC);
	defer r.free();
	assert(!r.lex_failed, "clean source lexes");
	assert(r.ast.root != parser::NONE, "a root is produced");
	assert(r.ast.len() > 1, "nodes beyond the sentinel exist");
}

fn void spans_and_edges_hold()
{
	ParseResult r = parser::parse(mem, SRC);
	defer r.free();
	Report rep = invariants::check(&r);
	assert(rep.edges_valid, "invariant 2, edge validity: %s", rep.detail);
	assert(rep.spans_nest, "invariant 1, span nesting: %s", rep.detail);
	// Invariant 3 (token coverage) is the Phase 1 gate and must NOT pass yet:
	// the Phase 0 stubs skip over function signatures without making nodes.
	// When lanes 1A-1C land, this assertion flips to rep.tokens_covered.
	assert(!rep.tokens_covered, "coverage must still fail with Phase 0 stubs");
}

fn void malformed_input_still_returns_a_tree()
{
	ParseResult r = parser::parse(mem, "module demo; fn void f() { @@@ ; }");
	defer r.free();
	assert(r.has_errors(), "garbage is reported");
	assert(r.ast.root != parser::NONE, "but a tree is still returned");
	Report rep = invariants::check(&r);
	assert(rep.edges_valid, "edges stay valid on malformed input: %s", rep.detail);
	assert(rep.spans_nest, "spans stay valid on malformed input: %s", rep.detail);
}

fn void unterminated_input_does_not_hang()
{
	ParseResult r = parser::parse(mem, "module demo; fn void f() { ");
	defer r.free();
	assert(r.ast.root != parser::NONE, "truncated input still yields a tree");
}

<*
 Binding-use queries. There is no control-flow graph: `Flow` carries no
 state, and `is_read` answers "is this binding ever read in this subtree"
 directly against the `Ast`.
*>
module c3vet;

import c3::parser;

struct Flow
{
	<* Unused; exists only so this isn't a zero-sized struct. *>
	bool built;
}

fn Flow build_flow(Ast* ast, TokenList* toks, Allocator a) => (Flow){
	.built =
			true
};

<*
 True when some `IDENT` spelling `name` is reachable anywhere in `id`'s
 subtree.

 Does not distinguish a read from a write (`err = other;` counts as "used"),
 which is the conservative direction for an unused-binding check: it would
 rather miss a genuine non-use than flag a binding that is, in fact, touched.
*>
fn bool is_read(Ast* ast, TokenList* toks, NodeId id, String name)
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.IDENT && toks.text_at(n.tok) == name) return true;
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) if (is_read(ast, toks, c, name))
		{
			return true;
		}
		return false;
	}
	return is_read(ast, toks, n.lhs, name) || is_read(ast, toks, n.rhs, name);
}

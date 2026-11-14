<*
 T2: statement reachability -- deliberately narrower than that name suggests.

 Walking the actual Phase 3 catalog, no check needs a control-flow graph.
 `unused-catch-binding`/`unused-try-binding` only need "is this binding ever
 read inside the branch where it's in scope" -- a plain subtree scan, not
 dataflow. So `Flow` itself carries no state; the real answer comes from
 `is_read`, a free function against the `Ast` directly. The field exists so
 `Unit.flow`'s frozen shape has a type, and so a future check that genuinely
 needs more can grow into it without another interface change.
*>
module c3vet;

import c3::parser;

struct Flow
{
	<* Unused; exists only so this isn't a zero-sized struct. *>
	bool built;
}

fn Flow build_flow(Ast* ast, TokenList* toks, Allocator a) => (Flow){ .built = true };

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
		foreach (c : ast.children(id)) if (is_read(ast, toks, c, name)) return true;
		return false;
	}
	return is_read(ast, toks, n.lhs, name) || is_read(ast, toks, n.rhs, name);
}

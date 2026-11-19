<*
 Walks one function body and calls a callback on every node in it.

 Nested functions, macros and lambdas have their own scope, so the walk does
 not descend into them. Used by `redundant-mem-free`, `mem-copy-slice-to-array`
 and `catch-default-operator`.
*>
module c3vet;

import c3::parser;

alias BodyNodeFn = fn void(Ast* ast, NodeId fn_decl, NodeId id, any ctx);

<* Calls `cb` on `id` and on every node below it, except inside nested scopes. *>
fn void scan_fn_body(Ast* ast, NodeId fn_decl, NodeId id, BodyNodeFn cb,
	any ctx)
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL
		|| n.kind == NodeKind.LAMBDA)
	{
		return;
	}

	cb(ast, fn_decl, id, ctx);

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) scan_fn_body(ast, fn_decl, c, cb, ctx);
	}
	else
	{
		scan_fn_body(ast, fn_decl, n.lhs, cb, ctx);
		scan_fn_body(ast, fn_decl, n.rhs, cb, ctx);
	}
}

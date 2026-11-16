<*
 Whether an expression's value is temp-allocator-derived.

 Used by `temp-escapes-fn`, `temp-escapes-pool`, `temp-escapes-struct`,
 `temp-wrong-free` and `temp-to-global`. Purely syntactic: no type
 resolution, no alias analysis. A call counts as temp-origin when either:

   - its callee is one of `mem`'s seven temp-allocation macros (`talloc`,
     `talloc_array`, `talloc_with_padding`, `tcalloc`, `tmalloc`, `tnew`,
     `trealloc`), bare or `mem::`-qualified -- these never take an
     allocator argument, so the only signal is the name; or
   - any of its arguments is literally the identifier `tmem` (bare or
     qualified), the well-known alias for the current temp allocator
     (`x.init(tmem)`, `alloc::new(tmem, Type)`, `path::ls(tmem, ...)`).

 Not detected: a module's own bespoke `t`-prefixed
 convenience wrapper that hardcodes the temp allocator internally without
 taking one as an argument (`path::tnew`, `string::tformat`) is not
 recognized, since it is not in the `mem` name list and its call site does
 not pass `tmem`.
*>
module c3vet;

import c3::parser;

<* The `mem` names that always allocate from the current temp allocator, regardless of arguments. *>
fn bool is_mem_temp_alloc_name(String name) @local
{
	switch (name)
	{
		case "talloc":
		case "talloc_array":
		case "talloc_with_padding":
		case "tcalloc":
		case "tmalloc":
		case "tnew":
		case "trealloc":
			return true;
		default:
			return false;
	}
}

<* True when `id` (an `IDENT` or `PATH`) spells exactly `tmem` in its final segment. *>
fn bool is_tmem_name(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE) return false;
	NodeKind k = ast.kind(id);
	if (k != NodeKind.IDENT && k != NodeKind.PATH) return false;
	return toks.text_at(ast.node(id).last_tok) == "tmem";
}

<*
 True when `call_id` (a `CALL` node) allocates from the current temp
 allocator (see the module doc comment).
*>
fn bool is_temp_origin_call(Ast* ast, TokenList* toks, NodeId call_id)
{
	if (call_id == parser::NONE || ast.kind(call_id) != NodeKind.CALL) return false;
	NodeId[] kids = ast.children(call_id);
	if (!kids.len) return false;
	NodeId callee = kids[0];
	NodeKind callee_kind = ast.kind(callee);
	if (callee_kind == NodeKind.IDENT || callee_kind == NodeKind.PATH)
	{
		if (is_mem_temp_alloc_name(toks.text_at(ast.node(callee).last_tok))) return true;
	}
	foreach (arg : kids[1..]) if (is_tmem_name(ast, toks, arg)) return true;
	return false;
}

<*
 True when `init` (a `VAR_DECL`'s `rhs`, or any expression) is temp-origin:
 either directly a qualifying `CALL`, or a `CALL` wrapped in at most one
 `CAST` (`(int*)mem::talloc(int)`). Anything deeper is not tracked.
*>
fn bool is_temp_origin_init(Ast* ast, TokenList* toks, NodeId init)
{
	if (init == parser::NONE) return false;
	Node* n = ast.node(init);
	if (n.kind == NodeKind.CAST) return is_temp_origin_call(ast, toks, n.rhs);
	return is_temp_origin_call(ast, toks, init);
}

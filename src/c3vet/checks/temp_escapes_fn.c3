<*
 `temp-escapes-fn`: temp memory allocated inside a `@pool()` body and returned
 from inside it. Leaving the body frees the allocation, so the caller gets a
 dangling pointer or slice.

 Returning temp memory allocated outside any `@pool` of this function is not
 reported: it lives until the caller's pool ends.
*>
module c3vet;

import c3::lexer;
import c3::parser;
import std::collections::list;
import std::core::mem::alloc;
import std::io;

const Check TEMP_ESCAPES_FN = {
	.name          = "temp-escapes-fn",
	.doc           = "temp-allocated memory returned out of "
		"the @pool that frees it",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_temp_escapes_fn,
	.make_state    = &make_temp_escapes_fn_state,
};

fn any make_temp_escapes_fn_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, TempEscapesFnWalker, { .ctx = ctx, .unit = u });

struct TempEscapesFnWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_temp_escapes_fn(Ast* ast, NodeId id, any ctx) @local
{
	TempEscapesFnWalker* w = (TempEscapesFnWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL) return true;

	LocalDecl[] locals = w.unit.scopes.locals_in(id);
	TokenList* toks = w.unit.toks();
	List{NodeId} pools;
	pools.tinit();
	outermost_pool_blocks(ast, toks, n.rhs, &pools);
	foreach (block_id : pools)
	{
		List{String} pool_temp_locals;
		pool_temp_locals.tinit();
		collect_temp_locals_in(ast, toks, ast.node(block_id), locals,
			&pool_temp_locals);
		check_returns_in_body(w, block_id, &pool_temp_locals);
	}
	return true;
}

fn void check_returns_in_body(TempEscapesFnWalker* w, NodeId id,
	List{String}* temp_locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	Node* n = ast.node(id);

	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL
		|| n.kind == NodeKind.LAMBDA)
	{
		return;
	}

	if (n.kind == NodeKind.RETURN)
	{
		NodeId val = n.lhs;
		if (val != parser::NONE
			&& (is_temp_origin_init(ast, w.unit.toks(), val)
			|| is_temp_val(ast, w.unit.toks(), val, temp_locals)))
		{
			w.ctx.report(w.unit, id, "temp-escapes-fn",
				"temp-allocated memory returned out of the @pool that frees it -- allocate it before the @pool, or copy it with a non-temp allocator");
		}
		return;
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) check_returns_in_body(w, c, temp_locals);
	}
	else
	{
		check_returns_in_body(w, n.lhs, temp_locals);
		check_returns_in_body(w, n.rhs, temp_locals);
	}
}

<* True when `val` resolves to one of `temp_locals`. *>
fn bool is_temp_val(Ast* ast, TokenList* toks,
	NodeId val, List{String}* temp_locals) @local
{
	if (val == parser::NONE) return false;

	NodeId cur = val;
	while (cur != parser::NONE)
	{
		Node* cn = ast.node(cur);
		if (cn.kind == NodeKind.CAST)
		{
			cur = cn.rhs;
		}
		else if (cn.kind == NodeKind.SLICE)
		{
			NodeId[] kids = ast.children(cur);
			cur = kids.len ? kids[0] : parser::NONE;
		}
		else if (cn.kind == NodeKind.UNARY)
		{
			TokenType tt = toks.type_at(cn.tok);
			if (tt == AMP || tt == STAR)
			{
				cur = cn.lhs;
			}
			else
			{
				break;
			}
		}
		else if (cn.kind == NodeKind.CALL)
		{
			// A view of a temp local, e.g. `p.view()`: follow the receiver.
			// Only without arguments, so a copy-out like `s.copy(mem)` passes.
			NodeId[] kids = ast.children(cur);
			NodeId callee = kids.len ? kids[0] : parser::NONE;
			if (kids.len == 1 && callee != parser::NONE
				&& ast.kind(callee) == NodeKind.MEMBER_ACCESS)
			{
				cur = ast.node(callee).lhs;
			}
			else
			{
				break;
			}
		}
		else
		{
			break;
		}
	}

	if (cur != parser::NONE && ast.kind(cur) == NodeKind.IDENT)
	{
		String name = toks.text_at(ast.node(cur).tok);
		foreach (tname : *temp_locals)
		{
			if (tname == name) return true;
		}
	}
	return false;
}

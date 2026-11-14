<*
 `temp-escapes-pool`: a talloc inside `@pool() { ... }` assigned to a variable declared outside the pool body.

 docs/CHECKS.md Family A. When a `@pool` scope exits, the temporary allocator
 frees all allocations made within it. Assigning any such allocation to a variable
 with a longer lifetime causes a use-after-free once the pool block exits.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::io;

const Check TEMP_ESCAPES_POOL = {
	.name          = "temp-escapes-pool",
	.doc           = "temp-allocated memory inside @pool assigned to variable declared outside pool",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_temp_escapes_pool,
};

fn void run_temp_escapes_pool(Ctx* ctx, Unit* u)
{
	TempEscapesPoolWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_temp_escapes_pool, &w);
}

struct TempEscapesPoolWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool span_contains(uint b_first, uint b_last, uint a_first, uint a_last) @inline
{
	return b_first <= a_first && a_last <= b_last;
}

fn bool is_pool_callee(Ast* ast, TokenList* toks, NodeId callee) @local
{
	if (callee == parser::NONE) return false;
	NodeKind k = ast.kind(callee);
	if (k != NodeKind.IDENT && k != NodeKind.PATH) return false;
	return toks.text_at(ast.node(callee).last_tok) == "@pool";
}

fn NodeId find_pool_block(Ast* ast, NodeId call_id) @local
{
	foreach (c : ast.children(call_id))
	{
		if (ast.kind(c) == NodeKind.BLOCK) return c;
	}
	return parser::NONE;
}

fn bool visit_temp_escapes_pool(Ast* ast, NodeId id, any ctx) @local
{
	TempEscapesPoolWalker* w = (TempEscapesPoolWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL && n.kind != NodeKind.MACRO_DECL) return true;

	LocalDecl[] locals = w.unit.scopes.locals_in(id);
	check_pools_in_body(w, n.rhs, locals);
	return true;
}

fn void check_pools_in_body(TempEscapesPoolWalker* w, NodeId id, LocalDecl[] locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	Node* n = ast.node(id);

	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;

	if (n.kind == NodeKind.CALL)
	{
		NodeId[] kids = ast.children(id);
		if (kids.len && is_pool_callee(ast, toks, kids[0]))
		{
			NodeId block_id = find_pool_block(ast, id);
			if (block_id != parser::NONE)
			{
				inspect_pool_block(w, block_id, locals);
			}
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) check_pools_in_body(w, c, locals);
	}
	else
	{
		check_pools_in_body(w, n.lhs, locals);
		check_pools_in_body(w, n.rhs, locals);
	}
}

fn void inspect_pool_block(TempEscapesPoolWalker* w, NodeId block_id, LocalDecl[] locals) @local
{
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	Node* b = ast.node(block_id);

	// Collect temp-origin locals declared inside this pool block.
	List{String} pool_temp_locals;
	pool_temp_locals.tinit();
	foreach (d : locals)
	{
		if (d.decl == parser::NONE || ast.kind(d.decl) != NodeKind.VAR_DECL) continue;
		Node* vn = ast.node(d.decl);
		if (span_contains(b.first_tok, b.last_tok, vn.first_tok, vn.last_tok))
		{
			if (is_temp_origin_init(ast, toks, vn.rhs))
			{
				pool_temp_locals.push(d.name);
			}
		}
	}

	// Walk statements in the pool block looking for assignments to outer variables.
	check_pool_assignments(w, block_id, b.first_tok, b.last_tok, locals, &pool_temp_locals);
}

fn void check_pool_assignments(TempEscapesPoolWalker* w, NodeId id, uint b_first, uint b_last,
                              LocalDecl[] locals, List{String}* pool_temp_locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	Node* n = ast.node(id);

	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;
	if (n.kind == NodeKind.INIT_LIST) return;

	if (n.kind == NodeKind.ASSIGN)
	{
		NodeId target = n.lhs;
		NodeId val = n.rhs;
		if (val_is_temp(ast, toks, val, pool_temp_locals))
		{
			// Check if target was declared outside this pool block.
			if (target_is_outer(ast, toks, target, b_first, b_last, locals))
			{
				w.ctx.report(w.unit, id, "temp-escapes-pool",
					"temp-allocated memory inside @pool assigned to variable declared outside pool");
			}
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) check_pool_assignments(w, c, b_first, b_last, locals, pool_temp_locals);
	}
	else
	{
		check_pool_assignments(w, n.lhs, b_first, b_last, locals, pool_temp_locals);
		check_pool_assignments(w, n.rhs, b_first, b_last, locals, pool_temp_locals);
	}
}

fn bool val_is_temp(Ast* ast, TokenList* toks, NodeId val, List{String}* pool_temp_locals) @local
{
	if (val == parser::NONE) return false;
	if (is_temp_origin_init(ast, toks, val)) return true;

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
			if (tt == AMP || tt == STAR) { cur = cn.lhs; }
			else { break; }
		}
		else { break; }
		if (is_temp_origin_init(ast, toks, cur)) return true;
	}

	if (cur != parser::NONE && ast.kind(cur) == NodeKind.IDENT)
	{
		String name = toks.text_at(ast.node(cur).tok);
		foreach (pname : *pool_temp_locals)
		{
			if (pname == name) return true;
		}
	}
	return false;
}

fn bool target_is_outer(Ast* ast, TokenList* toks, NodeId target, uint b_first, uint b_last, LocalDecl[] locals) @local
{
	NodeId cur = target;
	while (cur != parser::NONE)
	{
		Node* cn = ast.node(cur);
		if (cn.kind == NodeKind.MEMBER_ACCESS || cn.kind == NodeKind.SUBSCRIPT)
		{
			cur = cn.lhs;
		}
		else if (cn.kind == NodeKind.UNARY)
		{
			TokenType tt = toks.type_at(cn.tok);
			if (tt == STAR) { cur = cn.lhs; }
			else { break; }
		}
		else { break; }
	}

	if (cur == parser::NONE) return false;
	if (ast.kind(cur) != NodeKind.IDENT) return true; // e.g. PATH is outer/global

	String name = toks.text_at(ast.node(cur).tok);
	foreach (d : locals)
	{
		if (d.name == name)
		{
			if (d.decl == parser::NONE) return true;
			Node* dn = ast.node(d.decl);
			return !span_contains(b_first, b_last, dn.first_tok, dn.last_tok);
		}
	}
	// Not found in locals: it's a global/module-level variable, thus outside pool.
	return true;
}

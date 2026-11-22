<*
 `catch-default-operator`: catching a fault only to assign a default.

 `if (catch v) { x = {}; } else { x = v; }` should be `x = v ?? {};`, the
 optional else operator. Only a plain identifier `v` is matched, and the
 `catch err = v` form is also accepted; the binding must not be read. Off by
 default: this encodes a style policy, not a bug. Rules come from Christoffer
 Lerno's review of an LLM-written benchmark suite (kostya/LangArena#33).
*>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check CATCH_DEFAULT_OPERATOR = {
	.name          = "catch-default-operator",
	.doc           =
		"catch and assign a default, which the optional else operator does "
		"in one line: x = v ?? {};",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_catch_default_operator,
	.make_state    = &make_catch_default_operator_state,
};

struct CatchDefaultOperatorWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_catch_default_operator_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, CatchDefaultOperatorWalker, { .ctx = ctx, .unit = u });

fn bool visit_catch_default_operator(Ast* ast, NodeId id, any ctx) @local
{
	CatchDefaultOperatorWalker* w = (CatchDefaultOperatorWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL)
	{
		scan_fn_body(ast, id, n.rhs, &check_catch_default_if, w);
	}
	return true;
}

fn void check_catch_default_if(Ast* ast, NodeId fn_decl, NodeId id, any ctx)
	@local
{
	if (ast.kind(id) != NodeKind.IF) return;
	CatchDefaultOperatorWalker* w = (CatchDefaultOperatorWalker*)ctx;
	TokenList* toks = w.unit.toks();
	NodeId[] kids = ast.children(id);
	if (kids.len != 3 || kids[0] == parser::NONE || kids[2] == parser::NONE)
	{
		return;
	}
	if (ast.kind(kids[0]) != NodeKind.CATCH_EXPR) return;

	NodeId value = ast.node(kids[0]).lhs;
	if (value != parser::NONE && ast.kind(value) == NodeKind.VAR_DECL)
	{
		value = ast.node(value).rhs;
	}
	if (value == parser::NONE || ast.kind(value) != NodeKind.IDENT) return;
	String v = toks.text_at(ast.node(value).tok);

	NodeId then_assign = only_assign(ast, kids[1]);
	NodeId else_assign = only_assign(ast, kids[2]);
	if (then_assign == parser::NONE || else_assign == parser::NONE) return;

	NodeId then_val = ast.node(then_assign).rhs;
	NodeId else_val = ast.node(else_assign).rhs;
	if (ast.kind(then_val) != NodeKind.INIT_LIST
		|| ast.children(then_val).len != 0)
	{
		return;
	}
	if (ast.kind(else_val) != NodeKind.IDENT
		|| toks.text_at(ast.node(else_val).tok) != v)
	{
		return;
	}
	if (!same_expr(ast, toks, ast.node(then_assign).lhs,
		ast.node(else_assign).lhs))
	{
		return;
	}

	w.ctx.report(w.unit, id, "catch-default-operator",
		"catch and assign a default -- use the optional else operator: x = v ?? {};");
}

<* The single `x = value;` assignment in a `{ ... }` block, or NONE. *>
fn NodeId only_assign(Ast* ast, NodeId block) @local
{
	if (block == parser::NONE || ast.kind(block) != NodeKind.BLOCK)
	{
		return parser::NONE;
	}
	NodeId[] stmts = ast.children(block);
	if (stmts.len != 1 || ast.kind(stmts[0]) != NodeKind.EXPR_STMT)
	{
		return parser::NONE;
	}
	NodeId expr = ast.node(stmts[0]).lhs;
	if (expr == parser::NONE || ast.kind(expr) != NodeKind.ASSIGN)
	{
		return parser::NONE;
	}
	return expr;
}

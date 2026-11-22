<* Flag conditions determined entirely by boolean or integer literals. *>
module c3vet;

import c3::lexer;
import c3::parser;
import std::core::mem::alloc;

const Check CONST_COND = {
	.name          = "const-cond",
	.doc           = "a control-flow condition is determined by literals alone",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_const_cond,
	.make_state    = &make_const_cond_state,
};

struct ConstCondWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_const_cond_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, ConstCondWalker, { .ctx = ctx, .unit = u });

fn bool visit_const_cond(Ast* ast, NodeId id, any context) @local
{
	ConstCondWalker* w = (ConstCondWalker*)context;
	NodeId condition = parser::NONE;
	NodeKind kind = ast.kind(id);
	switch (kind)
	{
		case NodeKind.IF:
		{
			NodeId[] kids = ast.children(id);
			if (kids.len == 3) condition = kids[0];
		}
		case NodeKind.WHILE: condition = ast.node(id).lhs;
		case NodeKind.DO: condition = ast.node(id).rhs;
		case NodeKind.FOR:
		{
			NodeId[] kids = ast.children(id);
			if (kids.len == 4) condition = kids[1];
		}
		default: return true;
	}
	if (condition == parser::NONE
		|| !is_literal_condition(ast, w.unit.toks(), condition))
	{
		return true;
	}
	// `while (true)`/`do { ... } while (true)` is the standard loop-forever,
	// break-explicitly-inside idiom, not a forgotten toggle -- flagging it
	// would fire on some of the most ordinary code in any codebase.
	if ((kind == NodeKind.WHILE || kind == NodeKind.DO) && is_true_literal(ast,
		w.unit.toks(), condition))
	{
		return true;
	}
	w.ctx.report(w.unit, id, CONST_COND.name,
		"condition is determined by literals alone -- if this is a deliberate toggle, use $if for a compile-time condition instead");
	return true;
}

fn bool is_true_literal(Ast* ast, TokenList* toks,
	NodeId id) @local => ast.kind(id) == NodeKind.BOOL_LIT
	&& toks.text_at(ast.node(id).tok) == "true";

fn bool is_literal_condition(Ast* ast, TokenList* toks, NodeId id) @local
{
	NodeKind kind = ast.kind(id);
	if (kind == NodeKind.BOOL_LIT || kind == NodeKind.INT_LIT) return true;
	if (kind != NodeKind.BINARY) return false;
	TokenType op = toks.type_at(ast.node(id).tok);
	if (op != LESS && op != GREATER && op != LESS_EQ && op != GREATER_EQ
		&& op != EQEQ && op != NOT_EQUAL)
	{
		return false;
	}
	return is_literal(ast, ast.node(id).lhs) && is_literal(ast,
		ast.node(id).rhs);
}

fn bool is_literal(Ast* ast, NodeId id) @local
{
	switch (ast.kind(id))
	{
		case NodeKind.INT_LIT: case NodeKind.REAL_LIT: case NodeKind.BOOL_LIT:
		case NodeKind.STRING_LIT: case NodeKind.CHAR_LIT: case NodeKind.BYTES_LIT:
			return true;
		default: return false;
	}
}

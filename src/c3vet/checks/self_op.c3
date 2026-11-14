<*
 `self-op`: `a - a`, `a / a`, `a % a`, `a ^ a`, `a & a`, `a | a`.

 docs/CHECKS.md Family C. A BINARY node whose operator is one of these six
 and whose lhs and rhs are `same_expr` -- each has a constant result (`0`
 for `-`/`^`, `1` for `/`, `0` for `%`, and the operand itself for `&`/`|`),
 so the operation tells the reader nothing the constant wouldn't.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::core::mem::alloc;

const Check SELF_OP = {
	.name          = "self-op",
	.doc           = "self-operation: both operands are identical, always producing a constant",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_self_op,
	.make_state    = &make_self_op_state,
};

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct SelfOpWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_self_op_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, SelfOpWalker, { .ctx = ctx, .unit = u });

fn bool is_self_op_operator(TokenType t) @local
{
	switch (t)
	{
		case MINUS:
		case DIV:
		case MOD:
		case BIT_XOR:
		case AMP:
		case BIT_OR:
			return true;
		default:
			return false;
	}
}

fn bool visit_self_op(Ast* ast, NodeId id, any ctx) @local
{
	SelfOpWalker* w = (SelfOpWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.BINARY && is_self_op_operator(w.unit.toks().type_at(n.tok))
		&& c3vet::same_expr(ast, w.unit.toks(), n.lhs, n.rhs))
	{
		w.ctx.report(w.unit, id, "self-op",
			"self-operation: both operands are identical -- likely a typo for a different operand");
	}
	return true;
}

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

const Check SELF_OP = {
	.name          = "self-op",
	.doc           = "self-operation: both operands are identical, always producing a constant",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_self_op,
};

fn void run_self_op(Ctx* ctx, Unit* u)
{
	SelfOpWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_self_op, &w);
}

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct SelfOpWalker
{
	Ctx*  ctx;
	Unit* unit;
}

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
		w.ctx.report(w.unit, id, "self-op", "self-operation: both operands are identical");
	}
	return true;
}

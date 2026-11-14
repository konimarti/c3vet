<*
 `self-compare`: `a == a`, `a != a`, `a < a`, `a >= a` and the other four
 comparison operators.

 docs/CHECKS.md Family C. A BINARY node whose operator is a comparison and
 whose lhs and rhs are `same_expr` -- always true or always false, the
 comparison tells the reader nothing a literal `true`/`false` wouldn't.
*>
module c3vet;

import c3::parser;
import c3::lexer;

const Check SELF_COMPARE = {
	.name          = "self-compare",
	.doc           = "self-comparison: both sides of the comparison are identical",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_self_compare,
};

fn void run_self_compare(Ctx* ctx, Unit* u)
{
	SelfCompareWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_self_compare, &w);
}

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct SelfCompareWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool is_compare_op(TokenType t) @local
{
	switch (t)
	{
		case LESS:
		case GREATER:
		case LESS_EQ:
		case GREATER_EQ:
		case EQEQ:
		case NOT_EQUAL:
			return true;
		default:
			return false;
	}
}

fn bool visit_self_compare(Ast* ast, NodeId id, any ctx) @local
{
	SelfCompareWalker* w = (SelfCompareWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.BINARY && is_compare_op(w.unit.toks().type_at(n.tok))
		&& c3vet::same_expr(ast, w.unit.toks(), n.lhs, n.rhs))
	{
		w.ctx.report(w.unit, id, "self-compare", "self-comparison: both sides are identical");
	}
	return true;
}

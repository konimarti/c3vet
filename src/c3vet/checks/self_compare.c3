<*
 `self-compare`: `a == a`, `a != a`, `a < a`, `a >= a` and the other four
 comparison operators.

 Always true or always false. Operands with side effects (calls, `++`/`--`,
 assignments, dereferences) are not flagged.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::core::mem::alloc;

const Check SELF_COMPARE = {
	.name          = "self-compare",
	.doc           = "self-comparison: both sides of the comparison are identical",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_self_compare,
	.make_state    = &make_self_compare_state,
};

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct SelfCompareWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_self_compare_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, SelfCompareWalker, { .ctx = ctx, .unit = u });

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
		w.ctx.report(w.unit, id, "self-compare",
			"self-comparison: both sides are identical -- remove it, or use math::is_nan() if this is a NaN check");
	}
	return true;
}

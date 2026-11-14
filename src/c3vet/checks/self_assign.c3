<*
 `self-assign`: `a = a`, `obj.f = obj.f`, `arr[i] = arr[i]`.

 docs/CHECKS.md Family C. An ASSIGN node whose operator is plain `=` (not a
 compound form like `+=`, which genuinely changes the value) and whose lhs
 and rhs are `same_expr` -- assigning something to itself is always either
 dead code or a typo for a different name.
*>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check SELF_ASSIGN = {
	.name          = "self-assign",
	.doc           = "self-assignment: the right side is identical to the left",
	.tier          = Tier.SYNTAX,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_self_assign,
	.make_state    = &make_self_assign_state,
};

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct SelfAssignWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_self_assign_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, SelfAssignWalker, { .ctx = ctx, .unit = u });

fn bool visit_self_assign(Ast* ast, NodeId id, any ctx) @local
{
	SelfAssignWalker* w = (SelfAssignWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.ASSIGN && w.unit.toks().type_at(n.tok) == EQ
		&& c3vet::same_expr(ast, w.unit.toks(), n.lhs, n.rhs))
	{
		w.ctx.report(w.unit, id, "self-assign",
			"self-assignment: this assigns the same value to itself -- remove it, or fix the typo if a different name was meant");
	}
	return true;
}

<*
 `self-assign`: `a = a`, `obj.f = obj.f`, `arr[i] = arr[i]`.

 docs/CHECKS.md Family C. An ASSIGN node whose operator is plain `=` (not a
 compound form like `+=`, which genuinely changes the value) and whose lhs
 and rhs are `same_expr` -- assigning something to itself is always either
 dead code or a typo for a different name.
*>
module c3vet;

import c3::parser;

const Check SELF_ASSIGN = {
	.name          = "self-assign",
	.doc           = "self-assignment: the right side is identical to the left",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_self_assign,
};

fn void run_self_assign(Ctx* ctx, Unit* u)
{
	SelfAssignWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_self_assign, &w);
}

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct SelfAssignWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_self_assign(Ast* ast, NodeId id, any ctx) @local
{
	SelfAssignWalker* w = (SelfAssignWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.ASSIGN && w.unit.toks().type_at(n.tok) == EQ
		&& c3vet::same_expr(ast, w.unit.toks(), n.lhs, n.rhs))
	{
		w.ctx.report(w.unit, id, "self-assign", "self-assignment: this assigns the same value to itself");
	}
	return true;
}

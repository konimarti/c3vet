<*
 `defer-in-loop`: a `defer` statement lexically inside a loop body.

 NOTE for whoever reviews this check's FP count: the lane brief and
 docs/CHECKS.md:115 both describe this check's premise as "`defer` runs at
 *function* exit, not per iteration" -- that is factually wrong for C3.
 Verified directly against the compiler (see this lane's commit message):
 `defer` is scope-scoped, not function-scoped, and fires once at the end of
 *each* iteration for FOR/FOREACH/WHILE/DO alike. The doc string and report
 message below have deliberately been written to not repeat that claim --
 they flag the construct without asserting a false semantics. Purely
 structural otherwise: a hand-rolled recursive walk with a loop-depth
 counter, since `parser::walk`'s visitor has no "leaving this node" hook to
 decrement on.
*>
module c3vet;

import c3::parser;

const Check DEFER_IN_LOOP = {
	.name          = "defer-in-loop",
	.doc           = "a defer statement lexically inside a loop body",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_defer_in_loop,
};

struct DeferInLoopWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn void run_defer_in_loop(Ctx* ctx, Unit* u)
{
	DeferInLoopWalker w = { .ctx = ctx, .unit = u };
	walk_defer(u.ast(), u.root(), 0, &w);
}

fn bool is_loop_kind(NodeKind kind) @local
	=> kind == NodeKind.FOR || kind == NodeKind.FOREACH || kind == NodeKind.FOREACH_R ||
	kind == NodeKind.WHILE || kind == NodeKind.DO;

<* A defer's loop-nesting is relative to its own enclosing function, never a caller's. *>
fn bool starts_own_scope(NodeKind kind) @local
	=> kind == NodeKind.FN_DECL || kind == NodeKind.MACRO_DECL || kind == NodeKind.LAMBDA;

fn void walk_defer(Ast* ast, NodeId id, int depth, DeferInLoopWalker* w) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.DEFER && depth > 0)
	{
		w.ctx.report(w.unit, id, "defer-in-loop", "defer statement is lexically inside a loop body");
	}

	int child_depth = depth;
	if (is_loop_kind(n.kind)) { child_depth = depth + 1; }
	else if (starts_own_scope(n.kind)) { child_depth = 0; }

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) walk_defer(ast, c, child_depth, w);
	}
	else
	{
		walk_defer(ast, n.lhs, child_depth, w);
		walk_defer(ast, n.rhs, child_depth, w);
	}
}

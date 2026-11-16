<*
 `defer-in-loop`: a `defer` statement lexically inside a loop body.


 `defer` is scope-scoped in C3: it fires at the end of each loop iteration,
 not once at function exit. A reader coming from a language where `defer`
 is function-scoped (Go, most notably) may expect a loop-body `defer` to
 run once at the end. The check surfaces the construct for a second look; it
 does not claim either behavior is wrong.
*>
module c3vet;

import c3::parser;

const Check DEFER_IN_LOOP = {
	.name          = "defer-in-loop",
	.doc           = "a defer statement lexically inside a loop body runs every iteration, not once",
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
		w.ctx.report(w.unit, id, "defer-in-loop",
			"defer inside a loop body runs every iteration, not once at the end -- move it outside the loop if that's not what you want");
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

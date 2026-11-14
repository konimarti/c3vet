<* Detect repeated conditions or block bodies inside one if/else-if chain. *>
module c3vet;

import c3::parser;
import std::collections::list;

const Check DUP_BRANCH = {
	.name          = "dup-branch",
	.doc           = "an if/else-if chain repeats an earlier condition or block",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_dup_branch,
};

struct DupBranchWalker
{
	Ctx*          ctx;
	Unit*         unit;
	List{NodeId}  else_if_continuations;
}

fn void run_dup_branch(Ctx* ctx, Unit* u)
{
	DupBranchWalker w = { .ctx = ctx, .unit = u };
	w.else_if_continuations.tinit();
	parser::walk(u.ast(), u.root(), &visit_dup_branch, &w);
}

fn bool visit_dup_branch(Ast* ast, NodeId id, any context) @local
{
	DupBranchWalker* w = (DupBranchWalker*)context;
	if (ast.kind(id) != NodeKind.IF || is_else_if_continuation(&w.else_if_continuations, id)) return true;

	List{NodeId} conditions;
	List{NodeId} bodies;
	conditions.tinit();
	bodies.tinit();
	NodeId branch = id;
	while (branch != parser::NONE && ast.kind(branch) == NodeKind.IF)
	{
		NodeId[] kids = ast.children(branch);
		if (kids.len != 3) break;
		NodeId condition = kids[0];
		NodeId body = kids[1];
		foreach (earlier : conditions)
		{
			if (same_shape(w.unit.ast(), w.unit.toks(), earlier, condition))
			{
				w.ctx.report(w.unit, branch, DUP_BRANCH.name, "duplicate condition in if/else-if chain");
				break;
			}
		}
		if (ast.kind(body) == NodeKind.BLOCK)
		{
			foreach (earlier : bodies)
			{
				if (same_shape(w.unit.ast(), w.unit.toks(), earlier, body))
				{
					w.ctx.report(w.unit, branch, DUP_BRANCH.name, "duplicate block body in if/else-if chain");
					break;
				}
			}
			bodies.push(body);
		}
		conditions.push(condition);

		NodeId otherwise = kids[2];
		if (otherwise != parser::NONE && ast.kind(otherwise) == NodeKind.IF)
		{
			w.else_if_continuations.push(otherwise);
			branch = otherwise;
			continue;
		}
		if (otherwise != parser::NONE && ast.kind(otherwise) == NodeKind.BLOCK)
		{
			foreach (earlier : bodies)
			{
				if (same_shape(w.unit.ast(), w.unit.toks(), earlier, otherwise))
				{
					w.ctx.report(w.unit, otherwise, DUP_BRANCH.name, "duplicate block body in if/else-if chain");
					break;
				}
			}
		}
		break;
	}
	return true;
}

fn bool is_else_if_continuation(List{NodeId}* ids, NodeId id) @local
{
	foreach (candidate : *ids) if (candidate == id) return true;
	return false;
}

<*
 `unused-label`: a declared label (`FOO: while (...) { ... }`) never targeted
 by a `break`/`continue` naming it.

 Labels are function-scoped (grammar.y's `optional_label` only ever attaches
 to the statement it prefixes within one function body), so this scans each
 `FN_DECL`'s body in isolation rather than the whole file -- two functions
 that each declare their own `FOO:` label, one using it and one not, must
 not cross-contaminate. See `testdata/unused-label.c3` for exactly that case.

 Filed as `Tier.SYNTAX` per the Phase 2 lane instructions: once scoped
 correctly to one `FN_DECL` at a time, this needs nothing beyond the AST and
 token text, despite CHECKS.md's table placement in the project-tier family.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::core::mem::alloc;

const Check UNUSED_LABEL = {
	.name          = "unused-label",
	.doc           = "A declared label never targeted by a break/continue in the same function.",
	.tier          = Tier.SYNTAX,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_unused_label,
	.make_state    = &make_unused_label_state,
};

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct UnusedLabelWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_unused_label_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, UnusedLabelWalker, { .ctx = ctx, .unit = u });

struct LoopLabel
{
	NodeId node;
	String name;
}

fn bool visit_unused_label(Ast* ast, NodeId id, any ctx) @local
{
	UnusedLabelWalker* w = (UnusedLabelWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL) return true;

	TokenList* toks = w.unit.toks();
	List{LoopLabel} labels;
	labels.tinit();
	List{String} targets;
	targets.tinit();
	collect_labels_and_targets(ast, toks, n.rhs, &labels, &targets);

	foreach (l : labels)
	{
		bool used = false;
		foreach (t : targets) if (t == l.name) { used = true; break; }
		if (!used)
		{
			w.ctx.report(w.unit, l.node, "unused-label", "label '%s' is never used", l.name);
		}
	}
	return false;
}

<* Collects every LABEL declaration and every labelled break/continue target under `id`. *>
fn void collect_labels_and_targets(Ast* ast, TokenList* toks, NodeId id,
                                   List{LoopLabel}* labels, List{String}* targets) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.LABEL)
	{
		labels.push({ .node = id, .name = toks.text_at(n.tok) });
	}
	else if (n.kind == NodeKind.BREAK || n.kind == NodeKind.CONTINUE)
	{
		if (n.lhs != parser::NONE)
		{
			targets.push(toks.text_at(ast.node(n.lhs).tok));
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) collect_labels_and_targets(ast, toks, c, labels, targets);
		return;
	}
	collect_labels_and_targets(ast, toks, n.lhs, labels, targets);
	collect_labels_and_targets(ast, toks, n.rhs, labels, targets);
}

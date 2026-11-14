<* Warn when a try binding is never used in its branch. *>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check UNUSED_TRY_BINDING = {
	.name          = "unused-try-binding",
	.doc           = "a try binding is never read in its branch",
	.tier          = Tier.LOCAL,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_unused_try_binding,
	.make_state    = &make_unused_try_binding_state,
};

struct UnusedTryBindingWalker { Ctx* ctx; Unit* unit; }

fn any make_unused_try_binding_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, UnusedTryBindingWalker, { .ctx = ctx, .unit = u });

fn bool visit_unused_try_binding(Ast* ast, NodeId id, any context) @local
{
	UnusedTryBindingWalker* w = (UnusedTryBindingWalker*)context;
	if (ast.kind(id) != NodeKind.IF) return true;
	NodeId[] kids = ast.children(id);
	if (kids.len < 2 || kids[0] == parser::NONE) return true;
	NodeId binding = parser::NONE;
	NodeId expression = kids[0];
	if (ast.kind(expression) == NodeKind.VAR_DECL)
	{
		binding = expression;
		expression = ast.node(expression).rhs;
	}
	if (expression == parser::NONE || ast.kind(expression) != NodeKind.TRY_EXPR) return true;
	if (binding == parser::NONE)
	{
		NodeId operand = ast.node(expression).lhs;
		if (operand == parser::NONE || ast.kind(operand) != NodeKind.VAR_DECL) return true;
		binding = operand;
	}
	String name = w.unit.toks().text_at(ast.node(binding).tok);
	if (!c3vet::is_read(ast, w.unit.toks(), kids[1], name))
	{
		w.ctx.report(w.unit, id, UNUSED_TRY_BINDING.name, "try binding '%s' is never read in this branch", name);
	}
	return true;
}

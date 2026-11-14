<* Warn when a catch binding is never used in its branch. *>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check UNUSED_CATCH_BINDING = {
	.name          = "unused-catch-binding",
	.doc           = "a catch binding is never read in its branch",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_unused_catch_binding,
	.make_state    = &make_unused_catch_binding_state,
};

struct UnusedCatchBindingWalker { Ctx* ctx; Unit* unit; }

fn any make_unused_catch_binding_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, UnusedCatchBindingWalker, { .ctx = ctx, .unit = u });

fn bool visit_unused_catch_binding(Ast* ast, NodeId id, any context) @local
{
	UnusedCatchBindingWalker* w = (UnusedCatchBindingWalker*)context;
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
	if (expression == parser::NONE || ast.kind(expression) != NodeKind.CATCH_EXPR) return true;
	if (binding == parser::NONE)
	{
		NodeId operand = ast.node(expression).lhs;
		if (operand == parser::NONE || ast.kind(operand) != NodeKind.VAR_DECL) return true;
		binding = operand;
	}
	String name = w.unit.toks().text_at(ast.node(binding).tok);
	if (!c3vet::is_read(ast, w.unit.toks(), kids[1], name))
	{
		w.ctx.report(w.unit, id, UNUSED_CATCH_BINDING.name, "catch binding '%s' is never read in this branch", name);
	}
	return true;
}

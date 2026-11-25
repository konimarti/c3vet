<*
 `redundant-zero-init`: `T x = { };` on a local.

 Locals are zero-initialized, so the `= { }` adds nothing: declare it as
 `T x;`. Off by default: this encodes a style policy, not a bug. Rules come
 from Christoffer Lerno's review of an LLM-written benchmark suite
 (kostya/LangArena#33).
*>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check REDUNDANT_ZERO_INIT = {
	.name          = "redundant-zero-init",
	.doc           = "An explicit = { } on a local, "
		"which is zero-initialized anyway.",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_redundant_zero_init,
	.make_state    = &make_redundant_zero_init_state,
};

struct RedundantZeroInitWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_redundant_zero_init_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, RedundantZeroInitWalker, { .ctx = ctx, .unit = u });

fn bool visit_redundant_zero_init(Ast* ast, NodeId id, any ctx) @local
{
	RedundantZeroInitWalker* w = (RedundantZeroInitWalker*)ctx;
	Node* n = ast.node(id);
	// a const needs its value, so its `= { }` stays
	if (n.kind == NodeKind.VAR_DECL && n.lhs != parser::NONE
		&& w.unit.toks().type_at(n.first_tok) != CONST
		&& n.rhs != parser::NONE && ast.kind(n.rhs) == NodeKind.INIT_LIST
		&& ast.children(n.rhs).len == 0)
	{
		w.ctx.report(w.unit, id, "redundant-zero-init",
			"`= { }` on a local is redundant -- locals are zero-initialized, so declare it without an initializer");
	}
	return true;
}

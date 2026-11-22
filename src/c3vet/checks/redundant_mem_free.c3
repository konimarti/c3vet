<*
 `redundant-mem-free`: `mem::` in front of `free`, where it is noise.

 - `mem::free(p)` -- `free` is a `@builtin` taking `void*`, so write `free(p)`.
 - `mem::free(s.ptr)` on a slice `s` -- write `free(s)`.

 The slice rule needs the declared type of `s`, so it only fires when that
 type is visible in the same function. Off by default: this encodes a style
 policy, not a bug. Rules come from Christoffer Lerno's review of an
 LLM-written benchmark suite (kostya/LangArena#33).
*>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check REDUNDANT_MEM_FREE = {
	.name          = "redundant-mem-free",
	.doc           =
		"mem::free where free is enough: mem::free(p) is free(p), and "
		"mem::free(s.ptr) on a slice is free(s)",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_redundant_mem_free,
	.make_state    = &make_redundant_mem_free_state,
};

struct RedundantMemFreeWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_redundant_mem_free_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, RedundantMemFreeWalker, { .ctx = ctx, .unit = u });

fn bool visit_redundant_mem_free(Ast* ast, NodeId id, any ctx) @local
{
	RedundantMemFreeWalker* w = (RedundantMemFreeWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL)
	{
		scan_fn_body(ast, id, n.rhs, &check_mem_free_call, w);
	}
	return true;
}

fn void check_mem_free_call(Ast* ast, NodeId fn_decl, NodeId id, any ctx)
	@local
{
	if (ast.kind(id) != NodeKind.CALL) return;
	RedundantMemFreeWalker* w = (RedundantMemFreeWalker*)ctx;
	NodeId[] kids = ast.children(id);
	if (kids.len < 2
		|| !is_mem_callee(ast, w.unit.toks(), kids[0], "free"))
	{
		return;
	}

	NodeId arg = kids[1];
	if (slice_ptr_base(w.unit, fn_decl, arg) != parser::NONE)
	{
		w.ctx.report(w.unit, id, "redundant-mem-free",
			"mem::free(s.ptr) on a slice -- free takes the slice directly: write free(s)");
		return;
	}
	w.ctx.report(w.unit, id, "redundant-mem-free",
		"mem::free is just free here -- free is a builtin function, so drop the namespace");
}

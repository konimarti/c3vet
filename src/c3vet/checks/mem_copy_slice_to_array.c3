<*
 `mem-copy-slice-to-array`: `mem::copy(&arr, src.ptr, n)` into a fixed array
 from a slice. Use slice assignment instead: `arr[:count] = src[:count];`. Note
 that `count` is in elements, while `mem::copy` takes `n` in bytes.

 The rule needs the declared type of `arr` and `src`, so it only fires when
 those types are visible in the same function. Off by default: this encodes a
 style policy, not a bug. Rules come from Christoffer Lerno's review of an
 LLM-written benchmark suite (kostya/LangArena#33).
*>
module c3vet;

import c3::parser;
import std::core::mem::alloc;

const Check MEM_COPY_SLICE_TO_ARRAY = {
	.name          = "mem-copy-slice-to-array",
	.doc           =
		"mem::copy of a slice into a fixed array: use slice assignment, "
		"which counts elements, not bytes",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_mem_copy_slice_to_array,
	.make_state    = &make_mem_copy_slice_to_array_state,
};

struct MemCopySliceToArrayWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_mem_copy_slice_to_array_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, MemCopySliceToArrayWalker, { .ctx = ctx, .unit = u });

fn bool visit_mem_copy_slice_to_array(Ast* ast, NodeId id, any ctx) @local
{
	MemCopySliceToArrayWalker* w = (MemCopySliceToArrayWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL)
	{
		scan_fn_body(ast, id, n.rhs, &check_mem_copy_call, w);
	}
	return true;
}

fn void check_mem_copy_call(Ast* ast, NodeId fn_decl, NodeId id, any ctx)
	@local
{
	if (ast.kind(id) != NodeKind.CALL) return;
	MemCopySliceToArrayWalker* w = (MemCopySliceToArrayWalker*)ctx;
	TokenList* toks = w.unit.toks();
	NodeId[] kids = ast.children(id);
	if (kids.len != 4 || !is_mem_callee(ast, toks, kids[0], "copy")) return;

	NodeId dst_addr = kids[1];
	if (ast.kind(dst_addr) != NodeKind.UNARY
		|| toks.text_at(ast.node(dst_addr).tok) != "&")
	{
		return;
	}
	NodeId dst = ast.node(dst_addr).lhs;
	if (dst == parser::NONE || ast.kind(dst) != NodeKind.IDENT) return;
	NodeId dst_type =
		w.unit.scopes.declared_type(fn_decl, toks.text_at(ast.node(dst).tok));
	if (dst_type == parser::NONE || ast.kind(dst_type) != NodeKind.TYPE_ARRAY)
	{
		return;
	}

	if (slice_ptr_base(w.unit, fn_decl, kids[2]) == parser::NONE) return;

	w.ctx.report(w.unit, id, "mem-copy-slice-to-array",
		"mem::copy of a slice into an array -- use slice assignment, arr[:count] = src[:count], where count is in elements, not the bytes mem::copy takes");
}

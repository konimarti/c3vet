<*
 `idiomatic-c3`: C3 code that compiles but is written the way C is written.

 - `mem::free(p)` -- `free` is a `@builtin` taking `void*`, so the `mem::`
   prefix is noise. `mem::free(s.ptr)` on a slice `s` should be `free(s)`.
 - `T x = { };` -- locals are zero-initialized, so the `= { }` adds nothing.
 - `mem::copy(&arr, src.ptr, n)` into a fixed array from a slice -- use
   `arr[:n] = src[:n];`.
 - `if (catch v) { x = {}; } else { x = v; }` -- use `x = v ?? {};`.

 The `mem::copy` and `.ptr` rules need the declared type of a local or
 parameter, so they only fire when that type is visible in the same function.
 Off by default: this encodes a style policy, not a bug. Rules come from
 Christoffer Lerno's review of an LLM-written benchmark suite (kostya/LangArena#33).
*>
module c3vet;

import c3::lexer;
import c3::parser;
import std::core::mem::alloc;

const Check IDIOMATIC_C3 = {
	.name          = "idiomatic-c3",
	.doc           =
		"C-style code where idiomatic C3 is shorter: mem::free, = { } "
		"on a local, mem::copy into an array, catch-and-assign-default",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_idiomatic_c3,
	.make_state    = &make_idiomatic_c3_state,
};

struct IdiomaticC3Walker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_idiomatic_c3_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, IdiomaticC3Walker, { .ctx = ctx, .unit = u });

fn bool visit_idiomatic_c3(Ast* ast, NodeId id, any ctx) @local
{
	IdiomaticC3Walker* w = (IdiomaticC3Walker*)ctx;
	Node* n = ast.node(id);

	if (n.kind == NodeKind.FN_DECL)
	{
		idc_scan(w, id, n.rhs);
	}
	else if (n.kind == NodeKind.VAR_DECL && n.lhs != parser::NONE
		&& n.rhs != parser::NONE && ast.kind(n.rhs) == NodeKind.INIT_LIST
		&& ast.children(n.rhs).len == 0)
	{
		w.ctx.report(w.unit, id, "idiomatic-c3",
			"`= { }` on a local is redundant -- locals are zero-initialized, so declare it without an initializer");
	}
	return true;
}

<* Walks one function body. Nested functions, macros and lambdas have their own scope. *>
fn void idc_scan(IdiomaticC3Walker* w, NodeId fn_decl, NodeId id) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL
		|| n.kind == NodeKind.LAMBDA)
	{
		return;
	}

	if (n.kind == NodeKind.CALL)
	{
		idc_check_call(w, fn_decl, id);
		idc_check_copy(w, fn_decl, id);
	}
	else if (n.kind == NodeKind.IF)
	{
		idc_check_catch_default(w, id);
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) idc_scan(w, fn_decl, c);
	}
	else
	{
		idc_scan(w, fn_decl, n.lhs);
		idc_scan(w, fn_decl, n.rhs);
	}
}

fn void idc_check_call(IdiomaticC3Walker* w, NodeId fn_decl, NodeId id) @local
{
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	NodeId[] kids = ast.children(id);
	if (kids.len < 2 || !idc_is_mem_callee(ast, toks, kids[0], "free")) return;

	NodeId arg = kids[1];
	// `mem::free(s.ptr)` where `s` is a slice: the slice itself is the argument.
	if (idc_is_slice_ptr(w, fn_decl, arg) != parser::NONE)
	{
		w.ctx.report(w.unit, id, "idiomatic-c3",
			"mem::free(s.ptr) on a slice -- free takes the slice directly: write free(s)");
		return;
	}
	w.ctx.report(w.unit, id, "idiomatic-c3",
		"mem::free is just free here -- free is a builtin function, so drop the namespace");
}

<* `mem::copy(&arr, src.ptr, n)` with `arr` a fixed array and `src` a slice. *>
fn void idc_check_copy(IdiomaticC3Walker* w, NodeId fn_decl, NodeId id) @local
{
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	NodeId[] kids = ast.children(id);
	if (kids.len != 4 || !idc_is_mem_callee(ast, toks, kids[0], "copy")) return;

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

	if (idc_is_slice_ptr(w, fn_decl, kids[2]) == parser::NONE) return;

	w.ctx.report(w.unit, id, "idiomatic-c3",
		"mem::copy of a slice into an array -- use slice assignment: arr[:n] = src[:n];");
}

<*
 `if (catch v) { x = {}; } else { x = v; }`, with `v` a plain identifier.
 The `catch err = v` form is also accepted; the binding must not be read.
*>
fn void idc_check_catch_default(IdiomaticC3Walker* w, NodeId id) @local
{
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	NodeId[] kids = ast.children(id);
	if (kids.len != 3 || kids[0] == parser::NONE || kids[2] == parser::NONE)
	{
		return;
	}
	if (ast.kind(kids[0]) != NodeKind.CATCH_EXPR) return;

	NodeId value = ast.node(kids[0]).lhs;
	if (value != parser::NONE && ast.kind(value) == NodeKind.VAR_DECL)
	{
		value = ast.node(value).rhs;
	}
	if (value == parser::NONE || ast.kind(value) != NodeKind.IDENT) return;
	String v = toks.text_at(ast.node(value).tok);

	NodeId then_assign = idc_only_assign(ast, kids[1]);
	NodeId else_assign = idc_only_assign(ast, kids[2]);
	if (then_assign == parser::NONE || else_assign == parser::NONE) return;

	NodeId then_val = ast.node(then_assign).rhs;
	NodeId else_val = ast.node(else_assign).rhs;
	if (ast.kind(then_val) != NodeKind.INIT_LIST
		|| ast.children(then_val).len != 0)
	{
		return;
	}
	if (ast.kind(else_val) != NodeKind.IDENT
		|| toks.text_at(ast.node(else_val).tok) != v)
	{
		return;
	}
	if (!c3vet::same_expr(ast, toks, ast.node(then_assign).lhs,
		ast.node(else_assign).lhs))
	{
		return;
	}

	w.ctx.report(w.unit, id, "idiomatic-c3",
		"catch and assign a default -- use the optional else operator: x = v ?? {};");
}

<* The single `x = value;` assignment in a `{ ... }` block, or NONE. *>
fn NodeId idc_only_assign(Ast* ast, NodeId block) @local
{
	if (block == parser::NONE || ast.kind(block) != NodeKind.BLOCK)
	{
		return parser::NONE;
	}
	NodeId[] stmts = ast.children(block);
	if (stmts.len != 1 || ast.kind(stmts[0]) != NodeKind.EXPR_STMT)
	{
		return parser::NONE;
	}
	NodeId expr = ast.node(stmts[0]).lhs;
	if (expr == parser::NONE || ast.kind(expr) != NodeKind.ASSIGN)
	{
		return parser::NONE;
	}
	return expr;
}

<* The identifier `s` when `arg` is `s.ptr` and `s` is a slice local or parameter, else NONE. *>
fn NodeId idc_is_slice_ptr(IdiomaticC3Walker* w, NodeId fn_decl,
	NodeId arg) @local
{
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	if (arg == parser::NONE || ast.kind(arg) != NodeKind.MEMBER_ACCESS)
	{
		return parser::NONE;
	}
	Node* m = ast.node(arg);
	if (m.rhs == parser::NONE || toks.text_at(ast.node(m.rhs).tok) != "ptr")
	{
		return parser::NONE;
	}
	NodeId obj = m.lhs;
	if (obj == parser::NONE || ast.kind(obj) != NodeKind.IDENT)
	{
		return parser::NONE;
	}
	NodeId t =
		w.unit.scopes.declared_type(fn_decl, toks.text_at(ast.node(obj).tok));
	if (t == parser::NONE || ast.kind(t) != NodeKind.TYPE_SLICE)
	{
		return parser::NONE;
	}
	return obj;
}

<* True when `callee` names `mem::<name>` (or a longer path ending in it). *>
fn bool idc_is_mem_callee(Ast* ast,
	TokenList* toks, NodeId callee, String name) @local
{
	if (callee == parser::NONE || ast.kind(callee) != NodeKind.PATH)
	{
		return false;
	}
	Node* p = ast.node(callee);
	return p.last_tok >= p.first_tok + 2
		&& toks.text_at(p.last_tok) == name
		&& toks.text_at(p.last_tok - 2) == "mem";
}

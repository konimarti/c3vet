<*
 `temp-escapes-fn`: a `talloc`/`tmem`-derived pointer or slice returned from a function.

 docs/CHECKS.md Family A. Returning memory allocated with the temporary allocator
 escapes the caller or local frame and is a use-after-free once the temp arena resets.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::io;
import std::core::mem::alloc;

const Check TEMP_ESCAPES_FN = {
	.name          = "temp-escapes-fn",
	.doc           = "temp-allocated memory returned from a function",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.visit         = &visit_temp_escapes_fn,
	.make_state    = &make_temp_escapes_fn_state,
};

fn any make_temp_escapes_fn_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, TempEscapesFnWalker, { .ctx = ctx, .unit = u });

struct TempEscapesFnWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_temp_escapes_fn(Ast* ast, NodeId id, any ctx) @local
{
	TempEscapesFnWalker* w = (TempEscapesFnWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL) return true;

	// Collect names of all temp-origin locals in this function.
	LocalDecl[] locals = w.unit.scopes.locals_in(id);
	List{String} temp_locals;
	temp_locals.tinit();
	foreach (d : locals)
	{
		if (d.decl == parser::NONE || ast.kind(d.decl) != NodeKind.VAR_DECL) continue;
		Node* vn = ast.node(d.decl);
		if (is_temp_origin_init(ast, w.unit.toks(), vn.rhs))
		{
			temp_locals.push(d.name);
		}
	}

	// Walk function body inspecting return statements.
	check_returns_in_body(w, n.rhs, &temp_locals);
	return true;
}

fn void check_returns_in_body(TempEscapesFnWalker* w, NodeId id, List{String}* temp_locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	Node* n = ast.node(id);

	// Do not descend into nested functions or lambdas.
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;

	if (n.kind == NodeKind.RETURN)
	{
		NodeId val = n.lhs;
		if (val != parser::NONE && is_temp_val(ast, w.unit.toks(), val, temp_locals))
		{
			w.ctx.report(w.unit, id, "temp-escapes-fn",
				"temp-allocated memory returned from a function");
		}
		return;
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) check_returns_in_body(w, c, temp_locals);
	}
	else
	{
		check_returns_in_body(w, n.lhs, temp_locals);
		check_returns_in_body(w, n.rhs, temp_locals);
	}
}

<* True when `val` resolves to a temp-origin local. *>
fn bool is_temp_val(Ast* ast, TokenList* toks, NodeId val, List{String}* temp_locals) @local
{
	if (val == parser::NONE) return false;

	// Peel casts, slices, and unary & / * operators.
	NodeId cur = val;
	while (cur != parser::NONE)
	{
		Node* cn = ast.node(cur);
		if (cn.kind == NodeKind.CAST)
		{
			cur = cn.rhs;
		}
		else if (cn.kind == NodeKind.SLICE)
		{
			NodeId[] kids = ast.children(cur);
			cur = kids.len ? kids[0] : parser::NONE;
		}
		else if (cn.kind == NodeKind.UNARY)
		{
			TokenType tt = toks.type_at(cn.tok);
			if (tt == AMP || tt == STAR)
			{
				cur = cn.lhs;
			}
			else
			{
				break;
			}
		}
		else
		{
			break;
		}
	}

	if (cur != parser::NONE && ast.kind(cur) == NodeKind.IDENT)
	{
		String name = toks.text_at(ast.node(cur).tok);
		foreach (tname : *temp_locals)
		{
			if (tname == name) return true;
		}
	}
	return false;
}

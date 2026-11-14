<*
 `temp-wrong-free`: `mem::free` or `free` called on a `talloc`-derived pointer.

 docs/CHECKS.md Family A. Freeing memory allocated by the temporary allocator
 with the heap/general free function is invalid and leads to undefined behavior.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;

const Check TEMP_WRONG_FREE = {
	.name          = "temp-wrong-free",
	.doc           = "calling free on temp-allocated memory",
	.tier          = Tier.LOCAL,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_temp_wrong_free,
};

fn void run_temp_wrong_free(Ctx* ctx, Unit* u)
{
	TempWrongFreeWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_temp_wrong_free, &w);
}

struct TempWrongFreeWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_temp_wrong_free(Ast* ast, NodeId id, any ctx) @local
{
	TempWrongFreeWalker* w = (TempWrongFreeWalker*)ctx;
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

	// Walk function body inspecting free calls.
	check_frees_in_body(w, n.rhs, &temp_locals);
	return true;
}

fn void check_frees_in_body(TempWrongFreeWalker* w, NodeId id, List{String}* temp_locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	Node* n = ast.node(id);

	// Do not descend into nested functions or lambdas.
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;

	if (n.kind == NodeKind.CALL)
	{
		NodeId[] kids = ast.children(id);
		if (kids.len >= 2)
		{
			NodeId callee = kids[0];
			if (is_free_callee(ast, w.unit.toks(), callee))
			{
				NodeId arg = kids[1];
				if (is_temp_origin_init(ast, w.unit.toks(), arg) || is_temp_val_wrong_free(ast, w.unit.toks(), arg, temp_locals))
				{
					w.ctx.report(w.unit, id, "temp-wrong-free",
						"free called on temp-allocated memory");
				}
			}
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) check_frees_in_body(w, c, temp_locals);
	}
	else
	{
		check_frees_in_body(w, n.lhs, temp_locals);
		check_frees_in_body(w, n.rhs, temp_locals);
	}
}

fn bool is_free_callee(Ast* ast, TokenList* toks, NodeId callee) @local
{
	if (callee == parser::NONE) return false;
	NodeKind k = ast.kind(callee);
	if (k == NodeKind.IDENT)
	{
		return toks.text_at(ast.node(callee).tok) == "free";
	}
	if (k == NodeKind.PATH)
	{
		if (toks.text_at(ast.node(callee).last_tok) != "free") return false;
		NodeId[] pkids = ast.children(callee);
		if (pkids.len == 2)
		{
			String modname = toks.text_at(ast.node(pkids[0]).tok);
			return modname == "mem";
		}
		return true;
	}
	return false;
}

fn bool is_temp_val_wrong_free(Ast* ast, TokenList* toks, NodeId val, List{String}* temp_locals) @local
{
	if (val == parser::NONE) return false;

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

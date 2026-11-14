<*
 `temp-to-global`: a `talloc`-derived value assigned to a global or `tlocal` variable.

 docs/CHECKS.md Family A. Assigning memory allocated by the temporary allocator
 to a global or thread-local variable allows the temporary pointer to escape the
 current tick/arena lifetime, resulting in use-after-free once the arena resets.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;

const Check TEMP_TO_GLOBAL = {
	.name          = "temp-to-global",
	.doc           = "temp-allocated memory assigned to a global or thread-local variable",
	.tier          = Tier.LOCAL,
	.default_on    = true,
	.skip_on_error = true,
	.run           = &run_temp_to_global,
};

fn void run_temp_to_global(Ctx* ctx, Unit* u)
{
	TempToGlobalWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_temp_to_global, &w);
}

struct TempToGlobalWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_temp_to_global(Ast* ast, NodeId id, any ctx) @local
{
	TempToGlobalWalker* w = (TempToGlobalWalker*)ctx;
	Node* n = ast.node(id);

	if (n.kind == NodeKind.GLOBAL_DECL)
	{
		NodeId[] kids = ast.children(id);
		if (kids.len >= 2 && kids[1] != parser::NONE)
		{
			if (is_temp_origin_init(ast, w.unit.toks(), kids[1]))
			{
				w.ctx.report(w.unit, id, "temp-to-global",
					"temp-allocated memory assigned to a global or thread-local variable");
			}
		}
		return true;
	}

	if (n.kind != NodeKind.FN_DECL) return true;

	// In a function, collect local names, temp-origin locals, and static/tlocal locals.
	LocalDecl[] locals = w.unit.scopes.locals_in(id);
	List{String} temp_locals;
	temp_locals.tinit();
	List{String} local_names;
	local_names.tinit();
	List{String} tlocal_or_static_locals;
	tlocal_or_static_locals.tinit();

	foreach (d : locals)
	{
		local_names.push(d.name);
		if (d.decl != parser::NONE && ast.kind(d.decl) == NodeKind.VAR_DECL)
		{
			Node* vn = ast.node(d.decl);
			if (is_temp_origin_init(ast, w.unit.toks(), vn.rhs))
			{
				temp_locals.push(d.name);
			}
			if (is_local_tlocal_or_static(ast, w.unit.toks(), d.decl))
			{
				tlocal_or_static_locals.push(d.name);
				if (vn.rhs != parser::NONE && (is_temp_origin_init(ast, w.unit.toks(), vn.rhs) || is_temp_val_to_global(ast, w.unit.toks(), vn.rhs, &temp_locals)))
				{
					w.ctx.report(w.unit, d.decl, "temp-to-global",
						"temp-allocated memory assigned to a global or thread-local variable");
				}
			}
		}
	}

	// Walk function body inspecting assignments.
	check_assignments_in_body(w, n.rhs, &temp_locals, &local_names, &tlocal_or_static_locals);
	return true;
}

fn void check_assignments_in_body(TempToGlobalWalker* w, NodeId id, List{String}* temp_locals, List{String}* local_names, List{String}* tlocal_or_static_locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	Node* n = ast.node(id);

	// Do not descend into nested functions, macros, or lambdas.
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;

	// In an INIT_LIST, designated field initializers look like ASSIGN (.field = val). Skip them.
	if (n.kind == NodeKind.INIT_LIST) return;

	if (n.kind == NodeKind.ASSIGN)
	{
		NodeId lhs = n.lhs;
		NodeId rhs = n.rhs;
		if (rhs != parser::NONE && (is_temp_origin_init(ast, w.unit.toks(), rhs) || is_temp_val_to_global(ast, w.unit.toks(), rhs, temp_locals)))
		{
			if (is_target_global_or_tlocal(ast, w.unit.toks(), lhs, local_names, tlocal_or_static_locals))
			{
				w.ctx.report(w.unit, id, "temp-to-global",
					"temp-allocated memory assigned to a global or thread-local variable");
			}
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) check_assignments_in_body(w, c, temp_locals, local_names, tlocal_or_static_locals);
	}
	else
	{
		check_assignments_in_body(w, n.lhs, temp_locals, local_names, tlocal_or_static_locals);
		check_assignments_in_body(w, n.rhs, temp_locals, local_names, tlocal_or_static_locals);
	}
}

fn bool is_local_tlocal_or_static(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE || ast.kind(id) != NodeKind.VAR_DECL) return false;
	Node* n = ast.node(id);
	uint start = n.first_tok;
	if (n.lhs != parser::NONE)
	{
		start = ast.node(n.lhs).first_tok;
	}
	for (uint i = 1; i <= 3 && start >= i; i++)
	{
		TokenType tt = toks.type_at(start - i);
		if (tt == TLOCAL || tt == STATIC) return true;
		if (tt == EOS || tt == LBRACE || tt == RBRACE) break;
	}
	return false;
}

fn bool is_target_global_or_tlocal(Ast* ast, TokenList* toks, NodeId target, List{String}* local_names, List{String}* tlocal_or_static_locals) @local
{
	if (target == parser::NONE) return false;
	NodeKind k = ast.kind(target);
	if (k == NodeKind.PATH) return true;
	if (k == NodeKind.IDENT)
	{
		String name = toks.text_at(ast.node(target).tok);
		bool is_local = false;
		foreach (lname : *local_names)
		{
			if (lname == name)
			{
				is_local = true;
				break;
			}
		}
		if (!is_local) return true; // Undeclared in local scope => global/module-scoped
		foreach (tname : *tlocal_or_static_locals)
		{
			if (tname == name) return true;
		}
	}
	return false;
}

fn bool is_temp_val_to_global(Ast* ast, TokenList* toks, NodeId val, List{String}* temp_locals) @local
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

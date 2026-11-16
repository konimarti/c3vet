<*
 `temp-escapes-struct`: a talloc stored into a field of a struct that is then returned.

 Returning such a struct (by value or pointer) hands the caller a reference to
 memory that is freed at the next arena reset.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::core::mem::alloc;

const Check TEMP_ESCAPES_STRUCT = {
	.name          = "temp-escapes-struct",
	.doc           = "temp-allocated memory stored into struct field and returned",
	.tier          = Tier.LOCAL,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_temp_escapes_struct,
	.make_state    = &make_temp_escapes_struct_state,
};

fn any make_temp_escapes_struct_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, TempEscapesStructWalker, { .ctx = ctx, .unit = u });

struct TempEscapesStructWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_temp_escapes_struct(Ast* ast, NodeId id, any ctx) @local
{
	TempEscapesStructWalker* w = (TempEscapesStructWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL && n.kind != NodeKind.MACRO_DECL) return true;

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

	List{String} returned_vars;
	returned_vars.tinit();
	collect_returned_vars(w, n.rhs, &returned_vars, &temp_locals);

	// Check field assignments and struct initializers.
	check_struct_escapes(w, n.rhs, &returned_vars, &temp_locals);
	return true;
}

fn void collect_returned_vars(TempEscapesStructWalker* w, NodeId id,
                             List{String}* returned_vars, List{String}* temp_locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	Node* n = ast.node(id);

	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;

	if (n.kind == NodeKind.RETURN)
	{
		NodeId val = n.lhs;
		if (val != parser::NONE)
		{
			// Direct return of struct literal containing temp memory:
			NodeId peeled_lit = peel_casts(ast, val);
			if (ast.kind(peeled_lit) == NodeKind.INIT_LIST && init_list_has_temp(ast, toks, peeled_lit, temp_locals))
			{
				w.ctx.report(w.unit, id, "temp-escapes-struct",
					"temp-allocated memory stored into struct field and returned -- allocate the field's value with a non-temp allocator before storing it");
			}

			// Return of local variable:
			NodeId peeled_id = peel_expr(ast, toks, val);
			if (peeled_id != parser::NONE && ast.kind(peeled_id) == NodeKind.IDENT)
			{
				returned_vars.push(toks.text_at(ast.node(peeled_id).tok));
			}
		}
		return;
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) collect_returned_vars(w, c, returned_vars, temp_locals);
	}
	else
	{
		collect_returned_vars(w, n.lhs, returned_vars, temp_locals);
		collect_returned_vars(w, n.rhs, returned_vars, temp_locals);
	}
}

fn void check_struct_escapes(TempEscapesStructWalker* w, NodeId id,
                            List{String}* returned_vars, List{String}* temp_locals) @local
{
	if (id == parser::NONE) return;
	Ast* ast = w.unit.ast();
	TokenList* toks = w.unit.toks();
	Node* n = ast.node(id);

	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;

	if (n.kind == NodeKind.VAR_DECL)
	{
		String var_name = toks.text_at(n.tok);
		if (is_in_list(var_name, returned_vars))
		{
			NodeId init_lit = peel_casts(ast, n.rhs);
			if (ast.kind(init_lit) == NodeKind.INIT_LIST && init_list_has_temp(ast, toks, init_lit, temp_locals))
			{
				w.ctx.report(w.unit, id, "temp-escapes-struct",
					"temp-allocated memory stored into struct field and returned -- allocate the field's value with a non-temp allocator before storing it");
			}
		}
	}
	else if (n.kind == NodeKind.ASSIGN)
	{
		NodeId target = n.lhs;
		NodeId val = n.rhs;

		// Case 1: obj.field = temp_val
		if (ast.kind(target) == NodeKind.MEMBER_ACCESS)
		{
			NodeId obj_id = peel_expr(ast, toks, ast.node(target).lhs);
			if (obj_id != parser::NONE && ast.kind(obj_id) == NodeKind.IDENT)
			{
				String obj_name = toks.text_at(ast.node(obj_id).tok);
				if (is_in_list(obj_name, returned_vars) && struct_val_is_temp(ast, toks, val, temp_locals))
				{
					w.ctx.report(w.unit, id, "temp-escapes-struct",
						"temp-allocated memory stored into struct field and returned -- allocate the field's value with a non-temp allocator before storing it");
				}
			}
		}
		// Case 2: obj = { .field = temp_val }
		else if (ast.kind(target) == NodeKind.IDENT)
		{
			String obj_name = toks.text_at(ast.node(target).tok);
			if (is_in_list(obj_name, returned_vars))
			{
				NodeId init_lit = peel_casts(ast, val);
				if (ast.kind(init_lit) == NodeKind.INIT_LIST && init_list_has_temp(ast, toks, init_lit, temp_locals))
				{
					w.ctx.report(w.unit, id, "temp-escapes-struct",
						"temp-allocated memory stored into struct field and returned -- allocate the field's value with a non-temp allocator before storing it");
				}
			}
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) check_struct_escapes(w, c, returned_vars, temp_locals);
	}
	else
	{
		check_struct_escapes(w, n.lhs, returned_vars, temp_locals);
		check_struct_escapes(w, n.rhs, returned_vars, temp_locals);
	}
}

fn bool struct_val_is_temp(Ast* ast, TokenList* toks, NodeId val, List{String}* temp_locals) @local
{
	if (val == parser::NONE) return false;
	if (is_temp_origin_init(ast, toks, val)) return true;

	NodeId cur = peel_expr(ast, toks, val);
	if (cur != parser::NONE && ast.kind(cur) == NodeKind.IDENT)
	{
		String name = toks.text_at(ast.node(cur).tok);
		return is_in_list(name, temp_locals);
	}
	return false;
}

fn bool init_list_has_temp(Ast* ast, TokenList* toks, NodeId init_list_id, List{String}* temp_locals) @local
{
	if (init_list_id == parser::NONE || ast.kind(init_list_id) != NodeKind.INIT_LIST) return false;
	foreach (elem : ast.children(init_list_id))
	{
		NodeId val = elem;
		if (ast.kind(elem) == NodeKind.ASSIGN)
		{
			val = ast.node(elem).rhs;
		}
		if (struct_val_is_temp(ast, toks, val, temp_locals)) return true;
	}
	return false;
}

fn NodeId peel_casts(Ast* ast, NodeId id) @local
{
	NodeId cur = id;
	while (cur != parser::NONE && ast.kind(cur) == NodeKind.CAST)
	{
		cur = ast.node(cur).rhs;
	}
	return cur;
}

fn NodeId peel_expr(Ast* ast, TokenList* toks, NodeId id) @local
{
	NodeId cur = id;
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
			if (tt == AMP || tt == STAR) { cur = cn.lhs; }
			else { break; }
		}
		else
		{
			break;
		}
	}
	return cur;
}

fn bool is_in_list(String item, List{String}* list) @local
{
	foreach (s : *list)
	{
		if (s == item) return true;
	}
	return false;
}

<*
 `missing-format-attr`: a function whose last parameter is `args...` which passes
 an earlier `String` parameter to a `@format` callee, but lacks `@format(n)` itself.

 docs/CHECKS.md Family F. Adding `@format(n)` lets c3c type-check every call site
 of the wrapper against the format string forever.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;

const Check MISSING_FORMAT_ATTR = {
	.name          = "missing-format-attr",
	.doc           = "function forwarding format string and varargs without @format attribute",
	.tier          = Tier.PROJECT,
	.default_on    = true,
	.skip_on_error = true,
	.run           = &run_missing_format_attr,
};

fn void run_missing_format_attr(Ctx* ctx, Unit* u)
{
	if (!ctx.table) return;
	MissingFormatAttrWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_missing_format_attr, &w);
}

struct MissingFormatAttrWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_missing_format_attr(Ast* ast, NodeId id, any ctx) @local
{
	MissingFormatAttrWalker* w = (MissingFormatAttrWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FN_DECL && n.kind != NodeKind.MACRO_DECL) return true;

	NodeId sig_id = n.lhs;
	if (sig_id == parser::NONE || ast.kind(sig_id) != NodeKind.SIGNATURE) return true;
	if (has_format_attr(ast, w.unit.toks(), sig_id)) return true;

	// Extract declared parameters.
	List{NodeId} params;
	params.tinit();
	foreach (c : ast.children(sig_id))
	{
		if (c != parser::NONE && ast.kind(c) == NodeKind.PARAM)
		{
			params.push(c);
		}
	}
	if (params.len() < 2) return true;

	// The last parameter must be a varargs parameter (...).
	NodeId last_param = params[params.len() - 1];
	if (!is_varargs_param(ast, w.unit.toks(), last_param)) return true;
	String varargs_name = w.unit.toks().text_at(ast.node(last_param).tok);
	if (!varargs_name.len) return true;

	// Collect names of all earlier String-typed parameters.
	List{String} fmt_params;
	fmt_params.tinit();
	for (sz i = 0; i < params.len() - 1; i++)
	{
		NodeId p = params[i];
		NodeId[] pkids = ast.children(p);
		if (pkids.len && pkids[0] != parser::NONE)
		{
			Node* tn = ast.node(pkids[0]);
			if (tn.kind == NodeKind.TYPE_NAME && w.unit.toks().text_at(tn.tok) == "String")
			{
				fmt_params.push(w.unit.toks().text_at(ast.node(p).tok));
			}
		}
	}
	if (fmt_params.len() == 0) return true;

	bool reported = false;
	check_body_calls(w, n.rhs, id, &fmt_params, varargs_name, &reported);
	return true;
}

fn void check_body_calls(MissingFormatAttrWalker* w, NodeId id, NodeId fn_node,
	List{String}* fmt_params, String varargs_name, bool* reported) @local
{
	if (id == parser::NONE || *reported) return;
	Ast* ast = w.unit.ast();
	Node* n = ast.node(id);

	// Do not descend into nested functions, macros, or lambdas.
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL || n.kind == NodeKind.LAMBDA) return;

	if (n.kind == NodeKind.CALL)
	{
		NodeId[] kids = ast.children(id);
		if (kids.len >= 2)
		{
			String callee_name = call_name(ast, w.unit.toks(), kids[0]);
			if (callee_name.len)
			{
				int fmt_idx = w.ctx.table.format_param_of(callee_name);
				if (fmt_idx >= 0 && (sz)(1 + fmt_idx) < kids.len)
				{
					NodeId fmt_arg = kids[1 + fmt_idx];
					if (is_ident_in_list(ast, w.unit.toks(), fmt_arg, fmt_params))
					{
						if (call_forwards_varargs(ast, w.unit.toks(), kids[1..], varargs_name))
						{
							w.ctx.report(w.unit, fn_node, "missing-format-attr",
								"forwards its format string to '%s' (which has @format(%d)) but has no @format itself",
								callee_name, fmt_idx);
							*reported = true;
							return;
						}
					}
				}
			}
		}
	}

	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id))
		{
			check_body_calls(w, c, fn_node, fmt_params, varargs_name, reported);
			if (*reported) return;
		}
	}
	else
	{
		check_body_calls(w, n.lhs, fn_node, fmt_params, varargs_name, reported);
		if (!*reported) check_body_calls(w, n.rhs, fn_node, fmt_params, varargs_name, reported);
	}
}

fn bool has_format_attr(Ast* ast, TokenList* toks, NodeId sig_id) @local
{
	if (sig_id == parser::NONE) return false;
	foreach (c : ast.children(sig_id))
	{
		if (c == parser::NONE || ast.kind(c) != NodeKind.ATTR) continue;
		if (toks.text_at(ast.node(c).tok) == "@format") return true;
	}
	return false;
}

fn bool is_varargs_param(Ast* ast, TokenList* toks, NodeId param_id) @local
{
	if (param_id == parser::NONE || ast.kind(param_id) != NodeKind.PARAM) return false;
	Node* n = ast.node(param_id);
	for (uint i = n.first_tok; i <= n.last_tok; i++)
	{
		if (toks.type_at(i) == TokenType.ELLIPSIS) return true;
	}
	return false;
}

fn bool is_ident_in_list(Ast* ast, TokenList* toks, NodeId id, List{String}* list) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.IDENT) return false;
	String name = toks.text_at(n.tok);
	foreach (item : *list)
	{
		if (item == name) return true;
	}
	return false;
}

fn bool call_forwards_varargs(Ast* ast, TokenList* toks, NodeId[] args, String varargs_name) @local
{
	foreach (arg : args)
	{
		if (arg == parser::NONE) continue;
		Node* n = ast.node(arg);
		NodeId target = arg;
		if (n.kind == NodeKind.SPLAT)
		{
			target = n.lhs;
		}
		if (target != parser::NONE && ast.kind(target) == NodeKind.IDENT)
		{
			if (toks.text_at(ast.node(target).tok) == varargs_name) return true;
		}
	}
	return false;
}

fn String call_name(Ast* ast, TokenList* toks, NodeId id) @local
{
	if (id == parser::NONE) return "";
	Node* n = ast.node(id);
	if (n.kind == NodeKind.IDENT || n.kind == NodeKind.TYPE_NAME) return toks.text_at(n.tok);
	if (n.kind == NodeKind.MEMBER_ACCESS) return call_name(ast, toks, n.rhs);
	if (n.kind == NodeKind.PATH) return toks.text_at(n.last_tok);
	return "";
}

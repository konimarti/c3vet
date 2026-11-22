<* Find integer-literal division whose result is used as a floating value. *>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::core::mem::alloc;

const Check CONST_INT_DIV_TO_FLOAT = {
	.name          = "const-int-div-to-float",
	.doc           = "integer division of literals is converted to a floating value",
	.tier          = Tier.SYNTAX,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_const_int_div,
	.make_state    = &make_const_int_div_state,
};

struct ConstIntDivWalker
{
	Ctx*         ctx;
	Unit*        unit;
	List{NodeId} reported;
}

fn any make_const_int_div_state(Ctx* ctx, Unit* u, Allocator a) @local
{
	ConstIntDivWalker* w = alloc::new(a, ConstIntDivWalker, { .ctx = ctx, .unit = u });
	w.reported.init(a);
	return w;
}

fn bool visit_const_int_div(Ast* ast, NodeId id, any context) @local
{
	ConstIntDivWalker* w = (ConstIntDivWalker*)context;
	Node* n = ast.node(id);
	if ((n.kind == NodeKind.VAR_DECL || n.kind == NodeKind.CAST) && is_float_type(ast, w.unit.toks(), n.lhs))
	{
		find_float_divisions(ast, w.unit.toks(), n.rhs, w);
	}
	else if (n.kind == NodeKind.FN_DECL)
	{
		NodeId[] signature = ast.children(n.lhs);
		if (signature.len && is_float_type(ast, w.unit.toks(), signature[0]))
		{
			if (ast.kind(n.rhs) == NodeKind.BLOCK)
			{
				find_float_returns(ast, w.unit.toks(), n.rhs, w);
			}
			else
			{
				find_float_divisions(ast, w.unit.toks(), n.rhs, w);
			}
		}
	}
	return true;
}

fn bool is_float_type(Ast* ast, TokenList* toks, NodeId type) @local
{
	if (type == parser::NONE || ast.kind(type) != NodeKind.TYPE_BASE) return false;
	String name = toks.text_at(ast.node(type).tok);
	return name == "float" || name == "double" || name == "float16" || name == "bfloat" || name == "float128";
}

fn void find_float_divisions(Ast* ast, TokenList* toks, NodeId id, ConstIntDivWalker* w) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.CAST)
	{
		if (is_float_type(ast, toks, n.lhs)) find_float_divisions(ast, toks, n.rhs, w);
		return;
	}
	if (n.kind == NodeKind.CALL)
	{
		return;
	}
	if (n.kind == NodeKind.BINARY && toks.type_at(n.tok) == DIV &&
		ast.kind(n.lhs) == NodeKind.INT_LIT && ast.kind(n.rhs) == NodeKind.INT_LIT &&
		!contains_node(&w.reported, id))
	{
		w.reported.push(id);
		w.ctx.report(w.unit, id, CONST_INT_DIV_TO_FLOAT.name,
			"integer division of literals is converted to a floating value -- make one literal a float (e.g. 1.0 / 2) to get the division you probably meant");
	}
	if (n.kind.is_list_bearing())
	{
		foreach (child : ast.children(id)) find_float_divisions(ast, toks, child, w);
	}
	else
	{
		find_float_divisions(ast, toks, n.lhs, w);
		find_float_divisions(ast, toks, n.rhs, w);
	}
}

fn void find_float_returns(Ast* ast, TokenList* toks, NodeId id, ConstIntDivWalker* w) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.FN_DECL || n.kind == NodeKind.MACRO_DECL) return;
	if (n.kind == NodeKind.RETURN)
	{
		find_float_divisions(ast, toks, n.lhs, w);
		return;
	}
	if (n.kind.is_list_bearing())
	{
		foreach (child : ast.children(id)) find_float_returns(ast, toks, child, w);
	}
	else
	{
		find_float_returns(ast, toks, n.lhs, w);
		find_float_returns(ast, toks, n.rhs, w);
	}
}

fn bool contains_node(List{NodeId}* ids, NodeId id) @local
{
	foreach (candidate : *ids) if (candidate == id) return true;
	return false;
}

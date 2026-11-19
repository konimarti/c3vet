<*
 Helpers for recognizing `mem::` calls and slice `.ptr` arguments.

 Used by `redundant-mem-free` and `mem-copy-slice-to-array`. Both need the
 declared type of a local or parameter, so they only fire when that type is
 visible in the same function.
*>
module c3vet;

import c3::lexer;
import c3::parser;

<*
 The identifier `s` when `arg` is `s.ptr` and `s` is a slice local or
 parameter of `fn_decl`, else NONE.
*>
fn NodeId slice_ptr_base(Unit* unit, NodeId fn_decl, NodeId arg)
{
	Ast* ast = unit.ast();
	TokenList* toks = unit.toks();
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
	NodeId t = unit.scopes.declared_type(fn_decl,
		toks.text_at(ast.node(obj).tok));
	if (t == parser::NONE || ast.kind(t) != NodeKind.TYPE_SLICE)
	{
		return parser::NONE;
	}
	return obj;
}

<* True when `callee` names `mem::<name>` (or a longer path ending in it). *>
fn bool is_mem_callee(Ast* ast, TokenList* toks, NodeId callee, String name)
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

<*
 `loop-no-advance`: a `for` loop whose increment slot is empty, where nothing
 in the loop body can change the condition: no identifier in it, or field of
 one, is assigned, `++`/`--`'d or address-taken, and none has a method called
 on it. A condition made of calls only, like `c.next()`, may advance the loop
 itself and is left alone.

 False positives are possible: the counter may advance through a pointer
 alias, or the loop may exit via `break` before any advance is needed.
 `break` and `return` are not special-cased: they would hide a forgotten
 increment.
*>
module c3vet;

import c3::lexer;
import c3::parser;
import std::collections::list;
import std::core::mem::alloc;

const Check LOOP_NO_ADVANCE = {
	.name          = "loop-no-advance",
	.doc           =
		"A for loop with no increment clause whose "
		"condition variables never change in the body.",
	.tier          = Tier.SYNTAX,
	.default_on    = true,
	.skip_on_error = true,
	.visit         = &visit_loop_no_advance,
	.make_state    = &make_loop_no_advance_state,
};

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct LoopNoAdvanceWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn any make_loop_no_advance_state(Ctx* ctx, Unit* u, Allocator a) @local
	=> alloc::new(a, LoopNoAdvanceWalker, { .ctx = ctx, .unit = u });

fn bool visit_loop_no_advance(Ast* ast, NodeId id, any ctx) @local
{
	LoopNoAdvanceWalker* w = (LoopNoAdvanceWalker*)ctx;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.FOR) return true;

	NodeId[] kids = ast.children(id);
	NodeId cond = kids[1];
	NodeId incr = kids[2];
	NodeId body = kids[3];
	if (incr != parser::NONE || cond == parser::NONE) return true;

	TokenList* toks = w.unit.toks();
	List{String} names;
	names.tinit();
	collect_idents(ast, toks, cond, &names);
	if (!names.len()) return true;

	bool has_call;
	bool has_value;
	scan_condition(ast, toks, cond, &has_call, &has_value);
	if (has_call && !has_value) return true;

	String[] name_arr = names.to_tarray();
	if (!body_advances(ast, toks, body, name_arr))
	{
		w.ctx.report(w.unit, id, "loop-no-advance",
			"loop condition never advances in the body -- update the loop variable, or only a break or return can end the loop");
	}
	return true;
}

<* Every identifier name referenced anywhere in `id`'s subtree. *>
fn void collect_idents(Ast* ast, TokenList* toks, NodeId id,
	List{String}* out) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.IDENT)
	{
		out.push(toks.text_at(n.tok));
		return;
	}
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id)) collect_idents(ast, toks, c, out);
		return;
	}
	collect_idents(ast, toks, n.lhs, out);
	collect_idents(ast, toks, n.rhs, out);
}

<*
 Note whether the condition `id` has a call, and whether it reads a value the
 body would have to change: any identifier other than a constant, a called
 function or a method's receiver.
*>
fn void scan_condition(Ast* ast, TokenList* toks, NodeId id, bool* has_call,
	bool* has_value) @local
{
	if (id == parser::NONE) return;
	Node* n = ast.node(id);
	switch (n.kind)
	{
		case IDENT:
			if (toks.type_at(n.tok) != CONST_IDENT) *has_value = true;
		case MEMBER_ACCESS:
			// the right side only names the member
			scan_condition(ast, toks, n.lhs, has_call, has_value);
		case CALL:
		{
			*has_call = true;
			NodeId[] kids = ast.children(id);
			NodeId callee = member_base(ast, kids[0]);
			if (ast.kind(callee) != NodeKind.IDENT
				&& ast.kind(callee) != NodeKind.PATH)
			{
				scan_condition(ast, toks, callee, has_call, has_value);
			}
			foreach (arg : kids[1..])
			{
				scan_condition(ast, toks, arg, has_call, has_value);
			}
		}
		default:
			if (n.kind.is_list_bearing())
			{
				foreach (c : ast.children(id))
				{
					scan_condition(ast, toks, c, has_call, has_value);
				}
			}
			else
			{
				scan_condition(ast, toks, n.lhs, has_call, has_value);
				scan_condition(ast, toks, n.rhs, has_call, has_value);
			}
	}
}

<* `a.b.c` -> `a`; anything that is not a member access is returned as is. *>
fn NodeId member_base(Ast* ast, NodeId id) @local
{
	while (id != parser::NONE && ast.kind(id) == NodeKind.MEMBER_ACCESS)
	{
		id = ast.node(id).lhs;
	}
	return id;
}

<* True when `id` is one of `names`, or a field of one. *>
fn bool is_one_of(Ast* ast, TokenList* toks, NodeId id, String[] names) @local
{
	id = member_base(ast, id);
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.IDENT) return false;
	String text = toks.text_at(n.tok);
	foreach (nm : names) if (nm == text) return true;
	return false;
}

<*
 True when anywhere in `id`'s subtree, one of `names` or a field of one is
 assigned, `++`/`--`'d or address-taken, or has a method called on it.
*>
fn bool body_advances(Ast* ast,
	TokenList* toks, NodeId id, String[] names) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.ASSIGN && is_one_of(ast, toks, n.lhs, names))
	{
		return true;
	}
	if (n.kind == NodeKind.CALL)
	{
		NodeId callee = ast.children(id)[0];
		if (ast.kind(callee) == NodeKind.MEMBER_ACCESS
			&& is_one_of(ast, toks, callee, names))
		{
			return true;
		}
	}
	if (n.kind == NodeKind.UNARY || n.kind == NodeKind.POSTFIX)
	{
		TokenType op = toks.type_at(n.tok);
		if ((op == PLUSPLUS || op == MINUSMINUS || op == AMP) && is_one_of(ast,
			toks, n.lhs, names))
		{
			return true;
		}
	}
	if (n.kind.is_list_bearing())
	{
		foreach (c : ast.children(id))
		{
			if (body_advances(ast, toks, c, names)) return true;
		}
		return false;
	}
	return body_advances(ast, toks, n.lhs, names)
		|| body_advances(ast, toks, n.rhs, names);
}

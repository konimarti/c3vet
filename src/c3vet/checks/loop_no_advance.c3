<*
 `loop-no-advance`: a `for` loop whose increment slot is empty, where no
 identifier referenced in the condition is ever assigned, `++`/`--`'d, or
 address-taken (`&ident`) anywhere in the loop body.

 This is the highest false-positive-risk check in this lane: the counter may
 advance through a pointer alias the AST cannot see through, or the loop may
 exit entirely via `break` before any advance is needed. Conservative here
 means thorough in the search, not lenient in the verdict -- the body scan
 walks every nested block/if/switch/loop looking for any of the three
 advancing shapes before concluding "never advances", so a real advance
 anywhere in the body is never missed. It does not special-case `break`:
 whether that turns out to matter is a measured-FP-count question, answered
 in the commit message, not a guess baked into the logic.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::core::mem::alloc;

const Check LOOP_NO_ADVANCE = {
	.name          = "loop-no-advance",
	.doc           = "A for loop with no increment clause whose condition variables never change in the body.",
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

	String[] name_arr = names.to_tarray();
	if (!body_advances(ast, toks, body, name_arr))
	{
		w.ctx.report(w.unit, id, "loop-no-advance", "loop condition never advances in the body");
	}
	return true;
}

<* Every identifier name referenced anywhere in `id`'s subtree. *>
fn void collect_idents(Ast* ast, TokenList* toks, NodeId id, List{String}* out) @local
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

<* True when `id` is a leaf IDENT naming one of `names`. *>
fn bool is_one_of(Ast* ast, TokenList* toks, NodeId id, String[] names) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind != NodeKind.IDENT) return false;
	String text = toks.text_at(n.tok);
	foreach (nm : names) if (nm == text) return true;
	return false;
}

<*
 True when anywhere in `id`'s subtree, one of `names` is assigned,
 `++`/`--`'d, or address-taken.
*>
fn bool body_advances(Ast* ast, TokenList* toks, NodeId id, String[] names) @local
{
	if (id == parser::NONE) return false;
	Node* n = ast.node(id);
	if (n.kind == NodeKind.ASSIGN && is_one_of(ast, toks, n.lhs, names)) return true;
	if (n.kind == NodeKind.UNARY || n.kind == NodeKind.POSTFIX)
	{
		TokenType op = toks.type_at(n.tok);
		if ((op == PLUSPLUS || op == MINUSMINUS || op == AMP) && is_one_of(ast, toks, n.lhs, names))
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
	return body_advances(ast, toks, n.lhs, names) || body_advances(ast, toks, n.rhs, names);
}
